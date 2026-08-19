# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/sidekiq/claims_api_job'

RSpec.describe DependentsBenefits::Sidekiq::ClaimsApiJob, type: :job do
  let(:user) { create(:evss_user) }
  let(:parent_claim) { create(:dependents_claim) }
  let(:perform) { described_class.new.perform(parent_claim.id) }
  let(:bgs_service_stub) { instance_double(BGS::Service) }
  let(:claims_api_service_stub) { instance_double(BEP::Claims::Service) }

  def create_child_claims(claim)
    user_data = DependentsBenefits::UserData.new(user, claim.parsed_form)

    SavedClaimGroup.new(claim_group_guid: claim.guid, parent_claim_id: claim.id, saved_claim_id: claim.id,
                        user_data: user_data.get_user_json).save!
    form_data = claim.parsed_form
    DependentsBenefits::Generators::Claim686cGenerator.new(form_data, claim.id).generate if claim.submittable_686?

    if claim.submittable_674?
      # Create a 674 claim for student benefits
      form_data.dig('dependents_application', 'student_information')&.each do |student|
        DependentsBenefits::Generators::Claim674Generator.new(form_data, claim.id, student).generate
      end
    end
  end

  before do
    allow(BGS::Service).to receive(:new).and_return(bgs_service_stub)
    allow(BEP::Claims::Service).to receive(:new).and_return(claims_api_service_stub)
    allow(claims_api_service_stub).to receive_messages(create_claim: { 'claim_id' => 1_234_567 },
                                                       create_contentions: { 'contention_ids' => [
                                                         1, 2, 3, 4, 5
                                                       ] })
    allow(bgs_service_stub).to receive_messages(create_participant: {}, find_benefit_claim_type_increment: {},
                                                create_address: {}, get_regional_office_by_zip_code: {},
                                                create_relationship: {}, vnp_create_benefit_claim: {},
                                                vnp_benefit_claim_update: {},
                                                create_child_school: {}, create_note: {}, update_proc: {},
                                                create_child_student: {}, create_proc_form: {},
                                                find_regional_offices: {}, create_person: {}, create_phone: {})
    allow(bgs_service_stub).to receive_messages(create_proc: { vnp_proc_id: '123' }, insert_benefit_claim: {
                                                  benefit_claim_record: {
                                                    benefit_claim_id: '9876',
                                                    claim_type_code: 'EP123',
                                                    participant_claimant_id: '111',
                                                    program_type_code: '222',
                                                    service_type_code: '333',
                                                    status_type_code: '444'
                                                  }
                                                })
  end

  describe '#perform' do
    context 'with a 686-only form' do
      before do
        form_data = parent_claim.parsed_form
        # make sure nothing in this form will trigger a 674
        form_data['view:selectable686_options'] = {
          'add_spouse' => true,
          'add_child' => true,
          'report674' => false,
          'add_disabled_child' => true,
          'report_divorce' => true,
          'report_death' => true,
          'report_stepchild_not_in_household' => true,
          'report_marriage_of_child_under18' => true,
          'report_child18_or_older_is_not_attending_school' => true
        }
        form_data['dependents_application'].delete('student_information')
        parent_claim.update!(form: form_data.to_json)
        parent_claim.instance_variable_set('@parsed_form', nil)
        create_child_claims(parent_claim)
      end

      it 'is setup correctly' do
        expect(parent_claim.submittable_686?).to be(true)
        expect(parent_claim.submittable_674?).to be(false)
      end

      it 'creates a claim' do
        expect(claims_api_service_stub).to receive(:create_claim).with(hash_including(
                                                                         {
                                                                           serviceTypeCode: 'CP',
                                                                           programTypeCode: 'CPL',
                                                                           benefitClaimTypeCode: '130DPNEBNADJ',
                                                                           claimant: {
                                                                             participantId: user.participant_id
                                                                           },
                                                                           veteran: {
                                                                             participantId: user.participant_id,
                                                                             firstName: user.first_name,
                                                                             lastName: user.last_name
                                                                           },
                                                                           tempStationOfJurisdiction: 281,
                                                                           submtrRoleTypeCd: 'VBA',
                                                                           submtrApplcnTypeCd: 'VBMS'
                                                                         }
                                                                       ))
        perform
      end

      it 'creates contentions' do
        expect(claims_api_service_stub).to receive(:create_contentions).with(1_234_567, satisfy do |data|
          texts = data[:createContentions].map { |e| e[:claimantText] }

          data[:createContentions].size == 15 &&
          data[:createContentions].first[:contentionTypeCode] == 'NEW' &&
          data[:createContentions].first[:classificationType] == 8925 &&
          texts.include?('Dependency claim for removing spouse') &&
          texts.include?('Dependency claim for test childone') &&
          texts.include?('Dependency claim for child married') &&
          texts.include?('Dependency claim for removing child')
        end)
        perform
      end

      it 'sends the right data to bgs' do
        expect(bgs_service_stub).to receive(:create_proc_form).with('123', '21-686c')
        expect(bgs_service_stub).not_to receive(:create_proc_form).with('123', '21-674')
        %i[create_participant find_benefit_claim_type_increment
           create_address get_regional_office_by_zip_code
           create_relationship create_person create_phone].each do |method_name|
          expect(bgs_service_stub).to receive(method_name)
        end
        expect(bgs_service_stub).not_to receive(:create_child_school) # no 674s in this instance

        expect(bgs_service_stub).to receive(:vnp_create_benefit_claim).once
        expect(bgs_service_stub).to receive(:vnp_benefit_claim_update).with(hash_including({
                                                                                             bnft_claim_id: 1_234_567
                                                                                           }))
        expect(bgs_service_stub).to receive(:update_proc).with('123', proc_state: 'Ready')

        perform
      end

      it 'creates the correct FormSubmission and FormSubmissionAttempt records' do
        expect do
          perform
        end.to change(FormSubmission, :count).from(0).to(1).and change(FormSubmissionAttempt, :count).from(0).to(1)
        expect(FormSubmission.first.form_type).to eq(parent_claim.form_id)
        expect(FormSubmission.first.saved_claim_id).to eq(parent_claim.id)
        expect(FormSubmissionAttempt.first.aasm_state).to eq('success')
      end

      context 'when submission has already succeeded' do
        before do
          submission = FormSubmission.create!(form_type: parent_claim.form_id, saved_claim: parent_claim)
          FormSubmissionAttempt.create!(form_submission: submission, aasm_state: :success)
        end

        it 'returns immediately' do
          expect(claims_api_service_stub).not_to receive(:create_claim)
          expect(claims_api_service_stub).not_to receive(:create_contentions)
          expect(bgs_service_stub).not_to receive(:create_proc_form)
          perform
        end
      end

      context 'when submission fails' do
        before do
          allow(claims_api_service_stub).to receive(:create_claim).and_raise(StandardError, 'something went wrong')
        end

        it 'sets the submission attempt correctly' do
          expect { perform }.to raise_error(StandardError)
          expect(FormSubmission.first.form_type).to eq(parent_claim.form_id)
          expect(FormSubmission.first.saved_claim_id).to eq(parent_claim.id)
          expect(FormSubmissionAttempt.first.aasm_state).to eq('failure')
          expect(FormSubmissionAttempt.first.error_message).to eq('something went wrong')
        end
      end
    end

    context 'with a 674-only form' do
      before do
        form_data = build(:student_claim).parsed_form
        # make sure nothing in this form will trigger a 686
        form_data['view:selectable686_options'] = {
          'add_spouse' => false,
          'add_child' => false,
          'report674' => true,
          'add_disabled_child' => false,
          'report_divorce' => false,
          'report_death' => false,
          'report_stepchild_not_in_household' => false,
          'report_marriage_of_child_under18' => false,
          'report_child18_or_older_is_not_attending_school' => false
        }
        form_data['dependents_application'].delete('child_stopped_attending_school')
        parent_claim.update!(form: form_data.to_json)
        parent_claim.instance_variable_set('@parsed_form', nil)
        create_child_claims(parent_claim)
      end

      it 'is setup correctly' do
        expect(parent_claim.submittable_686?).to be(false)
        expect(parent_claim.submittable_674?).to be(true)
      end

      it 'creates a claim' do
        expect(claims_api_service_stub).to receive(:create_claim).with(hash_including(
                                                                         {
                                                                           serviceTypeCode: 'CP',
                                                                           programTypeCode: 'CPL',
                                                                           benefitClaimTypeCode: '130SCHATTEBN',
                                                                           claimant: {
                                                                             participantId: user.participant_id
                                                                           },
                                                                           veteran: {
                                                                             participantId: user.participant_id,
                                                                             firstName: user.first_name,
                                                                             lastName: user.last_name
                                                                           },
                                                                           tempStationOfJurisdiction: 281,
                                                                           submtrRoleTypeCd: 'VBA',
                                                                           submtrApplcnTypeCd: 'VBMS'
                                                                         }
                                                                       ))
        perform
      end

      it 'does not create any contentions' do
        expect(claims_api_service_stub).not_to receive(:create_contentions)
        perform
      end

      it 'sends the right data to bgs' do
        expect(bgs_service_stub).not_to receive(:create_proc_form).with('123', '21-686c')
        expect(bgs_service_stub).to receive(:create_proc_form).with('123', '21-674')
        %i[create_participant find_benefit_claim_type_increment
           create_address get_regional_office_by_zip_code
           create_relationship create_child_school create_person create_phone].each do |method_name|
          expect(bgs_service_stub).to receive(method_name)
        end

        expect(bgs_service_stub).to receive(:vnp_create_benefit_claim).once
        expect(bgs_service_stub).to receive(:vnp_benefit_claim_update).with(hash_including({
                                                                                             bnft_claim_id: 1_234_567
                                                                                           }))
        expect(bgs_service_stub).to receive(:update_proc).with('123', proc_state: 'Ready')

        perform
      end
    end

    context 'with a 686+674 form' do
      before do
        parent_claim.parsed_form
        create_child_claims(parent_claim)
      end

      it 'is setup correctly' do
        expect(parent_claim.submittable_686?).to be(true)
        expect(parent_claim.submittable_674?).to be(true)
      end

      it 'creates a claim' do
        expect(claims_api_service_stub).to receive(:create_claim).with(hash_including(
                                                                         {
                                                                           serviceTypeCode: 'CP',
                                                                           programTypeCode: 'CPL',
                                                                           benefitClaimTypeCode: '130DPNEBNADJ',
                                                                           claimant: {
                                                                             participantId: user.participant_id
                                                                           },
                                                                           veteran: {
                                                                             participantId: user.participant_id,
                                                                             firstName: user.first_name,
                                                                             lastName: user.last_name
                                                                           },
                                                                           tempStationOfJurisdiction: 281,
                                                                           submtrRoleTypeCd: 'VBA',
                                                                           submtrApplcnTypeCd: 'VBMS'
                                                                         }
                                                                       ))
        perform
      end

      it 'creates contentions' do
        expect(claims_api_service_stub).to receive(:create_contentions).with(1_234_567, satisfy do |data|
          texts = data[:createContentions].map { |e| e[:claimantText] }

          data[:createContentions].size == 16 &&
          data[:createContentions].first[:contentionTypeCode] == 'NEW' &&
          data[:createContentions].first[:classificationType] == 8925 &&
          texts.include?('Dependency claim for removing spouse') &&
          texts.include?('Dependency claim for test childone') &&
          texts.include?('Dependency claim for child married') &&
          texts.include?('Dependency claim for removing child')
        end)
        perform
      end

      it 'sends the right data to bgs' do
        expect(bgs_service_stub).to receive(:create_proc_form).with('123', '21-686c')
        expect(bgs_service_stub).to receive(:create_proc_form).with('123', '21-674')
        %i[create_participant find_benefit_claim_type_increment
           create_address get_regional_office_by_zip_code create_child_school
           create_relationship create_person create_phone].each do |method_name|
          expect(bgs_service_stub).to receive(method_name)
        end

        expect(bgs_service_stub).to receive(:vnp_create_benefit_claim).once
        expect(bgs_service_stub).to receive(:vnp_benefit_claim_update).with(hash_including({
                                                                                             bnft_claim_id: 1_234_567
                                                                                           }))
        expect(bgs_service_stub).to receive(:update_proc).with('123', proc_state: 'Ready')

        perform
      end
    end
  end

  describe '#generate_user_struct' do
    let(:job) { described_class.new }

    context 'when bgs_truncate_external_key Flipper is disabled' do
      let(:original_external_key) { 'g' * 60 }

      before do
        allow(Flipper).to receive(:enabled?).with(:bgs_truncate_external_key).and_return(false)
        allow(job).to receive(:generate_user_struct).and_call_original
        allow(job).to receive(:parent_claim).and_return(parent_claim)

        allow(parent_claim).to receive(:user_data).and_return(
          {
            'veteran_information' => {
              'full_name' => { 'first' => 'John', 'last' => 'Doe', 'middle' => nil },
              'common_name' => original_external_key
            }
          }
        )
      end

      it 'does not truncate the common_name in the generated user' do
        user = job.send(:generate_user_struct)

        expect(user.common_name).to eq(original_external_key)
      end
    end

    context 'when bgs_truncate_external_key Flipper is enabled' do
      let(:original_external_key) { 'k' * 60 }

      before do
        allow(Flipper).to receive(:enabled?).with(:bgs_truncate_external_key).and_return(true)
        allow(job).to receive(:generate_user_struct).and_call_original
        allow(job).to receive(:parent_claim).and_return(parent_claim)

        allow(parent_claim).to receive(:user_data).and_return(
          {
            'veteran_information' => {
              'full_name' => { 'first' => 'John', 'last' => 'Doe', 'middle' => nil },
              'common_name' => original_external_key
            }
          }
        )
      end

      it 'truncates the common_name in the generated user' do
        user = job.send(:generate_user_struct)

        expect(user.common_name).to eq(original_external_key.first(BGS::Constants::EXTERNAL_KEY_MAX_LENGTH))
      end
    end
  end
end
