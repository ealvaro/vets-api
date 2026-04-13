# frozen_string_literal: true

require 'rails_helper'
require 'dependents/notification_callback'
require 'dependents/notification_email'

RSpec.describe Dependents::NotificationEmail do
  before { allow_any_instance_of(SavedClaim::DependencyClaim).to receive(:pdf_overflow_tracking) }

  # NOTE: the factory in this case isn't truly representative of the shape of the parsed form
  # We can always expect "dependents_application" to be present, but not other properties
  let(:saved_claim) { create(:dependency_claim) }
  let(:vanotify) { double(send_email: true) }

  describe '#deliver' do
    it 'successfully sends an email' do
      expect(SavedClaim).to receive(:find).with(23).and_return saved_claim
      expect(Settings.vanotify.services).to receive(:dependents).exactly(3).times.and_call_original

      api_key = Settings.vanotify.services['dependents'].api_key
      callback_options = { callback_klass: Dependents::NotificationCallback.to_s, callback_metadata: anything }

      expect(VaNotify::Service).to receive(:new).with(api_key, callback_options).and_return(vanotify)
      expect(vanotify).to receive(:send_email).with(
        {
          email_address: 'vets.gov.user+228@gmail.com',
          template_id: Settings.vanotify.services['dependents'].email.submitted686.template_id,
          personalisation: {
            'first_name' => 'MARK',
            'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
            'confirmation_number' => saved_claim.confirmation_number
          }
        }.compact
      )

      described_class.new(23).deliver(:submitted686)
    end
  end
end
