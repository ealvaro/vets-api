# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA5495 do
  let(:instance) { build(:va5495) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-5495')

  describe '#after_submit' do
    let(:user) { create(:user) }
    let!(:claim) { create(:va5495_with_email) }
    let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }
    let(:personalisation) do
      {
        'first_name' => 'MARK',
        'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
        'confirmation_number' => confirmation_number,
        'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:form5495_confirmation_email).and_return(true)
      allow(VANotify::EmailJob).to receive(:perform_async)
    end

    context 'when va_notify_v2_form5495_confirmation_email is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_form5495_confirmation_email).and_return(false)
      end

      it 'sends confirmation email via V1 EmailJob' do
        claim.after_submit(user)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          'email@example.com',
          'form5495_confirmation_email_template_id',
          personalisation
        )
      end
    end

    context 'when va_notify_v2_form5495_confirmation_email is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_form5495_confirmation_email).and_return(true)
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
      end

      it 'sends confirmation email via V2 QueueEmailJob' do
        claim.after_submit(user)

        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          'email@example.com',
          'form5495_confirmation_email_template_id',
          personalisation,
          'Settings.vanotify.services.va_gov.api_key'
        )
        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end
  end
end
