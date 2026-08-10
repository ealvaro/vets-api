# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::EducationCareerCounselingClaim do
  let(:claim) { create(:education_career_counseling_claim_no_vet_information) }
  let(:user_object) { create(:evss_user, :loa3) }

  describe '#regional_office' do
    it 'returns an empty array for regional office' do
      expect(claim.regional_office).to eq([])
    end
  end

  describe '#send_to_benefits_intake!' do
    it 'formats data before sending to central mail or benefits intake' do
      allow(claim).to receive(:process_attachments!)

      expect(claim).to receive(:update).with(form: a_string_including('"veteranSocialSecurityNumber":"333224444"'))

      claim.send_to_benefits_intake!
    end

    it 'calls process_attachments! method' do
      expect(claim).to receive(:process_attachments!)
      claim.send_to_benefits_intake!
    end

    it 'calls Lighthouse::SubmitBenefitsIntakeClaim job' do
      expect_any_instance_of(Lighthouse::SubmitBenefitsIntakeClaim).to receive(:perform).with(claim.id)
      claim.send_to_benefits_intake!
    end
  end

  describe '#send_failure_email' do
    let(:email) { 'test@example.com' }
    let(:template_id) { Settings.vanotify.services.va_gov.template_id.form27_8832_action_needed_email }
    let(:expected_personalisation) do
      {
        'first_name' => 'DARDAN',
        'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
        'confirmation_number' => claim.confirmation_number
      }
    end

    before do
      allow(VANotify::EmailJob).to receive(:perform_async)
    end

    context 'when email is blank' do
      it 'does not send an email' do
        claim.send_failure_email('')
        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end

    it 'sends email via V2 QueueEmailJob' do
      allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)

      claim.send_failure_email(email)
      expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
        email,
        template_id,
        expected_personalisation,
        'Settings.vanotify.services.va_gov.api_key'
      )
      expect(VANotify::EmailJob).not_to have_received(:perform_async)
    end
  end
end
