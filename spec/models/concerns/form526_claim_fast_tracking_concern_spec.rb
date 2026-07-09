# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form526ClaimFastTrackingConcern do
  subject { create(:form526_submission, submitted_claim_id: 600_130_094) }

  before do
    subject.save_metadata(forward_to_mas_all_claims: true)
    allow(StatsD).to receive(:increment)
    allow(Flipper).to receive(:enabled?).and_call_original
  end

  describe '#conditionally_notify_mas' do
    context 'when the disability_526_pause_mas_notification flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:disability_526_pause_mas_notification).and_return(true)
      end

      it 'logs the claim id and does not send to MAS' do
        expect(RrdMasNotificationMailer).not_to receive(:build)
        expect(MailAutomation::Client).not_to receive(:new)
        expect(Rails.logger).to receive(:info).with(
          'MAS notification paused; claim not sent to MAS',
          submission_id: subject.id, submitted_claim_id: subject.submitted_claim_id
        )

        subject.send(:conditionally_notify_mas)
      end

      it 'increments the paused metric' do
        subject.send(:conditionally_notify_mas)

        expect(StatsD).to have_received(:increment)
          .with('worker.rapid_ready_for_decision.notify_mas.paused')
      end
    end

    context 'when the disability_526_pause_mas_notification flag is disabled' do
      let(:client) { instance_double(MailAutomation::Client) }

      before do
        allow(Flipper).to receive(:enabled?).with(:disability_526_pause_mas_notification).and_return(false)
        allow(RrdMasNotificationMailer).to receive(:build)
          .and_return(instance_double(ActionMailer::MessageDelivery, deliver_now: true))
        allow(MailAutomation::Client).to receive(:new).and_return(client)
        allow(client).to receive(:initiate_apcas_processing)
          .and_return(instance_double(Faraday::Response, body: { 'packetId' => '12345' }))
      end

      it 'sends the claim to MAS' do
        expect(RrdMasNotificationMailer).to receive(:build)
          .and_return(instance_double(ActionMailer::MessageDelivery, deliver_now: true))
        expect(client).to receive(:initiate_apcas_processing)

        subject.send(:conditionally_notify_mas)

        expect(StatsD).to have_received(:increment)
          .with('worker.rapid_ready_for_decision.notify_mas.success')
      end

      it 'does not increment the paused metric' do
        subject.send(:conditionally_notify_mas)

        expect(StatsD).not_to have_received(:increment)
          .with('worker.rapid_ready_for_decision.notify_mas.paused')
      end
    end

    context 'when the claim is not flagged to forward to MAS' do
      before do
        subject.save_metadata(forward_to_mas_all_claims: false)
        allow(Flipper).to receive(:enabled?).with(:disability_526_pause_mas_notification).and_return(true)
      end

      it 'does nothing' do
        expect(Rails.logger).not_to receive(:info)
          .with('MAS notification paused; claim not sent to MAS', anything)
        expect(MailAutomation::Client).not_to receive(:new)

        subject.send(:conditionally_notify_mas)
      end
    end
  end
end
