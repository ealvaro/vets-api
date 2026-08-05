# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA5490 do
  let(:instance) { build(:va5490) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-5490')

  describe '#after_submit' do
    let(:user) { create(:user) }

    before do
      allow(Flipper).to receive(:enabled?).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:form5490_confirmation_email).and_return(true)
    end

    describe 'sends confirmation email for the 5490' do
      context 'chapter 33' do
        let(:claim) { create(:va5490_chapter33) }
        let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }
        let(:expected_personalisation) do
          {
            'first_name' => 'MARK',
            'benefit' => 'The Fry Scholarship (Chapter 33)',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number,
            'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
          }
        end

        before do
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
        end

        it 'sends email via V2 QueueEmailJob' do
          claim.after_submit(user)

          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            'email@example.com',
            'form5490_confirmation_email_template_id',
            expected_personalisation,
            'Settings.vanotify.services.va_gov.api_key'
          )
        end
      end

      context 'chapter 35' do
        let(:claim) { create(:va5490) }
        let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }
        let(:expected_personalisation) do
          {
            'first_name' => 'MARK',
            'benefit' => 'Survivors’ and Dependents’ Educational Assistance (DEA, Chapter 35)',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => confirmation_number,
            'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
          }
        end

        before do
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
        end

        it 'sends email via V2 QueueEmailJob' do
          claim.after_submit(user)

          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            'email@example.com',
            'form5490_confirmation_email_template_id',
            expected_personalisation,
            'Settings.vanotify.services.va_gov.api_key'
          )
        end
      end
    end
  end
end
