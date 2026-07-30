# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA0994 do
  let(:instance) { build(:va0994_full_form) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-0994')

  describe '#after_submit' do
    let(:user) { create(:user) }

    describe 'confirmation email for 0994' do
      it 'is skipped when feature flag is turned off' do
        allow(Flipper).to receive(:enabled?).with(:form0994_confirmation_email).and_return(false)
        allow(VANotify::EmailJob).to receive(:perform_async)

        subject = create(:va0994_full_form)
        subject.after_submit(user)

        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end

      context 'when they have applied for VA education benefits previously' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form0994_confirmation_email).and_return(true)
          allow(VANotify::EmailJob).to receive(:perform_async)
        end

        let(:claim) { create(:va0994_full_form) }
        let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }
        let(:expected_personalisation) do
          {
            'first_name' => 'TEST',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number,
            'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
          }
        end

        it 'sends email via V2 QueueEmailJob' do
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)

          claim.after_submit(user)
          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            'test@test.com',
            'form0994_confirmation_email_template_id',
            expected_personalisation,
            'Settings.vanotify.services.va_gov.api_key'
          )
        end
      end

      context 'when they have not applied for VA education benefits previously' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form0994_confirmation_email).and_return(true)
          allow(VANotify::EmailJob).to receive(:perform_async)
        end

        let(:claim) { create(:va0994_no_education_benefits) }
        let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }
        let(:expected_personalisation) do
          {
            'first_name' => 'TEST',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number,
            'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
          }
        end

        it 'sends email via V2 QueueEmailJob' do
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)

          claim.after_submit(user)
          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            'test@test.com',
            'form0994_extra_action_confirmation_email_template_id',
            expected_personalisation,
            'Settings.vanotify.services.va_gov.api_key'
          )
        end
      end
    end
  end
end
