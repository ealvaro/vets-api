# frozen_string_literal: true

require_relative '../../../support/helpers/rails_helper'
require_relative '../../../support/helpers/committee_helper'

require 'lighthouse/letters_generator/configuration'
require 'lighthouse/letters_generator/service'

RSpec.describe 'Mobile::V0::Letters', type: :request do
  include CommitteeHelper

  let(:letter_json) do
    {
      'data' =>
        {
          'id' => user.uuid,
          'type' => 'letter',
          'attributes' => {
            'letter' =>
            {
              'letterDescription' => 'This card verifies that you served honorably in the Armed Forces.',
              'letterContent' => [
                { 'contentKey' => 'front-of-card',
                  'contentTitle' => '<front of card>',
                  'content' =>
                  "This card is to serve as proof the individual listed below served honorably in the Uniformed \
Services of the United States. Jesse Gray 1708 Tiburon Blvd Tiburon, CA 94921 Effective as of: June 08, 2023 DoD \
ID Number: 1293307390 Date of Birth: December 15, 1954 Branch Of Service: Army"},
                {
                  'contentKey' => 'back-of-card',
                  'contentTitle' => '<back of card>',
                  'content' =>
                  "United States of America Department of Veterans Affairs General Benefit Information 1-800-827-1000 \
Health Care Information 1-877-222-VETS (8387) This card does not reflect entitlement to any benefits administered by \
the Department of Veterans Affairs or serve as proof of receiving such benefits."
                },
                {
                  'contentKey' => 'contact-us',
                  'contentTitle' => 'How You Can Contact Us',
                  'content' =>
                  "If you need general information about benefits and eligibility, please visit us at \
https://www.va.gov. Call us at 1-800-827-1000. Contact us using Telecommunications Relay Services (TTY) at 711 24/7. \
Send electronic inquiries through the Internet at https://www.va.gov/contact-us."
                }
              ]
            }
          }
        }
    }
  end

  let(:letters_body) do
    {
      'data' => {
        'id' => user.uuid,
        'type' => 'letters',
        'attributes' => {
          'letters' =>
            [
              {
                'name' => 'Benefit Summary and Service Verification Letter',
                'letterType' => 'benefit_summary'
              },
              {
                'name' => 'Benefit Verification Letter',
                'letterType' => 'benefit_verification'
              },
              {
                'name' => 'Civil Service Preference Letter',
                'letterType' => 'civil_service'
              },
              {
                'name' => 'Commissary Letter',
                'letterType' => 'commissary'
              },
              {
                'name' => 'Proof of Service Letter',
                'letterType' => 'proof_of_service'
              },
              # {
              #   'name' => 'Proof of Creditable Prescription Drug Coverage Letter',
              #   'letterType' => 'medicare_partd'
              # },
              # {
              #   'name' => 'Proof of Minimum Essential Coverage Letter',
              #   'letterType' => 'minimum_essential_coverage'
              # },
              {
                'name' => 'Service Verification Letter',
                'letterType' => 'service_verification'
              }
            ]
        }
      }
    }
  end

  let(:beneficiary_body) do
    { 'data' =>
       { 'id' => user.uuid,
         'type' => 'LettersBeneficiaryResponses',
         'attributes' =>
          { 'benefitInformation' =>
             { 'awardEffectiveDate' => '2016-02-04T17:51:56Z',
               'hasChapter35Eligibility' => true,
               'monthlyAwardAmount' => 2673.0,
               'serviceConnectedPercentage' => 2,
               'hasDeathResultOfDisability' => false,
               'hasSurvivorsIndemnityCompensationAward' => false,
               'hasSurvivorsPensionAward' => false,
               'hasAdaptedHousing' => false,
               'hasIndividualUnemployabilityGranted' => false,
               'hasNonServiceConnectedPension' => false,
               'hasServiceConnectedDisabilities' => true,
               'hasSpecialMonthlyCompensation' => false },
            'militaryService' =>
              [{ 'branch' => 'Army', 'characterOfService' => 'HONORABLE',
                 'enteredDate' => '2016-02-04T17:51:56Z', 'releasedDate' => '2016-02-04T17:51:56Z' }] } } }
  end

  let!(:user) { sis_user(icn: '24811694708759028') }

  before do
    token = 'abcdefghijklmnop'
    allow_any_instance_of(Lighthouse::LettersGenerator::Configuration).to receive(:get_access_token).and_return(token)
  end

  describe 'GET /mobile/v0/letters' do
    context 'when user does not have access' do
      let!(:user) { sis_user(participant_id: nil) }

      it 'returns forbidden' do
        get '/mobile/v0/letters', headers: sis_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with a valid lighthouse response' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      end

      it 'matches the letters schema' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters', headers: sis_headers
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq(letters_body)
          assert_schema_conform(200)
        end
      end

      it 'filters unlisted letter types' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_with_extra_types_200',
                         match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters', headers: sis_headers
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq(letters_body)
          assert_schema_conform(200)
        end
      end

      describe 'cst_letters_content_updates flag' do
        def expect_legacy_letter_content(response)
          expect(response).to have_http_status(:ok)
          letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
          letter_names = letters.map { |l| l['name'] }
          letter_types = letters.map { |l| l['letterType'] }

          expect(letter_names).to eq(letter_names.sort)
          expect(letter_types).not_to include('medicare_partd', 'minimum_essential_coverage')
          benefit_summary = letters.find { |l| l['letterType'] == 'benefit_summary' }
          expect(benefit_summary['name']).to eq('Benefit Summary and Service Verification Letter')

          # Legacy payload: every letter falls back to upstream names and carries no server description.
          expect(letters.map { |l| l['description'] }).to all(be_nil)
          benefit_verification = letters.find { |l| l['letterType'] == 'benefit_verification' }
          expect(benefit_verification['name']).not_to eq('Proof of VA income') if benefit_verification
        end

        context 'when :cst_letters_content_updates is disabled' do
          before do
            allow(Flipper).to receive(:enabled?).and_call_original
            allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
          end

          it 'applies legacy name overrides for benefit_summary' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              get '/mobile/v0/letters', headers: sis_headers
              expect(response).to have_http_status(:ok)
              letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
              benefit_summary = letters.find { |l| l['letterType'] == 'benefit_summary' }
              expect(benefit_summary['name']).to eq('Benefit Summary and Service Verification Letter')
            end
          end

          it 'applies legacy name overrides for foreign_medical_program' do
            service_double = instance_double(Lighthouse::LettersGenerator::Service)
            fmp_response = {
              letters: [
                { letterType: 'foreign_medical_program', name: 'Foreign Medical Program enrollment' }
              ],
              letter_destination: {}
            }
            allow(service_double).to receive(:get_eligible_letter_types).and_return(fmp_response)
            allow_any_instance_of(Mobile::V0::LettersController)
              .to receive(:lighthouse_service).and_return(service_double)
            allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter_mobile,
                                                      instance_of(User)).and_return(true)

            get '/mobile/v0/letters', headers: sis_headers
            expect(response).to have_http_status(:ok)
            letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
            fmp_letter = letters.find { |l| l['letterType'] == 'foreign_medical_program' }
            expect(fmp_letter['name']).to eq('Foreign Medical Program Enrollment Letter')
          end

          it 'returns letters sorted alphabetically by name' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              get '/mobile/v0/letters', headers: sis_headers
              expect(response).to have_http_status(:ok)
              letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
              letter_names = letters.map { |l| l['name'] }
              expect(letter_names).to eq(letter_names.sort)
            end
          end

          it 'filters out medicare_partd and minimum_essential_coverage letters' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              get '/mobile/v0/letters', headers: sis_headers
              letter_types = JSON.parse(response.body).dig('data', 'attributes', 'letters').map { |l| l['letterType'] }
              expect(letter_types).not_to include('medicare_partd', 'minimum_essential_coverage')
            end
          end

          it 'applies old behavior regardless of App-Version when flag is off' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
              expect_legacy_letter_content(response)
            end
          end
        end

        context 'when :cst_letters_content_updates is enabled' do
          before do
            allow(Flipper).to receive(:enabled?).and_call_original
            allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(true)
          end

          context 'with App-Version below 2.78.0' do
            shared_examples 'old behavior' do |version|
              it 'sorts alphabetically, filters health letters, and uses legacy names' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => version })
                  expect_legacy_letter_content(response)
                end
              end
            end

            context 'when cst_letters_description_content_format is disabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)
              end

              include_examples 'old behavior', '2.77.0'
            end

            context 'when cst_letters_description_content_format is enabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
              end

              include_examples 'old behavior', '2.77.0'
            end
          end

          context 'with a missing App-Version header' do
            it 'falls back to old behavior: sorts alphabetically, filters health letters, uses legacy names' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                get '/mobile/v0/letters', headers: sis_headers
                expect_legacy_letter_content(response)
              end
            end
          end

          context 'with a malformed App-Version header' do
            it 'falls back to old behavior: sorts alphabetically, filters health letters, uses legacy names' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => 'not-a-version' })
                expect_legacy_letter_content(response)
              end
            end
          end

          context 'with App-Version at or above 2.78.0' do
            context 'when cst_letters_description_content_format is disabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)
              end

              it 'includes descriptions in legacy format and uses Content module names' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })

                  expect(response).to have_http_status(:ok)
                  letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                  proof_of_service = letters.find { |letter| letter['letterType'] == 'proof_of_service' }
                  benefit_summary = letters.find { |letter| letter['letterType'] == 'benefit_summary' }
                  benefit_verification = letters.find { |letter| letter['letterType'] == 'benefit_verification' }

                  expect(proof_of_service['description']).to be_present
                  expect(proof_of_service['description']['paragraphs']).to be_an(Array)
                  expect(
                    proof_of_service['description']['paragraphs'].first
                  ).to include('This card confirms that you served')
                  expect(proof_of_service['description']['lists']).to be_an(Array)
                  expect(
                    proof_of_service['description']['lists'].first['items']
                  ).to include('Requesting Veteran discounts')

                  expect(benefit_summary['name']).to eq('Benefits and service summary')
                  expect(benefit_verification['name']).to eq('Proof of VA income')

                  assert_schema_conform(200)
                end
              end

              it 'returns letters in service order, not alphabetically sorted' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                  expect(response).to have_http_status(:ok)
                  letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                  letter_names = letters.map { |l| l['name'] }
                  expect(letter_names).not_to eq(letter_names.sort)
                  expect(letters.map { |l| l['letterType'] }).to eq(
                    %w[benefit_summary benefit_verification proof_of_service service_verification civil_service
                       minimum_essential_coverage medicare_partd commissary]
                  )
                end
              end

              it 'includes medicare_partd and minimum_essential_coverage letters' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                  letter_types = JSON.parse(response.body).dig('data', 'attributes', 'letters').map do |l|
                    l['letterType']
                  end
                  expect(letter_types).to include('medicare_partd', 'minimum_essential_coverage')
                end
              end
            end

            context 'when cst_letters_description_content_format is enabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
              end

              it 'includes descriptions in content format and uses Content module names' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })

                  expect(response).to have_http_status(:ok)
                  letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                  proof_of_service = letters.find { |letter| letter['letterType'] == 'proof_of_service' }
                  benefit_summary = letters.find { |letter| letter['letterType'] == 'benefit_summary' }
                  benefit_verification = letters.find { |letter| letter['letterType'] == 'benefit_verification' }

                  expect(proof_of_service['description']).to be_present
                  expect(proof_of_service['description']['content']).to be_an(Array)
                  expect(
                    proof_of_service['description']['content'].first['text']
                  ).to include('This card confirms that you served')
                  expect(
                    proof_of_service['description']['content'].find { |n| n['type'] == 'list' }['items']
                  ).to include('Requesting Veteran discounts')

                  expect(benefit_summary['name']).to eq('Benefits and service summary')
                  expect(benefit_verification['name']).to eq('Proof of VA income')

                  assert_schema_conform(200)
                end
              end

              it 'consolidates medicare_partd into minimum_essential_coverage' do
                service_double = instance_double(Lighthouse::LettersGenerator::Service)
                allow(service_double).to receive(:get_eligible_letter_types).and_return(
                  {
                    letters: [
                      { letterType: 'benefit_summary', name: 'Benefits and service summary', description: nil },
                      { letterType: 'minimum_essential_coverage',
                        name: 'Creditable coverage for health care and prescription drugs', description: {} }
                    ],
                    letter_destination: {}
                  }
                )
                allow_any_instance_of(Mobile::V0::LettersController)
                  .to receive(:lighthouse_service).and_return(service_double)

                get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                letter_types = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                                   .map { |l| l['letterType'] }
                expect(letter_types).to include('minimum_essential_coverage')
                expect(letter_types).not_to include('medicare_partd')
              end
            end
          end
        end
      end

      context 'when :mobile_coe_letter_use_lgy_service is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:mobile_coe_letter_use_lgy_service,
                                                    instance_of(User)).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
        end

        context 'with an app version that supports COE letters' do
          context 'with a user that has an available COE letter' do
            it 'includes the COE letter if available' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                    expect(response).to have_http_status(:ok)
                    expect(JSON.parse(response.body)['data']['attributes']['letters']).to include(
                      { 'name' => 'Certificate of Eligibility for Home Loan Letter',
                        'letterType' => 'certificate_of_eligibility_home_loan',
                        'referenceNumber' => '16934344',
                        'coeStatus' => 'AVAILABLE' }
                    )
                    assert_schema_conform(200)
                  end
                end
              end
            end

            it 'increments the COE status counters' do
              allow(StatsD).to receive(:increment)

              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                    expect(response).to have_http_status(:ok)
                    expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.total')
                    expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.available')
                  end
                end
              end
            end

            context 'when :cst_letters_content_updates is disabled' do
              it 'returns the letters alphabetically sorted by name with COE included' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                    VCR.use_cassette('mobile/lgy/application_200_status_submitted',
                                     match_requests_on: %i[method uri]) do
                      get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                      expect(response).to have_http_status(:ok)
                      letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                      expect(letters.map { |l| l['letterType'] }).to eq(
                        %w[benefit_summary benefit_verification certificate_of_eligibility_home_loan
                           civil_service commissary proof_of_service service_verification]
                      )
                    end
                  end
                end
              end
            end
          end

          context 'with a user that has an eligible COE letter' do
            it 'includes the COE letter if eligible' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_not_found', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                    expect(response).to have_http_status(:ok)
                    expect(JSON.parse(response.body)['data']['attributes']['letters']).to include(
                      { 'name' => 'Certificate of Eligibility for Home Loan Letter',
                        'letterType' => 'certificate_of_eligibility_home_loan',
                        'referenceNumber' => '16934344',
                        'coeStatus' => 'ELIGIBLE' }
                    )
                    assert_schema_conform(200)
                  end
                end
              end
            end

            it 'increments the COE status counters' do
              allow(StatsD).to receive(:increment)

              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_not_found', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                    expect(response).to have_http_status(:ok)
                    expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.total')
                    expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.eligible')
                  end
                end
              end
            end

            it 'uses legacy name and excludes description when cst_letters_content_updates flag is off' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_not_found', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                    expect(response).to have_http_status(:ok)
                    letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                    coe_letter = letters.find do |letter|
                      letter['letterType'] == 'certificate_of_eligibility_home_loan'
                    end
                    expect(coe_letter['name']).to eq('Certificate of Eligibility for Home Loan Letter')
                    expect(coe_letter).not_to have_key('description')
                  end
                end
              end
            end

            it 'uses legacy name and excludes description when flag is off regardless of App-Version' do
              VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/application_not_found', match_requests_on: %i[method uri]) do
                    get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                    expect(response).to have_http_status(:ok)
                    letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                    coe_letter = letters.find do |letter|
                      letter['letterType'] == 'certificate_of_eligibility_home_loan'
                    end
                    expect(coe_letter['name']).to eq('Certificate of Eligibility for Home Loan Letter')
                    expect(coe_letter).not_to have_key('description')
                  end
                end
              end
            end
          end
        end

        context 'with an app version that does not support COE letters' do
          it 'does not include the COE letter' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.58.0' })
                  expect(response).to have_http_status(:ok)
                  expect(JSON.parse(response.body)).to eq(letters_body)
                  assert_schema_conform(200)
                end
              end
            end
          end
        end

        context 'with a missing app version' do
          it 'does not include the COE letter' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers
                  expect(response).to have_http_status(:ok)
                  expect(JSON.parse(response.body)).to eq(letters_body)
                  assert_schema_conform(200)
                end
              end
            end
          end
        end

        context 'with a malformed app version' do
          it 'does not include the COE letter' do
            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                  get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => 'foobar' })
                  expect(response).to have_http_status(:ok)
                  expect(JSON.parse(response.body)).to eq(letters_body)
                  assert_schema_conform(200)
                end
              end
            end
          end
        end

        context 'with an unexpected error from LGY' do
          it 'returns the letters without an error and increments the COE status counter' do
            allow(StatsD).to receive(:increment)

            VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/lgy/determination_not_found', match_requests_on: %i[method uri]) do
                get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                expect(response).to have_http_status(:ok)
                expect(JSON.parse(response.body)).to eq(letters_body)
                assert_schema_conform(200)
                expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.total')
                expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.failure')
              end
            end
          end
        end

        it 'does not include the COE letter if not available or eligible' do
          VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
            VCR.use_cassette('mobile/lgy/determination_pending', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/lgy/application_200_status_submitted', match_requests_on: %i[method uri]) do
                get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.59.0' })
                expect(response).to have_http_status(:ok)
                expect(JSON.parse(response.body)).to eq(letters_body)
                assert_schema_conform(200)
              end
            end
          end
        end

        context 'when :cst_letters_content_updates is enabled' do
          before do
            allow(Flipper).to receive(:enabled?).and_call_original
            allow(Flipper).to receive(:enabled?).with(:mobile_coe_letter_use_lgy_service,
                                                      instance_of(User)).and_return(true)
            allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(true)
          end

          context 'with App-Version below 2.78.0' do
            shared_examples 'legacy COE behavior' do |version|
              it 'uses legacy COE name and excludes description' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                    VCR.use_cassette('mobile/lgy/application_200_status_submitted',
                                     match_requests_on: %i[method uri]) do
                      get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => version })
                      expect(response).to have_http_status(:ok)

                      letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                      coe_letter = letters.find do |letter|
                        letter['letterType'] == 'certificate_of_eligibility_home_loan'
                      end

                      expect(coe_letter).to be_present
                      expect(coe_letter['name']).to eq('Certificate of Eligibility for Home Loan Letter')
                      expect(coe_letter).not_to have_key('description')
                    end
                  end
                end
              end
            end

            context 'when cst_letters_description_content_format is disabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)
              end

              include_examples 'legacy COE behavior', '2.77.0'
            end

            context 'when cst_letters_description_content_format is enabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
              end

              include_examples 'legacy COE behavior', '2.77.0'
            end
          end

          context 'with App-Version at or above 2.78.0' do
            context 'when cst_letters_description_content_format is disabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)
              end

              it 'uses Content module name and includes COE description in legacy format' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                    VCR.use_cassette('mobile/lgy/application_200_status_submitted',
                                     match_requests_on: %i[method uri]) do
                      get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                      expect(response).to have_http_status(:ok)

                      letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                      coe_letter = letters.find do |letter|
                        letter['letterType'] == 'certificate_of_eligibility_home_loan'
                      end

                      expect(coe_letter).to be_present
                      expect(coe_letter['name']).to eq('VA home loan Certificate of Eligibility (COE)')
                      expect(coe_letter['description']).to be_present
                      expect(coe_letter['description']['paragraphs']).to be_an(Array)
                      expect(coe_letter['referenceNumber']).to eq('16934344')
                      expect(coe_letter['coeStatus']).to eq('AVAILABLE')
                      expect(letters.map { |l| l['letterType'] }).to eq(
                        %w[benefit_summary benefit_verification certificate_of_eligibility_home_loan
                           proof_of_service service_verification civil_service minimum_essential_coverage medicare_partd
                           commissary]
                      )
                      assert_schema_conform(200)
                    end
                  end
                end
              end
            end

            context 'when cst_letters_description_content_format is enabled' do
              before do
                allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
              end

              it 'uses Content module name and includes COE description in content format' do
                VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
                  VCR.use_cassette('mobile/lgy/determination_eligible', match_requests_on: %i[method uri]) do
                    VCR.use_cassette('mobile/lgy/application_200_status_submitted',
                                     match_requests_on: %i[method uri]) do
                      get '/mobile/v0/letters', headers: sis_headers({ 'App-Version' => '2.78.0' })
                      expect(response).to have_http_status(:ok)

                      letters = JSON.parse(response.body).dig('data', 'attributes', 'letters')
                      coe_letter = letters.find do |letter|
                        letter['letterType'] == 'certificate_of_eligibility_home_loan'
                      end

                      expect(coe_letter).to be_present
                      expect(coe_letter['name']).to eq('VA home loan Certificate of Eligibility (COE)')
                      expect(coe_letter['description']).to be_present
                      expect(coe_letter['description']['content']).to be_an(Array)
                      expect(coe_letter['referenceNumber']).to eq('16934344')
                      expect(coe_letter['coeStatus']).to eq('AVAILABLE')
                      assert_schema_conform(200)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  describe 'GET /mobile/v0/letters/beneficiary' do
    context 'when user does not have access' do
      let!(:user) { sis_user(participant_id: nil) }

      it 'returns forbidden' do
        get '/mobile/v0/letters/beneficiary', headers: sis_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with a valid lighthouse response' do
      it 'matches the letters beneficiary schema' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_200', match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters/beneficiary', headers: sis_headers
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq(beneficiary_body)
          assert_schema_conform(200)
        end
      end
    end
  end

  describe 'POST /mobile/v0/letters/:type/download' do
    context 'when user does not have access' do
      let!(:user) { sis_user(participant_id: nil) }

      it 'returns forbidden' do
        post '/mobile/v0/letters/benefit_summary/download', headers: sis_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'formats' do
      context 'when format is unspecified' do
        it 'downloads a PDF' do
          VCR.use_cassette('mobile/lighthouse_letters/download') do
            post '/mobile/v0/letters/benefit_summary/download', headers: sis_headers
            expect(response).to have_http_status(:ok)
            expect(response.media_type).to eq('application/pdf')
          end
        end
      end

      context 'when format is pdf' do
        it 'downloads a PDF' do
          VCR.use_cassette('mobile/lighthouse_letters/download') do
            post '/mobile/v0/letters/benefit_summary/download', headers: sis_headers, params: { format: 'pdf' },
                                                                as: :json
            expect(response).to have_http_status(:ok)
            expect(response.media_type).to eq('application/pdf')
          end
        end
      end

      context 'when format is json' do
        it 'returns json that matches the letter schema' do
          VCR.use_cassette('mobile/lighthouse_letters/download_as_json', match_requests_on: %i[method uri]) do
            post '/mobile/v0/letters/proof_of_service/download', headers: sis_headers, params: { format: 'json' },
                                                                 as: :json

            expect(response).to have_http_status(:ok)
            expect(response.media_type).to eq('application/json')
            expect(JSON.parse(response.body)).to eq(letter_json)
            assert_schema_conform(200)
          end
        end
      end

      context 'when format is something else' do
        it 'returns unprocessable entity' do
          VCR.use_cassette('mobile/lighthouse_letters/download') do
            post '/mobile/v0/letters/benefit_summary/download', headers: sis_headers, params: { format: 'floormat' },
                                                                as: :json
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end
    end

    context 'with options' do
      let(:options) do
        {
          'militaryService' => false,
          'serviceConnectedDisabilities' => false,
          'serviceConnectedEvaluation' => false,
          'nonServiceConnectedPension' => false,
          'monthlyAward' => false,
          'unemployable' => false,
          'specialMonthlyCompensation' => false,
          'adaptedHousing' => false,
          'chapter35Eligibility' => false,
          'deathResultOfDisability' => false,
          'survivorsAward' => false
        }
      end

      it 'downloads a PDF' do
        VCR.use_cassette('mobile/lighthouse_letters/download_with_options') do
          post '/mobile/v0/letters/benefit_summary/download', params: options, headers: sis_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq('application/pdf')
        end
      end

      it 'downloads json' do
        VCR.use_cassette('mobile/lighthouse_letters/download_as_json_with_options',
                         match_requests_on: %i[method uri]) do
          post '/mobile/v0/letters/proof_of_service/download', headers: sis_headers,
                                                               params: options.merge({ format: 'json' }),
                                                               as: :json

          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq('application/json')
          expect(JSON.parse(response.body)).to eq(letter_json)
          assert_schema_conform(200)
        end
      end
    end

    context 'when an error occurs' do
      it 'raises lighthouse service error' do
        VCR.use_cassette('mobile/lighthouse_letters/download_error') do
          post '/mobile/v0/letters/benefit_summary/download', headers: sis_headers

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'with an invalid letter type' do
      it 'returns 400 bad request' do
        post '/mobile/v0/letters/not_real/download', headers: sis_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['errors'][0]).to include(
          'detail' => 'Letter type of not_real is not one of the expected options',
          'source' => 'Mobile::V0::LettersController',
          'status' => '400'
        )
      end
    end

    context 'when :mobile_coe_letter_use_lgy_service is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:mobile_coe_letter_use_lgy_service,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      end

      it 'returns 400 bad request' do
        post '/mobile/v0/letters/certificate_of_eligibility_home_loan/download', headers: sis_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['errors'][0]).to include(
          'detail' => 'Letter type of certificate_of_eligibility_home_loan is not one of the expected options',
          'source' => 'Mobile::V0::LettersController',
          'status' => '400'
        )
      end
    end

    context 'when :mobile_coe_letter_use_lgy_service is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:mobile_coe_letter_use_lgy_service,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      end

      it 'downloads a PDF' do
        VCR.use_cassette 'mobile/lgy/documents_coe_file' do
          post '/mobile/v0/letters/certificate_of_eligibility_home_loan/download',
               headers: sis_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq('application/pdf')
        end
      end

      it 'increments the COE status counters' do
        allow(StatsD).to receive(:increment)

        VCR.use_cassette 'mobile/lgy/documents_coe_file' do
          post '/mobile/v0/letters/certificate_of_eligibility_home_loan/download',
               headers: sis_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.download_total')
          expect(StatsD).to have_received(:increment).with('mobile.letters.coe_status.download_success')
        end
      end
    end
  end

  describe 'Error Handling' do
    context 'when user is not authorized to use lighthouse' do
      let!(:user) { sis_user(icn: '24811694708759028', participant_id: nil) }

      it 'returns 403 forbidden' do
        get '/mobile/v0/letters', headers: sis_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when upstream is unavailable' do
      it 'returns 503 service unavailable' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_503', match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters', headers: sis_headers
          expect(response).to have_http_status(:service_unavailable)
          expect(response.parsed_body).to eq(
            { 'errors' =>
              [{
                'title' => 'Service unavailable',
                'detail' => 'Backend Service Outage',
                'code' => '503',
                'status' => '503'
              }] }
          )
        end
      end
    end

    context 'with upstream service error' do
      it 'returns a internal server error response' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_500_error_bgs', match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters/beneficiary', headers: sis_headers
          expect(response).to have_http_status(:internal_server_error)
          error = response.parsed_body['errors']
          expect(error[0]).to include(
            'title' => 'Required Backend Connection Error',
            'detail' => 'Backend Service Error BGS',
            'status' => '500'
          )
        end
      end
    end

    context 'when user is not found' do
      it 'returns a not found response' do
        VCR.use_cassette('mobile/lighthouse_letters/letters_404', match_requests_on: %i[method uri]) do
          get '/mobile/v0/letters', headers: sis_headers
        end
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['errors'][0]).to include(
          'status' => '404',
          'title' => 'Person for ICN not found'
        )
      end
    end
  end
end
