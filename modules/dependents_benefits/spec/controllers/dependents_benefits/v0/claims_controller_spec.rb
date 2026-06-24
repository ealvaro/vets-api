# frozen_string_literal: true

require 'rails_helper'

require 'claims_evidence_api/uploader'
require 'digital_forms_api/service/submissions'

RSpec.describe DependentsBenefits::V0::ClaimsController do
  routes { DependentsBenefits::Engine.routes }

  let(:user) { create(:evss_user) }
  let(:test_form) { build(:dependents_claim_combined_form) }
  let(:claim) { create(:dependents_claim, form: test_form.to_json) }
  let(:bgs_service) { double('BGS::Services') }
  let(:bgs_people) { double('BGS::People') }
  let(:monitor) { DependentsBenefits::Monitor.new }

  let(:user_json) do
    { 'veteran_information' => {
      'full_name' => {
        'first' => user.first_name,
        'last' => user.last_name
      },
      'common_name' => user.common_name,
      'va_profile_email' => user.va_profile_email,
      'email' => user.email,
      'participant_id' => user.participant_id,
      'ssn' => user.ssn,
      'va_file_number' => '987654321',
      'birth_date' => user.birth_date,
      'uuid' => user.uuid,
      'icn' => user.icn
    } }
  end
  let(:user_data) { double('DependentsBenefits::UserData', get_user_json: user_json.to_json) }

  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    sign_in_as(user)
    allow(Flipper).to receive(:enabled?).with(:dependents_module_enabled, instance_of(User)).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:va_dependents_v3, instance_of(User)).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:enable_date_last_verified_for_dependents).and_return(false)
    allow_any_instance_of(SavedClaim).to receive(:pdf_overflow_tracking)
    allow(DependentsBenefits::Monitor).to receive(:new).and_return(monitor)
    allow(DependentsBenefits::UserData).to receive(:new).and_return(user_data)
  end

  describe '#show' do
    context 'with a valid bgs response' do
      it 'returns a list of dependents' do
        VCR.use_cassette('bgs/claimant_web_service/dependents') do
          get(:show, params: { id: user.participant_id }, as: :json)
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)['data']['type']).to eq('dependents')
        end
      end
    end

    context 'with an erroneous bgs response' do
      it 'returns no content' do
        allow_any_instance_of(BGS::DependentService).to receive(:get_dependents).and_raise(BGS::ShareError)
        get(:show, params: { id: user.participant_id }, as: :json)
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with flipper disabled' do
      before do
        expect(Flipper).to receive(:enabled?).with(:dependents_module_enabled, instance_of(User)).and_return(false)
      end

      it 'returns forbidden error' do
        get(:show, params: { id: user.participant_id }, as: :json)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with the last verified date feature flag on' do
      let(:persons_service) { double('BID::Persons::Service') }
      let(:persons_response) do
        OpenStruct.new(
          success?: true,
          status: 200,
          body: {
            'find_relationships_response' => [{
              'ptcpnt_id' => 600_140_899,
              'ptcpnt_type_nm' => 'Person',
              'last_nm' => 'Person',
              'first_nm' => 'Test',
              'middle_nm' => 'B',
              'ssn_nbr' => '123456789',
              'file_nbr' => '123456789',
              'last_verfd_dt' => '2026-06-24T15:15:02.463Z'
            }]
          }
        )
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:enable_date_last_verified_for_dependents).and_return(true)
        allow(BID::Persons::Service).to receive(:new).and_return(persons_service)
        allow(persons_service).to receive(:get_relationships).with(user.participant_id).and_return(persons_response)
      end

      it 'returns a response with last date verified populated' do
        VCR.use_cassette('bgs/claimant_web_service/dependents') do
          expect(monitor).to receive(:track_info_event).with('Fetching last verified dates',
                                                             action: 'fetch_dlv.start')
          expect(monitor).to receive(:track_info_event).with('Successfully fetched last verified dates',
                                                             action: 'fetch_dlv.success',
                                                             non_blank_dlvs: 1)

          get(:show, params: { id: user.participant_id }, as: :json)
          expect(response).to have_http_status(:ok)
          parsed_body = JSON.parse(response.body)
          expect(parsed_body['data']['type']).to eq('dependents')
          dependent_entry = parsed_body['data']['attributes']['persons'].find { |e| e['ptcpnt_id'] == '600140899' }
          expect(dependent_entry['date_last_verified']).to eq('2026-06-24T15:15:02.463Z')
        end
      end
    end
  end

  describe 'POST create' do
    context 'with valid params and flipper enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:dependents_digital_forms_api_submission_enabled,
                                                  instance_of(User)).and_return(false)
        allow_any_instance_of(DependentsBenefits::PrimaryDependencyClaim).to receive(:validate_schema).and_return([])
        allow_any_instance_of(DependentsBenefits::PrimaryDependencyClaim).to receive(:validate_form).and_return([])
        allow_any_instance_of(DependentsBenefits::AddRemoveDependent).to receive(:validate_schema).and_return([])
        allow_any_instance_of(DependentsBenefits::AddRemoveDependent).to receive(:validate_form).and_return([])
        allow_any_instance_of(DependentsBenefits::SchoolAttendanceApproval).to receive(:validate_schema).and_return([])
        allow_any_instance_of(DependentsBenefits::SchoolAttendanceApproval).to receive(:validate_form).and_return([])

        allow(BGS::Services).to receive(:new).and_return(bgs_service)
        allow(bgs_service).to receive(:people).and_return(bgs_people)
        allow(bgs_people).to receive(:find_person_by_ptcpnt_id).and_return({ file_nbr: '987654321' })
      end

      it 'validates successfully' do
        post(:create, params: test_form, as: :json)
        expect(response).to have_http_status(:ok)
      end

      it 'sets the user account on the claim' do
        post(:create, params: test_form, as: :json)
        claim = DependentsBenefits::PrimaryDependencyClaim.last
        expect(claim.user_account).to eq(user.user_account)
      end

      it 'creates saved claims' do
        expect do
          post(:create, params: test_form, as: :json)
        end.to change(
          DependentsBenefits::PrimaryDependencyClaim, :count
        ).by(1)
          .and change(
            DependentsBenefits::AddRemoveDependent, :count
          ).by(1)
          .and change(
            DependentsBenefits::SchoolAttendanceApproval, :count
          ).by(1).and change(
            SavedClaimGroup, :count
          ).by(3)
      end

      it 'creates SavedClaimGroup with current user data' do
        post(:create, params: test_form, as: :json)

        parent_group = SavedClaimGroup.last.parent_claim_group_for_child
        user_hash = JSON.parse(parent_group.user_data)
        expect(user_hash).to eq(user_json)
      end

      it 'calls ClaimProcessor with correct parameters' do
        expect(DependentsBenefits::ClaimProcessor).to receive(:enqueue_submissions)
          .with(a_kind_of(Integer))

        post(:create, params: test_form, as: :json)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid params' do
      let(:invalid_params) { { dependents_application: {} } }

      it 'returns validation errors' do
        expect(monitor).to receive(:track_create_validation_error)

        post(:create, params: invalid_params, as: :json)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not create a saved claim' do
        expect do
          post(:create, params: invalid_params, as: :json)
        end.not_to change(DependentsBenefits::PrimaryDependencyClaim, :count)
      end

      it 'sets metadata error message on the in-progress form' do
        in_progress_form = create(:in_progress_form, form_id: claim.form_id, user_uuid: user.uuid, metadata: {})
        allow(InProgressForm).to receive(:form_for_user).and_return(in_progress_form)

        post(:create, params: invalid_params, as: :json)

        expect(response).to have_http_status(:unprocessable_content)
        expect(in_progress_form.reload.metadata.dig('submission', 'error_message')).to be_present
      end
    end

    context 'with no submittable form' do
      it 'returns backend service exception' do
        allow(DependentsBenefits::PrimaryDependencyClaim).to receive(:new).and_return(claim)
        allow(claim).to receive_messages(validate_schema: [], validate_form: [])

        expect(claim).to receive(:submittable_686?).and_return(false)
        expect(claim).to receive(:submittable_674?).and_return(false)

        post(:create, params: test_form, as: :json)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with flipper disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:dependents_module_enabled, instance_of(User)).and_return(false)
      end

      it 'returns forbidden error' do
        post(:create, params: test_form, as: :json)
        expect(response).to have_http_status(:forbidden)
      end

      it 'does not create a saved claim' do
        expect do
          post(:create, params: test_form, as: :json)
        end.not_to change(DependentsBenefits::PrimaryDependencyClaim, :count)
      end
    end

    context 'with Forms API enabled' do
      let(:claim_information) do
        {
          proc_state: 'MANUAL_VAGOV',
          note_text: 'TEST',
          claim_name: '130 - Automated Dependency 686c',
          claim_label: '130DPNEBNADJ',
          participant_id: 'fake-participant-id'
        }
      end
      let(:dfa) { double(DigitalFormsApi::Service::Submissions) }
      let(:uploader) { double(ClaimsEvidenceApi::Uploader) }
      let(:response) { double('response', success?: true, body: { 'submission' => { foobar: 'TEST' } }) }

      before do
        allow(Flipper).to receive(:enabled?).with(:dependents_digital_forms_api_submission_enabled,
                                                  instance_of(User)).and_return(true)
        allow(DependentsBenefits::PrimaryDependencyClaim).to receive(:new).and_return(claim)
        allow(claim).to receive_messages(validate_schema: [], validate_form: [], claim_form_type: '21-686c')

        allow(DigitalFormsApi::Service::Submissions).to receive(:new).and_return(dfa)
        allow(ClaimsEvidenceApi::Uploader).to receive(:new).and_return(uploader)

        allow(claim).to receive(:claim_form_type).and_return('21-686c')
      end

      it 'submits to forms api and uploads evidence' do
        expect(claim).to receive(:get_claim_information).and_return(claim_information)
        expect(dfa).to receive(:submit).and_return(response)
        expect(monitor).to receive(:track_request).with(:info, 'success', 'dependents_controller.forms_api_submission',
                                                        hash_including(saved_claim_id: claim.id))
        expect(uploader).to receive(:upload_evidence)
        expect(monitor).to receive(:track_create_success)

        expect_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_submitted_notification)
        expect_any_instance_of(DependentsBenefits::V0::ClaimsController).to receive(:clear_saved_form)

        post(:create, params: test_form, as: :json)
      end

      it 'tracks an error' do
        expect(claim).to receive(:get_claim_information).and_raise StandardError, 'TEST'
        expect(dfa).not_to receive(:submit)
        expect(monitor).to receive(:track_request).with(:error, 'TEST', 'dependents_controller.forms_api_submission',
                                                        hash_including(error: 'TEST'))

        post(:create, params: test_form, as: :json)
      end
    end
  end

  describe '#log_validation_error_to_metadata' do
    let(:in_progress_form) { build(:in_progress_form) }

    it 'returns nil for blank in_progress_form' do
      ['', [], {}, nil].each do |blank|
        expect(in_progress_form).not_to receive(:update)
        expect(subject.send(:log_validation_error_to_metadata, blank, claim)).to be_nil
      end
    end

    it 'updates metadata for non-blank in_progress_form' do
      expect(in_progress_form).to receive(:metadata).and_return(in_progress_form.metadata)
      expect(in_progress_form).to receive(:update)

      subject.send(:log_validation_error_to_metadata, in_progress_form, claim)
    end
  end
end
