# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA10275 do
  let(:instance) { build(:va10275) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-10275')

  describe 'retention_period' do
    it 'returns the correct period' do
      expect(instance.retention_period).to be_within(1.minute).of(60.days)
    end
  end

  describe '#after_submit' do
    let(:user) { create(:user) }

    before do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:va_notify_v2_form10275_submission_email).and_return(false)
    end

    describe 'confirmation email for 10275' do
      subject { create(:va10275) }

      context 'when va_notify_v2_form10275_submission_email is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_notify_v2_form10275_submission_email).and_return(false)
        end

        it 'sends the email via V1 EmailJob' do
          allow(VANotify::EmailJob).to receive(:perform_async)

          subject.after_submit(user)

          expect(VANotify::EmailJob).to have_received(:perform_async).with(
            'form_10275@example.com',
            'form10275_submission_email_template_id',
            satisfy do |args|
              args[:submission_id] == subject.id &&
              args[:agreement_type] == 'New commitment' &&
              args[:institution_details].include?('Springfield University') &&
              args[:institution_details].include?('US123456') &&
              args[:additional_locations].include?('Springfield Technical Institute') &&
              args[:additional_locations].include?('US654321') &&
              args[:points_of_contact].include?('michael.brown@springfield.edu') &&
              args[:points_of_contact].include?('emily.johnson@springfield.edu') &&
              args[:submission_information].include?('Robert Smith')
            end,
            'fake_secret',
            anything
          )
        end
      end

      context 'when va_notify_v2_form10275_submission_email is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_notify_v2_form10275_submission_email).and_return(true)
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
          allow(VANotify::EmailJob).to receive(:perform_async)
        end

        it 'sends the email via V2 QueueEmailJob' do
          subject.after_submit(user)

          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            'form_10275@example.com',
            'form10275_submission_email_template_id',
            satisfy do |args|
              args[:submission_id] == subject.id &&
              args[:agreement_type] == 'New commitment' &&
              args[:institution_details].include?('Springfield University') &&
              args[:institution_details].include?('US123456') &&
              args[:additional_locations].include?('Springfield Technical Institute') &&
              args[:additional_locations].include?('US654321') &&
              args[:points_of_contact].include?('michael.brown@springfield.edu') &&
              args[:points_of_contact].include?('emily.johnson@springfield.edu') &&
              args[:submission_information].include?('Robert Smith')
            end,
            'Settings.vanotify.services.va_gov.api_key',
            anything
          )
          expect(VANotify::EmailJob).not_to have_received(:perform_async)
        end
      end
    end
  end
end
