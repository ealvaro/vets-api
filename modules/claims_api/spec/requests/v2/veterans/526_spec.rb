# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../rails_helper'
require 'claims_api/v2/disability_compensation_fes_mapper'
require_relative '../../../support/form_526_fixture_helper'

RSpec.describe 'ClaimsApi::V2::Veterans::526', type: :request do
  let(:scopes) { %w[claim.write claim.read] }
  let(:target_veteran) do
    OpenStruct.new(
      icn: '1012832025V743496',
      first_name: 'Wesley',
      last_name: 'Ford',
      middle_name: 'John',
      birth_date: '19630211',
      loa: { current: 3, highest: 3 },
      edipi: nil,
      ssn: '796043735',
      participant_id: '600061742',
      mpi: OpenStruct.new(
        icn: '1012832025V743496',
        profile: OpenStruct.new(ssn: '796043735')
      )
    )
  end

  let(:data) do
    fixture = Form526FixtureHelper.new.future_change_of_address_dates
    fixture.attributes['serviceInformation']['federalActivation']['anticipatedSeparationDate'] =
      anticipated_separation_date
    fixture.attributes['serviceInformation']['servicePeriods'][-1]['activeDutyEndDate'] = active_duty_end_date

    fixture.data.to_json
  end

  before do
    Timecop.freeze(Time.zone.now)
    allow_any_instance_of(ClaimsApi::EVSSService::Base).to receive(:submit).and_return OpenStruct.new(claimId: 1337)
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)
    # Set fixed birthdate (65 years ago) to prevent flaky tests from random birthdates crossing 13-year validation
    profile = build(:mpi_profile, birth_date: (Time.zone.today - 65.years).strftime('%Y%m%d'))
    profile_response = build(:find_profile_response, profile:)
    allow_any_instance_of(MPIData).to receive(:response_from_redis_or_service).and_return(profile_response)
  end

  after do
    Timecop.return
  end

  describe '#526', vcr: 'claims_api/disability_comp' do
    let(:anticipated_separation_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:active_duty_end_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:schema) { Rails.root.join('modules', 'claims_api', 'config', 'schemas', 'v2', '526.json').read }
    let(:veteran_id) { '1013062086V794840' }

    context 'validate endpoint' do
      let(:veteran_id) { '1012832025V743496' }
      let(:validation_path) { "/services/claims/v2/veterans/#{veteran_id}/526/validate" }

      it 'returns a successful response when valid' do
        mock_ccg(scopes) do |auth_header|
          post validation_path, params: data, headers: auth_header
          expect(response).to have_http_status(:ok)
          parsed = JSON.parse(response.body)
          expect(parsed['data']['type']).to eq('claims_api_auto_established_claim_validation')
          expect(parsed['data']['attributes']['status']).to eq('valid')
        end
      end

      describe "'claimantCertification'" do
        context 'when not provided' do
          it 'is optional and returns a successful response' do
            mock_ccg(scopes) do |auth_header|
              json_data = JSON.parse data
              params = json_data
              params['data']['attributes'].delete('claimantCertification')
              post validation_path, params: params.to_json, headers: auth_header
              expect(response).to have_http_status(:ok)
              parsed = JSON.parse(response.body)
              expect(parsed['data']['type']).to eq('claims_api_auto_established_claim_validation')
              expect(parsed['data']['attributes']['status']).to eq('valid')
            end
          end
        end
      end
    end

    describe '#generate_pdf' do
      let(:invalid_scopes) { %w[claim.write claim.read] }
      let(:generate_pdf_scopes) { %w[system/526-pdf.override] }
      let(:generate_pdf_path) { "/services/claims/v2/veterans/#{veteran_id}/526/generatePDF/minimum-validations" }

      context 'valid data' do
        it 'responds with a 200' do
          mock_ccg_for_fine_grained_scope(generate_pdf_scopes) do |auth_header|
            post generate_pdf_path, params: data, headers: auth_header
            expect(response.header['Content-Disposition']).to include('filename')
            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'invalid scopes' do
        it 'returns a 401 unauthorized' do
          mock_ccg_for_fine_grained_scope(invalid_scopes) do |auth_header|
            post generate_pdf_path, params: data, headers: auth_header
            expect(response).to have_http_status(:unauthorized)
          end
        end
      end

      context 'without the first and last name present' do
        it 'does not allow the generatePDF call to occur' do
          mock_ccg_for_fine_grained_scope(generate_pdf_scopes) do |auth_header|
            target_veteran.first_name = ''
            target_veteran.last_name = ''
            allow_any_instance_of(ClaimsApi::V2::ApplicationController)
              .to receive(:target_veteran).and_return(target_veteran)

            post generate_pdf_path, params: data, headers: auth_header
            expect(response).to have_http_status(:unprocessable_content)
            expect(response.parsed_body['errors'][0]['detail']).to eq('Must have either first or last name')
          end
        end
      end

      context 'without the first name present' do
        it 'allows the generatePDF call to occur' do
          mock_ccg_for_fine_grained_scope(generate_pdf_scopes) do |auth_header|
            target_veteran.first_name = ''
            allow_any_instance_of(ClaimsApi::V2::ApplicationController)
              .to receive(:target_veteran).and_return(target_veteran)

            post generate_pdf_path, params: data, headers: auth_header
            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'when the PDF string is not generated' do
        it 'returns a 422 response when empty object is returned' do
          allow_any_instance_of(ClaimsApi::V2::Veterans::DisabilityCompensationController)
            .to receive(:generate_526_pdf)
            .and_return({})

          mock_ccg_for_fine_grained_scope(generate_pdf_scopes) do |auth_header|
            post generate_pdf_path, params: data, headers: auth_header
            expect(response).to have_http_status(:unprocessable_content)
          end
        end

        it 'returns a 422 response if nil gets returned' do
          allow_any_instance_of(ClaimsApi::V2::Veterans::DisabilityCompensationController)
            .to receive(:generate_526_pdf)
            .and_return(nil)

          mock_ccg_for_fine_grained_scope(generate_pdf_scopes) do |auth_header|
            post generate_pdf_path, params: data, headers: auth_header
            expect(response).to have_http_status(:unprocessable_content)
          end
        end
      end
    end
  end

  describe 'POST #submit not using md5 lookup',
           skip: 'Disabling tests for deactivated /veterans/{veteranId}/526 endpoint' do
    let(:anticipated_separation_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:active_duty_end_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:schema) { Rails.root.join('modules', 'claims_api', 'config', 'schemas', 'v2', '526.json').read }
    let(:veteran_id) { '1013062086V794840' }
    let(:submit_path) { "/services/claims/v2/veterans/#{veteran_id}/526" }

    it 'creates a new claim if duplicate submit occurs (does not use md5 lookup)' do
      mock_ccg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/disability_comp') do
          json = JSON.parse(data)
          post submit_path, params: json.to_json, headers: auth_header
          expect(response).to have_http_status(:accepted)
          first_submit_parsed = JSON.parse(response.body)
          @original_id = first_submit_parsed['data']['id']
        end
      end
      mock_ccg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/disability_comp') do
          json = JSON.parse(data)
          post submit_path, params: json.to_json, headers: auth_header
          expect(response).to have_http_status(:accepted)
          duplicate_submit_parsed = JSON.parse(response.body)
          duplicate_id = duplicate_submit_parsed['data']['id']
          expect(@original_id).not_to eq(duplicate_id)
        end
      end
    end
  end

  describe 'POST #synchronous' do
    let(:veteran_id) { '1012832025V743496' }
    let(:synchronous_path) { "/services/claims/v2/veterans/#{veteran_id}/526/synchronous" }
    let(:anticipated_separation_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:active_duty_end_date) { 2.days.from_now.strftime('%Y-%m-%d') }
    let(:schema) { Rails.root.join('modules', 'claims_api', 'config', 'schemas', 'v2', '526.json').read }
    let(:synchronous_scopes) { %w[system/526.override system/claim.write] }
    let(:invalid_scopes) { %w[system/526-pdf.override] }
    let(:meta) do
      { transactionId: '00000000-0000-0000-000000000000' }
    end

    context 'submission to synchronous' do
      context 'with a transaction_id' do
        context 'present' do
          it 'saves the transaction ID on the claim record' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                json = JSON.parse data
                json['meta'] = meta
                data = json.to_json
                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                claim_id = parsed_res['data']['id']
                aec = ClaimsApi::AutoEstablishedClaim.find(claim_id)

                expect(aec.transaction_id).to eq(meta[:transactionId])
                expect(parsed_res['meta']['transactionId']).to eq(meta[:transactionId])
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context 'absent' do
          it 'has a null transaction ID on the claim record' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                claim_id = parsed_res['data']['id']
                aec = ClaimsApi::AutoEstablishedClaim.find(claim_id)

                expect(aec.transaction_id).to be_nil
                expect(parsed_res).not_to have_key('meta')
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end
      end

      describe 'FES claim submission source' do
        it "adds claimSubmissionSource as 'VET' in v2 FES mapper output without mutating persisted form_data" do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              post synchronous_path, params: data, headers: auth_header

              expect(response).to have_http_status(:accepted)

              parsed_res = JSON.parse(response.body)
              claim_id = parsed_res['data']['id']
              auto_claim = ClaimsApi::AutoEstablishedClaim.find(claim_id)
              fes_payload = ClaimsApi::V2::DisabilityCompensationFesMapper.new(auto_claim).map_claim

              expect(auto_claim.form_data['claimSubmissionSource']).to be_nil
              expect(fes_payload.dig(:data, :claimSubmissionSource)).to eq('VET')
            end
          end
        end
      end

      context 'claimDate', vcr: 'claims_api/disability_comp' do
        before do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(false)
        end

        context 'present' do
          it 'accepts the submission with valid string' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              temp = JSON.parse(data)
              temp['data']['attributes']['claimDate'] = (Date.current - 1.day).to_s
              data = temp.to_json

              post synchronous_path, params: data, headers: auth_header

              expect(response).to have_http_status(:accepted)
            end
          end

          context 'rejects the submission' do
            it 'with an invalid string YYYY' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = '2024'
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to include('is not a valid date')
              end
            end

            it 'with an invalid string YYYY-MM' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = '2024-06'
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to include('is not a valid date')
              end
            end

            it 'with an invalid string' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = 'strings-like-this-are-invalid'
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to include('is not a valid date')
              end
            end

            it 'with a non-string integer value' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = 123
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to include('is not a valid date')
              end
            end

            it 'with a non-string boolean value' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = true
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to include('is not a valid date')
              end
            end

            it 'rejects the submission when claimDate is in the future' do
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                temp = JSON.parse(data)
                temp['data']['attributes']['claimDate'] = (Date.current + 1.day).to_s
                data = temp.to_json

                post synchronous_path, params: data, headers: auth_header

                parsed_res = JSON.parse(response.body)
                parsed_errors = parsed_res['errors']
                expect(parsed_errors.count).to eq(1)
                expect(response).to have_http_status(:unprocessable_content)
                expect(parsed_errors[0]['detail']).to eq(
                  'claimDate must not be in the future.'
                )
              end
            end
          end
        end

        context 'absent' do
          it 'accepts the submission when optional claimDate not provided' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              post synchronous_path, params: data, headers: auth_header

              expect(response).to have_http_status(:accepted)
            end
          end
        end
      end

      context 'BDD claim' do
        before do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)
        end

        it 'return a 422 when service periods is not included' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              temp = JSON.parse(data)
              temp['data']['attributes']['claimProcessType'] = 'BDD_PROGRAM'
              temp['data']['attributes']['serviceInformation'].delete('servicePeriods')
              data = temp.to_json

              post synchronous_path, params: data, headers: auth_header

              parsed_res = JSON.parse(response.body)
              parsed_errors = parsed_res['errors']
              expect(parsed_errors.count).to eq(1)
              expect(parsed_errors[0]['detail']).to eq(
                'The property /serviceInformation did not contain the required key servicePeriods'
              )
            end
          end
        end
      end

      context 'Section 6: Service Information' do
        before do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)
        end

        it 'return a 422 when service periods is not included' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              temp = JSON.parse(data)
              temp['data']['attributes']['serviceInformation'].delete('servicePeriods')
              data = temp.to_json

              post synchronous_path, params: data, headers: auth_header

              parsed_res = JSON.parse(response.body)
              parsed_errors = parsed_res['errors']
              expect(parsed_errors.count).to eq(1)
              expect(parsed_errors[0]['detail']).to eq(
                'The property /serviceInformation did not contain the required key servicePeriods'
              )
            end
          end
        end
      end

      it 'returns an empty test object' do
        mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
          VCR.use_cassette('claims_api/disability_comp') do
            post synchronous_path, params: data, headers: auth_header

            parsed_res = JSON.parse(response.body)
            expect(parsed_res['data']['attributes']).to include('claimId')
          end
        end
      end

      it 'returns a 202 response when successful' do
        mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
          VCR.use_cassette('claims_api/disability_comp') do
            post synchronous_path, params: data, headers: auth_header

            expect(response).to have_http_status(:accepted)
          end
        end
      end

      describe "'claimantCertification'" do
        context 'when not provided' do
          it 'is optional and returns a 202 response' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                json_data = JSON.parse data
                params = json_data
                params['data']['attributes'].delete('claimantCertification')
                post synchronous_path, params: params.to_json, headers: auth_header

                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end
      end

      it 'returns a 401 unauthorized with incorrect scopes' do
        mock_ccg_for_fine_grained_scope(invalid_scopes) do |auth_header|
          post synchronous_path, params: data, headers: auth_header

          expect(response).to have_http_status(:unauthorized)
        end
      end

      it 'returns a 202 when the s3 upload is mocked' do
        with_settings(Settings.claims_api.benefits_documents, use_mocks: true) do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              post synchronous_path, params: data, headers: auth_header

              expect(response).to have_http_status(:accepted)
            end
          end
        end
      end
    end

    describe "'treatments' validations" do
      describe 'when FES is enabled' do
        def treatment_data_with_date(date_value)
          temp = JSON.parse(data)
          temp['data']['attributes']['treatments'] = [
            {
              center: {
                name: 'Some Treatment Center',
                city: 'Portland',
                state: 'OR'
              },
              treatedDisabilityNames: [
                'PTSD (post traumatic stress disorder)'
              ],
              beginDate: date_value
            }
          ]
          temp.to_json
        end

        before do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)
        end

        context 'it does not require the treatment beginDate to be after the earliest activeDutyBeginDate' do
          let(:treatment_begin_date) { '1970-01' }

          it 'returns a 202' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: treatment_data_with_date(treatment_begin_date), headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context 'it does not require the begin date to be in yyyy-mm-dd format' do
          let(:treatment_begin_date) { '1985-01' }

          it 'returns a 202' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: treatment_data_with_date(treatment_begin_date), headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context 'it allows the begin date to be nil' do
          let(:treatment_begin_date) { nil }

          it 'returns a 202' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: treatment_data_with_date(treatment_begin_date), headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context 'and the treatment date is in an invalid format' do
          let(:invalid_date) { 'four score and seven years ago' }

          it 'returns a 422' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: treatment_data_with_date(invalid_date), headers: auth_header
                expect(response).to have_http_status(:unprocessable_content)
              end
            end
          end
        end

        context 'and treatment date is YYYY, or YYYY-MM' do
          let(:invalid_dates) { %w[9999 2014-23] }
          let(:valid_dates) { %w[2014 2026-02] }

          it 'accepts invalid dates because they are in the correct format' do
            invalid_dates.each do |date|
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                VCR.use_cassette('claims_api/disability_comp') do
                  post synchronous_path, params: treatment_data_with_date(date), headers: auth_header
                  expect(response).to have_http_status(:accepted)
                end
              end
            end
          end

          it 'accepts valid dates' do
            valid_dates.each do |date|
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                VCR.use_cassette('claims_api/disability_comp') do
                  post synchronous_path, params: treatment_data_with_date(date), headers: auth_header
                  expect(response).to have_http_status(:accepted)
                end
              end
            end
          end
        end

        context 'it does not require a treatment begin date' do
          let(:treatments) do
            [
              {
                center: {
                  name: 'Some Treatment Center',
                  city: 'Portland',
                  state: 'OR'
                },
                treatedDisabilityNames: [
                  'PTSD (post traumatic stress disorder)'
                ]
              }
            ]
          end

          it 'returns a 202' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                temp = JSON.parse(data)
                temp['data']['attributes']['treatments'] = treatments
                test_data = temp.to_json
                post synchronous_path, params: test_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context 'it does not require the center name, city, state, or treatedDisabilityNames' do
          let(:treatments) do
            [
              {
                center: {},
                treatedDisabilityNames: []
              }
            ]
          end

          it 'returns a 202' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                temp = JSON.parse(data)
                temp['data']['attributes']['treatments'] = treatments
                test_data = temp.to_json
                post synchronous_path, params: test_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end
      end
    end

    context 'handling for missing first and last name' do
      context 'without the first and last name present' do
        it 'does not allow the submit to occur' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              target_veteran.first_name = ''
              target_veteran.last_name = ''
              allow_any_instance_of(ClaimsApi::V2::ApplicationController)
                .to receive(:target_veteran).and_return(target_veteran)
              post synchronous_path, params: data, headers: auth_header
              expect(response).to have_http_status(:unprocessable_content)
              expect(response.parsed_body['errors'][0]['detail']).to eq('Missing first and last name')
            end
          end
        end
      end
    end

    context 'flash handling' do
      let(:homeless_flash_data) do
        temp = JSON.parse(data)
        temp['data']['attributes']['homeless'] = {
          'currentlyHomeless' => {
            'homelessSituationOptions' => 'LIVING_IN_A_HOMELESS_SHELTER'
          },
          'pointOfContact' => 'Jane Doe'
        }
        temp.to_json
      end

      it 'saves homeless flash when applicable' do
        mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
          VCR.use_cassette('claims_api/disability_comp') do
            post synchronous_path, params: homeless_flash_data, headers: auth_header

            claim_id = JSON.parse(response.body)['data']['id']
            claim = ClaimsApi::AutoEstablishedClaim.find(claim_id)

            expect(claim.flashes).to include('Homeless')
          end
        end
      end
    end

    context 'removed servicePay validations - confirming no errors when violating old schema rules' do
      before do
        allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)
      end

      describe "'militaryRetiredPay.payment.monthlyAmount' no longer has min/max constraints" do
        let(:service_pay_data) do
          temp = JSON.parse(data)
          temp['data']['attributes']['servicePay'] = {
            'receivingMilitaryRetiredPay' => 'YES',
            'futureMilitaryRetiredPay' => 'NO',
            'militaryRetiredPay' => {
              'branchOfService' => 'Army',
              'monthlyAmount' => monthly_amount
            },
            'retiredStatus' => 'PERMANENT_DISABILITY_RETIRED_LIST',
            'favorMilitaryRetiredPay' => false
          }
          temp.to_json
        end

        context "when 'monthlyAmount' is 0 (was below old minimum of 1)" do
          let(:monthly_amount) { 0 }

          it 'returns a 202 accepted (no longer validated at schema level)' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context "when 'monthlyAmount' is 1000000 (was above old maximum of 999999)" do
          let(:monthly_amount) { 1_000_000 }

          it 'returns a 202 accepted (no longer validated at schema level)' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end
      end

      describe "'separationSeverancePay.preTaxAmountReceived' no longer has min/max constraints" do
        let(:service_pay_data) do
          temp = JSON.parse(data)
          temp['data']['attributes']['servicePay'] = {
            'receivingMilitaryRetiredPay' => 'NO',
            'futureMilitaryRetiredPay' => 'NO',
            'receivedSeparationOrSeverancePay' => 'YES',
            'separationSeverancePay' => {
              'datePaymentReceived' => '2022-03-12',
              'branchOfService' => 'Army',
              'preTaxAmountReceived' => pre_tax_amount
            },
            'favorTrainingPay' => false
          }
          temp.to_json
        end

        context "when 'preTaxAmountReceived' is 0 (was below old minimum of 1)" do
          let(:pre_tax_amount) { 0 }

          it 'returns a 202 accepted (no longer validated at schema level)' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context "when 'preTaxAmountReceived' is 1000000 (was above old maximum of 999999)" do
          let(:pre_tax_amount) { 1_000_000 }

          it 'returns a 202 accepted (no longer validated at schema level)' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data, headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end
      end

      describe "'separationSeverancePay.datePaymentReceived' validations" do
        def service_pay_data_with_date(date_value)
          temp = JSON.parse(data)
          temp['data']['attributes']['servicePay'] = {
            'receivingMilitaryRetiredPay' => 'NO',
            'futureMilitaryRetiredPay' => 'NO',
            'receivedSeparationOrSeverancePay' => 'YES',
            'separationSeverancePay' => {
              'datePaymentReceived' => date_value,
              'branchOfService' => 'Army',
              'preTaxAmountReceived' => 100
            },
            'favorTrainingPay' => false
          }
          temp.to_json
        end

        context "when 'datePaymentReceived' is an arbitrary string" do
          let(:date_received) { 'invalid-date-format' }

          it 'returns a 422 unprocessable content' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data_with_date(date_received), headers: auth_header
                expect(response).to have_http_status(:unprocessable_content)
              end
            end
          end
        end

        context "when 'datePaymentReceived' is null" do
          let(:date_received) { nil }

          it 'returns a 202 accepted (field is nullable)' do
            mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
              VCR.use_cassette('claims_api/disability_comp') do
                post synchronous_path, params: service_pay_data_with_date(date_received), headers: auth_header
                expect(response).to have_http_status(:accepted)
              end
            end
          end
        end

        context "when 'datePaymentReceived' is YYYY, YYYY-MM, or YYYY-MM-DD" do
          let(:invalid_dates) { %w[9999 2014-23 2014-11-55] }
          let(:valid_dates) { %w[2014 2026-02 2026-01-05] }

          it 'accepts invalid dates because they are in the correct format' do
            invalid_dates.each do |date|
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                VCR.use_cassette('claims_api/disability_comp') do
                  post synchronous_path, params: service_pay_data_with_date(date), headers: auth_header
                  expect(response).to have_http_status(:accepted)
                end
              end
            end
          end

          it 'accepts valid dates' do
            valid_dates.each do |date|
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                VCR.use_cassette('claims_api/disability_comp') do
                  post synchronous_path, params: service_pay_data_with_date(date), headers: auth_header
                  expect(response).to have_http_status(:accepted)
                end
              end
            end
          end
        end

        context "when 'datePaymentReceived' has a trailing dash" do
          let(:trailing_dash_dates) { %w[2011- 2011-02- 2011-02-04-] }

          it 'rejects dates with trailing dashes' do
            trailing_dash_dates.each do |date|
              mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
                VCR.use_cassette('claims_api/disability_comp') do
                  post synchronous_path, params: service_pay_data_with_date(date), headers: auth_header
                  expect(response).to have_http_status(:unprocessable_content),
                                      "Expected trailing dash date '#{date}' to be rejected but got #{response.status}"
                end
              end
            end
          end
        end
      end
    end

    context 'alternateNames validations' do
      context 'when alternateNames contains duplicate names' do
        it 'allows duplicate alternate names when FES validation is enabled' do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_enable_FES).and_return(true)

          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              json_data['data']['attributes']['serviceInformation']['alternateNames'] = [
                'John Smith',
                'john smith',
                'Johnny Smith',
                'John Smith'
              ]

              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:accepted)
            end
          end
        end
      end
    end

    describe "'mailingAddress.city'" do
      context 'when city exceeds maxLength' do
        it 'returns an unprocessable entity error' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              json_data['data']['attributes']['veteranIdentification']['mailingAddress']['city'] = 'A' * 21
              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:unprocessable_content)
              errors = JSON.parse(response.body)['errors']
              expect(errors).to be_an Array
              expect(errors[0]['detail']).to include('/veteranIdentification/mailingAddress/city',
                                                     '"maxLength"=>20')
            end
          end
        end
      end
    end

    describe "'changeOfAddress.city'" do
      context 'when city exceeds maxLength' do
        it 'returns an unprocessable entity error' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              json_data['data']['attributes']['changeOfAddress'] = {
                typeOfAddressChange: 'PERMANENT',
                addressLine1: '1234 Couch Street',
                city: 'A' * 21,
                state: 'OR',
                zipFirstFive: '12345',
                country: 'USA'
              }
              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:unprocessable_content)
              errors = JSON.parse(response.body)['errors']
              expect(errors).to be_an Array
              expect(errors[0]['detail']).to include('/changeOfAddress/city', '"maxLength"=>20')
            end
          end
        end
      end
    end

    describe "'disabilities.secondaryDisabilities' validations" do
      context 'when secondary disability name contains invalid characters' do
        it 'returns an error for secondary disability name with @ symbol' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              disabilities = [
                {
                  disabilityActionType: 'NONE',
                  name: 'PTSD (post traumatic stress disorder)',
                  diagnosticCode: 9999,
                  secondaryDisabilities: [
                    {
                      disabilityActionType: 'SECONDARY',
                      name: 'hearing loss @home!',
                      serviceRelevance: 'Caused by a service-connected disability.'
                    }
                  ]
                }
              ]
              json_data['data']['attributes']['disabilities'] = disabilities
              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:unprocessable_content)
              parsed_response = JSON.parse(response.body)
              expect(parsed_response['errors']).to be_present
              expect(parsed_response['errors'][0]['detail']).to include('secondaryDisabilities')
            end
          end
        end
      end

      context 'when secondary disability name contains all FES-valid characters' do
        it 'accepts the secondary disability name' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              # Covers all FES-allowed chars: alphanumeric, space, hyphen, apostrophe, double quote,
              # comma, period, hash, ampersand, semicolon, colon, percent, angle brackets,
              # slash, parens, square brackets, backslash
              disabilities = [
                {
                  disabilityActionType: 'NONE',
                  name: 'PTSD (post traumatic stress disorder)',
                  diagnosticCode: 9999,
                  secondaryDisabilities: [
                    {
                      disabilityActionType: 'SECONDARY',
                      name: "hearing loss \"type\" #1: 50% [right] & left-ear; <acute> (O'Brien's), test/case\\injury",
                      serviceRelevance: 'Caused by a service-connected disability.'
                    }
                  ]
                }
              ]
              json_data['data']['attributes']['disabilities'] = disabilities
              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:accepted)
            end
          end
        end
      end

      context 'when secondary disability name contains double spaces' do
        it 'accepts secondary disability name with consecutive spaces' do
          mock_ccg_for_fine_grained_scope(synchronous_scopes) do |auth_header|
            VCR.use_cassette('claims_api/disability_comp') do
              json_data = JSON.parse(data)
              disabilities = [
                {
                  disabilityActionType: 'NONE',
                  name: 'PTSD (post traumatic stress disorder)',
                  diagnosticCode: 9999,
                  secondaryDisabilities: [
                    {
                      disabilityActionType: 'SECONDARY',
                      name: 'hearing  loss',
                      serviceRelevance: 'Caused by a service-connected disability.'
                    }
                  ]
                }
              ]
              json_data['data']['attributes']['disabilities'] = disabilities
              post synchronous_path, params: json_data.to_json, headers: auth_header
              expect(response).to have_http_status(:accepted)
            end
          end
        end
      end
    end
  end
end
