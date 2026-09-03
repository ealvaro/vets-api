# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

RSpec.describe 'IvcChampva::V1::ChampvaCardsController', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :loa3, first_name: 'Alex', last_name: 'Doe', birth_date: '1990-01-15') }
  let(:feature_enabled) { true }
  let(:ves_client) { instance_double(IvcChampva::VesApi::Client) }
  # A real SQA ChampvaDigitalCardData response, sanitized (ICNs, street, institution). Carries the
  # full dataset: sensitivityInfo, demographics.contactInfo.addresses, and vfmpProgramsInfo, plus
  # the demographics fields we ignore. Its status is "Ineligible" over a 2002-02-22 -> 2024-06-01
  # window, so it never yields a card; tests travel_to to pick which ineligible verdict applies.
  let(:card_dataset_response) { ves_fixture('champva_digital_card_data') }
  # The same response with only the eligibility entry swapped, so the address and sensitivity
  # blocks stay exactly as VES returns them. Its window is open through 2099, so it is enrolled
  # without travel_to.
  let(:eligible_dataset_response) do
    with_eligibility(
      card_dataset_response,
      'status' => 'Eligible',
      'reason' => 'P&T',
      'eligibilityDates' => [{ 'startDate' => '2020-01-01', 'endDate' => '2099-12-31' }]
    )
  end
  # What VES returns for an ICN that is not a CHAMPVA beneficiary: empty data, not an error.
  let(:veteran_dataset_response) { ves_fixture('champva_digital_card_data_veteran') }
  let(:covering_ee_summary) do
    {
      'vfmpProgramsInfo' => {
        'relationships' => [
          {
            'relationshipType' => 'Child',
            'champvaEligibilities' => [
              {
                'status' => 'Eligible',
                'reason' => 'P&T',
                'eligibilityDates' => [
                  { 'startDate' => '2011-01-01', 'endDate' => '2099-01-31' }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  def ves_fixture(name)
    JSON.parse(File.read("modules/ivc_champva/spec/fixtures/ves/#{name}.json"))['data']
  end

  # deep_merge cannot reach through the relationships array, so the eligibility entry is dug out
  # and merged directly.
  def with_eligibility(dataset, overrides)
    dataset.deep_dup.tap do |data|
      data.dig('vfmpProgramsInfo', 'relationships', 0, 'champvaEligibilities', 0).merge!(overrides)
    end
  end

  def make_request
    get '/ivc_champva/v1/champva_card'
  end

  def beneficiary_info
    response.parsed_body.dig('data', 'attributes', 'beneficiary_infos').first
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:champva_benefits_card, anything).and_return(feature_enabled)
    allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
    allow(ves_client).to receive(:get_ee_summary).and_return(covering_ee_summary)
  end

  describe 'GET /ivc_champva/v1/champva_card' do
    context 'when not logged in' do
      it 'returns unauthorized' do
        make_request

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when logged in' do
      before { sign_in_as(user) }

      context 'when the feature flag is disabled' do
        let(:feature_enabled) { false }

        it 'returns not found' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body['error_message']).to eq('Not found')
        end
      end

      context 'when the user has not verified their identity' do
        let(:user) { create(:user) }

        it 'returns forbidden' do
          make_request

          expect(response).to have_http_status(:forbidden)
          expect(response.parsed_body.dig('error', 'code')).to eq('not_verified')
        end

        it 'does not call VES' do
          make_request

          expect(ves_client).not_to have_received(:get_ee_summary)
        end
      end

      context 'when the user has no ICN' do
        before { allow_any_instance_of(User).to receive(:icn).and_return(nil) }

        it 'returns unprocessable content' do
          make_request

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body.dig('error', 'code')).to eq('missing_icn')
        end
      end

      context 'when the user is an eligible beneficiary' do
        let(:covering_ee_summary) { eligible_dataset_response }

        it 'returns one fully populated beneficiary_infos entry' do
          make_request

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq(
            'data' => {
              'type' => 'champva_card',
              'attributes' => {
                'role' => 'beneficiary',
                'beneficiary_infos' => [
                  {
                    'icn' => user.icn,
                    'full_name' => 'Alex Doe',
                    'date_of_birth' => '1990-01-15',
                    'mailing_address' => {
                      'line1' => '123 EXAMPLE ST',
                      'line2' => nil,
                      'line3' => nil,
                      'city' => 'BRANDON',
                      'state' => 'FL',
                      'province_code' => nil,
                      'zip_code' => '33511',
                      'zip_plus4' => '2216',
                      'postal_code' => nil,
                      'country' => 'USA'
                    },
                    'enrollment_status' => 'eligible',
                    'eligibility_status' => 'Eligible',
                    'eligibility_reason' => 'P&T',
                    'sensitive_record' => false,
                    'relationship_type' => 'Child',
                    'effective_date' => '2020/01/01',
                    'expiration_date' => '2099/12/31'
                  }
                ]
              }
            }
          )
        end
      end

      context 'when the user is an eligible beneficiary and the dataset omits demographics' do
        # VES supplies demographics now, but it is optional in the contract, so a record without
        # it must still produce a card rather than failing.
        it 'returns the card with a null mailing_address' do
          make_request

          expect(response).to have_http_status(:ok)
          expect(beneficiary_info).to include(
            'enrollment_status' => 'eligible',
            'full_name' => 'Alex Doe',
            'mailing_address' => nil,
            'sensitive_record' => nil,
            'relationship_type' => 'Child'
          )
        end
      end

      context 'when VES reports the beneficiary ineligible inside a live window' do
        # The shipped fixture is status "Ineligible" over a 2002 -> 2024 window, so before this
        # ticket it was issued a card on the dates alone.
        let(:covering_ee_summary) { card_dataset_response }

        it 'returns not found with the ineligible code' do
          travel_to(Date.new(2023, 1, 1)) do
            make_request

            expect(response).to have_http_status(:not_found)
            expect(response.parsed_body['error']).to eq(
              'code' => 'ineligible',
              'message' => IvcChampva::V1::ChampvaCardsController::INELIGIBLE_MESSAGE,
              'enrollment_status' => 'ineligible'
            )
          end
        end

        it 'returns no card data, since the frontend renders static content' do
          travel_to(Date.new(2023, 1, 1)) do
            make_request

            expect(response.parsed_body).not_to have_key('data')
          end
        end
      end

      context 'when the beneficiary is eligible but the dataset is sensitive' do
        let(:covering_ee_summary) do
          eligible_dataset_response.deep_merge('sensitivityInfo' => { 'sensitivityFlag' => true })
        end

        # The beneficiary is viewing their own record, so the flag is surfaced rather than
        # suppressing anything. The sponsor flow will use it to filter beneficiaries out.
        it 'returns the card with sensitive_record true' do
          make_request

          expect(response).to have_http_status(:ok)
          expect(beneficiary_info).to include(
            'enrollment_status' => 'eligible',
            'sensitive_record' => true
          )
        end
      end

      context 'when eligibility has expired' do
        let(:covering_ee_summary) { card_dataset_response }

        # Expiry is a flavor of ineligibility, so it shares the code and status. The specific
        # verdict rides along in enrollment_status for a frontend that wants to differentiate.
        it 'returns not found with the ineligible code and an expired enrollment_status' do
          travel_to(Date.new(2025, 1, 1)) do
            make_request

            expect(response).to have_http_status(:not_found)
            expect(response.parsed_body['error']).to include(
              'code' => 'ineligible',
              'enrollment_status' => 'expired'
            )
          end
        end
      end

      context 'when eligibility starts in the future' do
        let(:covering_ee_summary) do
          {
            'vfmpProgramsInfo' => {
              'relationships' => [
                {
                  'relationshipType' => 'Child',
                  'champvaEligibilities' => [
                    {
                      'status' => 'Eligible',
                      'eligibilityDates' => [
                        { 'startDate' => '2099-01-01', 'endDate' => '2100-01-31' }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        end

        it 'returns not found with the ineligible code and a not_yet_effective enrollment_status' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body['error']).to include(
            'code' => 'ineligible',
            'enrollment_status' => 'not_yet_effective'
          )
        end
      end

      context 'when the user is not a CHAMPVA beneficiary' do
        # Either a veteran/sponsor or someone with no CHAMPVA record: VES returns empty data for
        # both, so they cannot be told apart. The sponsor flow is disabled until the roster
        # endpoint exists, so both are reported as not enrolled.
        let(:covering_ee_summary) { veteran_dataset_response }

        it 'returns not enrolled' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body.dig('error', 'code')).to eq('not_enrolled')
        end
      end

      context 'when VES returns no eligibility relationships' do
        before do
          allow(ves_client).to receive(:get_ee_summary)
            .and_return({ 'vfmpProgramsInfo' => { 'relationships' => [] } })
        end

        it 'returns not enrolled' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body.dig('error', 'code')).to eq('not_enrolled')
        end
      end

      context 'when VES times out' do
        before do
          allow(ves_client).to receive(:get_ee_summary)
            .and_raise(IvcChampva::VesApi::VesApiTimeoutError, 'timeout')
        end

        it 'returns gateway timeout' do
          make_request

          expect(response).to have_http_status(:gateway_timeout)
          expect(response.parsed_body.dig('error', 'code')).to eq('upstream_timeout')
        end
      end

      context 'when VES returns an upstream error' do
        before do
          allow(ves_client).to receive(:get_ee_summary)
            .and_raise(IvcChampva::VesApi::VesApiError, 'response code: 500')
        end

        it 'returns bad gateway' do
          make_request

          expect(response).to have_http_status(:bad_gateway)
          expect(response.parsed_body.dig('error', 'code')).to eq('upstream_error')
        end
      end

      # The endpoint counters are what on-call reads, so every rendered outcome is asserted to
      # increment the right metric with the right reason tag. Rejections and failures are separate
      # metrics on purpose: a spike in ineligible beneficiaries must not be able to fire the alerts
      # that watch for VES being down.
      describe 'Datadog metrics' do
        let(:card_key) { "#{IvcChampva::Monitor::STATS_KEY}.benefits_card" }

        # make_request stays in the examples rather than a before hook here: hooks run outer to
        # inner, so a request issued at this level would fire before the nested contexts had
        # stubbed their failures.
        before { allow(StatsD).to receive(:increment).and_call_original }

        def expect_card_metric(suffix, *tags)
          expect(StatsD).to have_received(:increment)
            .with("#{card_key}.#{suffix}", tags: array_including(*tags))
        end

        def expect_no_card_metric(suffix)
          expect(StatsD).not_to have_received(:increment).with("#{card_key}.#{suffix}", anything)
        end

        context 'when card data is returned' do
          let(:covering_ee_summary) { eligible_dataset_response }

          it 'increments get and neither error metric' do
            make_request

            expect_card_metric('get')
            expect_no_card_metric('rejected')
            expect_no_card_metric('failed')
          end
        end

        context 'when the caller is not enrolled' do
          let(:covering_ee_summary) { veteran_dataset_response }

          it 'increments rejected tagged not_enrolled with its status' do
            make_request

            expect_card_metric('rejected', 'reason:not_enrolled', 'http_status:404')
            expect_no_card_metric('failed')
          end
        end

        context 'when the caller is ineligible' do
          let(:covering_ee_summary) do
            with_eligibility(card_dataset_response,
                             'eligibilityDates' => [{ 'startDate' => '2020-01-01', 'endDate' => '2099-12-31' }])
          end

          # Tagged with the specific verdict rather than the shared "ineligible" error code, so a
          # denial and an expiry can be told apart in Datadog without the frontend caring.
          it 'increments rejected tagged with the specific verdict' do
            make_request

            expect_card_metric('rejected', 'reason:ineligible', 'http_status:404')
          end
        end

        context 'when eligibility has expired' do
          let(:covering_ee_summary) { card_dataset_response }

          it 'increments rejected tagged expired rather than ineligible' do
            make_request

            expect_card_metric('rejected', 'reason:expired', 'http_status:404')
          end
        end

        context 'when the user has not verified their identity' do
          let(:user) { create(:user) }

          it 'increments rejected tagged not_verified' do
            make_request

            expect_card_metric('rejected', 'reason:not_verified', 'http_status:403')
          end
        end

        context 'when the user has no ICN' do
          before { allow_any_instance_of(User).to receive(:icn).and_return(nil) }

          it 'increments rejected tagged missing_icn' do
            make_request

            expect_card_metric('rejected', 'reason:missing_icn', 'http_status:422')
          end
        end

        context 'when the feature flag is disabled' do
          let(:feature_enabled) { false }

          # Counted so traffic hitting a disabled flag is visible during rollout; the reason tag
          # keeps it filterable out of the real rejections.
          it 'increments rejected tagged feature_disabled' do
            make_request

            expect_card_metric('rejected', 'reason:feature_disabled', 'http_status:404')
          end
        end

        context 'when VES times out' do
          before do
            allow(ves_client).to receive(:get_ee_summary)
              .and_raise(IvcChampva::VesApi::VesApiTimeoutError, 'timeout')
          end

          it 'increments failed and the VES call failure metric' do
            make_request

            expect_card_metric('failed', 'reason:upstream_timeout', 'http_status:504')
            expect_no_card_metric('rejected')
            expect(StatsD).to have_received(:increment).with(
              "#{IvcChampva::Monitor::STATS_KEY}.ves_call.failure",
              tags: array_including('ves_operation:ee_summary', 'reason:upstream_timeout',
                                    'error_class:IvcChampva::VesApi::VesApiTimeoutError')
            )
          end
        end

        context 'when VES returns an upstream error' do
          before do
            allow(ves_client).to receive(:get_ee_summary)
              .and_raise(IvcChampva::VesApi::VesApiError, 'response code: 403')
          end

          it 'increments failed and the VES call failure metric' do
            make_request

            expect_card_metric('failed', 'reason:upstream_error', 'http_status:502')
            expect_no_card_metric('rejected')
            expect(StatsD).to have_received(:increment).with(
              "#{IvcChampva::Monitor::STATS_KEY}.ves_call.failure",
              tags: array_including('ves_operation:ee_summary', 'reason:upstream_error',
                                    'error_class:IvcChampva::VesApi::VesApiError')
            )
          end
        end
      end
    end
  end
end
