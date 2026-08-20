# frozen_string_literal: true

require 'rails_helper'
require 'education_benefits_claims/notification_email'

RSpec.describe EducationBenefitsClaims::NotificationEmail do
  let(:vanotify) { double(send_email: true) }

  {
    '22-10278' => :va10278,
    '22-0810' => :va0810,
    '22-10272' => :va10272
  }.each do |form_id, factory|
    context "for #{form_id}" do
      let(:saved_claim) { create(factory) }
      # mirrors the settings key the framework derives from the claim's form_id
      let(:service_config) { Settings.vanotify.services[form_id.tr('-', '_')] }

      describe '#deliver' do
        it 'successfully sends an email' do
          callback_options = {
            callback_klass: EducationBenefitsClaims::NotificationCallback.to_s,
            callback_metadata: be_a(Hash)
          }

          expect(VaNotify::Service).to receive(:new)
            .with(service_config.api_key, callback_options).and_return(vanotify)
          expect(vanotify).to receive(:send_email).with(
            {
              email_address: saved_claim.email,
              template_id: service_config.email.error.template_id,
              personalisation: be_a(Hash)
            }.compact
          )

          described_class.new(saved_claim.id).deliver(:error)
        end

        it 'sends the personalisation fields the templates depend on' do
          allow(VaNotify::Service).to receive(:new).and_return(vanotify)
          expect(vanotify).to receive(:send_email) do |payload|
            expect(payload[:template_id]).to eq(service_config.email.received.template_id)
            expect(payload[:personalisation].keys.map(&:to_s))
              .to match_array(%w[date_submitted confirmation_number first_name last_name])
          end

          described_class.new(saved_claim.id).deliver(:received)
        end
      end
    end
  end
end
