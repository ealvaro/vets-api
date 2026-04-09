# frozen_string_literal: true

require 'rails_helper'
require AppealsApi::Engine.root.join('spec', 'support', 'shared_examples_for_monitored_worker.rb')

describe AppealsApi::WeeklyErrorReport, type: :job do
  it_behaves_like 'a monitored worker'

  describe '#perform' do
    context 'if flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_weekly_error_report_enabled).and_return(true)
      end

      it 'sends mail' do
        expect(AppealsApi::WeeklyErrorReportMailer).to receive(:build)
          .once
          .and_return(double.tap do |mailer|
            expect(mailer).to receive(:deliver_now).once
          end)

        described_class.new.perform
      end
    end

    context 'if flipper disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_weekly_error_report_enabled).and_return(false)
      end

      it 'does not send report email' do
        expect(AppealsApi::WeeklyErrorReportMailer).not_to receive(:build)

        described_class.new.perform
      end
    end
  end
end
