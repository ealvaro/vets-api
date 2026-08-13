# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA1995 do
  let(:instance) { build(:va1995) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-1995')

  describe '#after_submit' do
    let(:user) { create(:user) }

    before do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:form1995_confirmation_email).and_return(true)
    end

    describe 'sends confirmation email for the 1995' do
      let(:expected_personalisation) do
        {
          'first_name' => 'FIRST',
          'benefit' => 'Transfer of Entitlement Program (TOE)',
          'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
          'confirmation_number' => confirmation_number,
          'regional_office_address' => "P.O. Box 4616\nBuffalo, NY 14240-4616"
        }
      end
      let(:claim) { create(:va1995_full_form) }
      let(:confirmation_number) { claim.education_benefits_claim.confirmation_number }

      before do
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
      end

      it 'sends email via V2 QueueEmailJob' do
        claim.after_submit(user)

        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          'test@sample.com',
          'form1995_confirmation_email_template_id',
          expected_personalisation,
          'Settings.vanotify.services.va_gov.api_key'
        )
      end

      it 'sends email via V2 QueueEmailJob without benefit selected' do
        parsed_form_data = JSON.parse(claim.form)
        parsed_form_data.delete('benefit')
        claim.form = parsed_form_data.to_json

        claim.after_submit(user)

        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          'test@sample.com',
          'form1995_confirmation_email_template_id',
          expected_personalisation.merge('benefit' => ''),
          'Settings.vanotify.services.va_gov.api_key'
        )
      end
    end
  end
end
