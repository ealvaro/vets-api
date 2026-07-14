# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/sidekiq/claims_api_job'

RSpec.describe DependentsBenefits::Sidekiq::ClaimsApiJob, type: :job do
  let(:user) { create(:evss_user) }
  let(:parent_claim) { create(:dependents_claim) }
  let(:perform) { described_class.new.perform(parent_claim.id) }

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
        parent_claim.update!(form: form_data.to_json)
        create_child_claims(parent_claim)
      end

      it 'creates a claim and contentions' do
        skip('check claim and contention ids')
      end

      it 'sends the right data to bgs' do
        skip('check bgs mock calls')
      end
    end

    context 'with a 674-only form' do
      before do
        form_data = parent_claim.parsed_form
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
        parent_claim.update!(form: form_data.to_json)
        create_child_claims(parent_claim)
      end

      it 'creates a claim and contentions' do
        skip('check claim and contention ids')
      end

      it 'sends the right data to bgs' do
        skip('check bgs mock calls')
      end
    end

    context 'with a 686+674 form' do
      before do
        create_child_claims(parent_claim)
      end

      it 'creates a claim and contentions' do
        skip('check claim and contention ids')
      end

      it 'sends the right data to bgs' do
        skip('check bgs mock calls')
      end
    end
  end
end
