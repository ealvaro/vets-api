# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA10282 do
  let(:instance) { build(:va10282) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-10282')

  describe '#after_submit' do
    subject { create(:va10282) }

    let(:user) { create(:user) }

    context 'with the feature enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form22_10282_confirmation_email).and_return(true)
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
      end

      it 'sends email via V2 QueueEmailJob' do
        subject.after_submit(user)
        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          'test@sample.com',
          Settings.vanotify.services.va_gov.template_id.form22_10282_confirmation_email,
          {
            'first_name' => 'MARK',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => subject.education_benefits_claim.confirmation_number
          },
          'Settings.vanotify.services.va_gov.api_key'
        )
      end
    end

    context 'with the feature disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form22_10282_confirmation_email).and_return(false)
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
      end

      it 'does nothing' do
        subject.after_submit(user)
        expect(VANotify::V2::QueueEmailJob).not_to have_received(:enqueue)
      end
    end
  end
end
