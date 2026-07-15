# frozen_string_literal: true

require 'rails_helper'
require 'education_benefits_claims/submission_handler'
require 'education_benefits_claims/monitor'
require 'education_benefits_claims/notification_email'

RSpec.describe EducationBenefitsClaims::SubmissionHandler do
  let(:handler) { described_class.for_form_id('22-10278') }
  let(:claim) { create(:va10278) }
  let(:monitor) { double(EducationBenefitsClaims::Monitor) }
  let(:notification) { double(EducationBenefitsClaims::NotificationEmail) }
  let(:instance) { handler.new(claim.id) }

  before do
    allow(EducationBenefitsClaims::Monitor).to receive(:new).and_return monitor
    allow(EducationBenefitsClaims::NotificationEmail).to receive(:new).and_return notification
  end

  describe '::for_form_id' do
    context 'with a valid form type' do
      it 'returns a class with the right constant set' do
        klass = described_class.for_form_id('22-10278')
        expect(klass::FORM_ID).to eq('22-10278')
        expect(klass.superclass).to eq(EducationBenefitsClaims::SubmissionHandler)
      end
    end

    context 'with an invalid form type' do
      it 'raises an error' do
        expect { described_class.for_form_id('abc-123') }.to raise_error(ArgumentError, 'Invalid form id type: abc-123')
      end
    end
  end

  describe '::pending_attempts' do
    let(:claim) { create(:va10278) }
    let!(:submissions) do
      [
        create(:lighthouse_submission, :pending, saved_claim: claim, form_id: '22-10278'), # found
        create(:lighthouse_submission, :pending, saved_claim: claim, form_id: '22-10278'), # found
        create(:lighthouse_submission, :failure, saved_claim: claim, form_id: '22-10278'), # wrong status
        create(:lighthouse_submission, :vbms, saved_claim: claim, form_id: '22-10278'), # wrong status
        create(:lighthouse_submission, :pending, saved_claim: create(:va0989), form_id: '22-0989') # other form type
      ]
    end

    it 'fetches the correct submission attempts' do
      result = handler.pending_attempts
      expect(result.size).to eq(2)
      expected_ids = submissions[0..1].map { |s| s.submission_attempts.first.id }
      expect(result.map(&:id)).to match_array(expected_ids)
    end
  end

  describe 'registered handlers in SubmissionStatusJob' do
    it 'registers subclasses with FORM_ID defined, not the parent class' do
      %w[22-10278].each do |form_id|
        handler = BenefitsIntake::SubmissionStatusJob::FORM_HANDLERS[form_id]
        expect(handler).not_to be_nil, "No handler registered for #{form_id}"
        expect(handler).to be < EducationBenefitsClaims::SubmissionHandler
        expect(handler::FORM_ID).to eq(form_id)
        expect { handler.pending_attempts }.not_to raise_error
      end
    end
  end

  describe '#on_failure' do
    it 'logs silent failure avoided' do
      expect(notification).to receive(:deliver).with(:error).and_return true
      expect(monitor).to receive(:log_silent_failure_avoided).with(hash_including(claim_id: claim.id),
                                                                   call_location: nil)
      instance.handle(:failure)
    end

    it 'logs silent failure' do
      expect(notification).to receive(:deliver).with(:error).and_return false
      message = "#{handler}: on_failure silent failure not avoided"
      expect(monitor).to receive(:log_silent_failure).with(hash_including(message:), call_location: nil)
      expect { instance.handle(:failure) }.to raise_error message
    end
  end

  describe '#on_success' do
    it 'sends a received email' do
      expect(instance.handle(:success)).to be true
    end

    context 'with a 10278 form' do
      let(:handler) { described_class.for_form_id('22-10278') }
      let(:claim) { create(:va10278) }

      it 'sends a received email' do
        expect(notification).to receive(:deliver).with(:received).and_return true
        instance.handle(:success)
      end
    end
  end

  describe '#on_stale' do
    it 'does nothing' do
      expect(instance.handle(:stale)).to be true
    end
  end
end
