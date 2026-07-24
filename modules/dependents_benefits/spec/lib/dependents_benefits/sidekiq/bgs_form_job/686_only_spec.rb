# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/sidekiq/bgs_form_job'
require 'bgs/service'

RSpec.describe DependentsBenefits::Sidekiq::BGSFormJob, type: :job do
  let(:parent_claim) { create(:dependents_claim) }
  let(:job) { described_class.new }
  let(:user) { create(:evss_user) }
  let(:bgs_stub) { double('BGS::Service') }
  let(:bep_awards_stub) { double('BEP::Awards::Service') }
  let(:proc_id) { 101 }
  let(:create_proc_response) { OpenStruct.new({ vnp_proc_id: proc_id }) }

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
    parent_claim.update!(form: form_data.to_json)

    user_data = DependentsBenefits::UserData.new(user, parent_claim.parsed_form)
    SavedClaimGroup.new(claim_group_guid: parent_claim.guid,
                        parent_claim_id: parent_claim.id,
                        saved_claim_id: parent_claim.id,
                        user_data: user_data.get_user_json).save!

    DependentsBenefits::Generators::Claim686cGenerator.new(parent_claim.parsed_form, parent_claim.id).generate
    # intentionally do not generate 674 claim

    allow(BGS::Service).to receive(:new).and_return(bgs_stub)
    allow(bgs_stub).to receive(:create_proc).and_return(create_proc_response)
    allow(bgs_stub).to receive(:create_proc_form)
    allow(bgs_stub).to receive(:update_proc)
    allow(bgs_stub).to receive_messages(create_participant: {}, find_benefit_claim_type_increment: {},
                                        create_address: {}, get_regional_office_by_zip_code: {},
                                        create_relationship: {}, vnp_create_benefit_claim: {},
                                        insert_benefit_claim: {}, vnp_benefit_claim_update: {},
                                        create_child_school: {}, create_note: {},
                                        create_child_student: {},
                                        find_regional_offices: {}, create_person: {}, create_phone: {})

    allow(BEP::Awards::Service).to receive(:new).and_return(bep_awards_stub)
    allow(bep_awards_stub).to receive(:get_awards_pension).and_return(
      OpenStruct.new({ body: { 'awards_pension' => { 'is_in_receipt_of_pension' => false } } })
    )
  end

  context 'parent claim has only 686 parts' do
    let(:claim686) { DependentsBenefits::AddRemoveDependent.first }
    let(:claim674) { DependentsBenefits::SchoolAttendanceApproval.first }

    describe '#perform' do
      it 'creates a single BGS proc' do
        expect(parent_claim.submittable_686?).to be(true)
        expect(parent_claim.submittable_674?).to be(false)
        expect(DependentsBenefits::PrimaryDependencyClaim.count).to eq(1)
        expect(DependentsBenefits::AddRemoveDependent.count).to eq(1)
        expect(DependentsBenefits::SchoolAttendanceApproval.count).to eq(0)
        expect(parent_claim.send(:child_claims)).to contain_exactly(claim686)

        expect(bgs_stub).to receive(:create_proc).with(proc_state: 'Started').once
        expect(bgs_stub).to receive(:update_proc).with(proc_id, proc_state: 'MANUAL_VAGOV').once

        job.perform(parent_claim.id)
      end
    end
  end
end
