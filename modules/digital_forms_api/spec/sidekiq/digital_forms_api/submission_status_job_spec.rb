# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DigitalFormsApi::SubmissionStatusJob, type: :job do
  subject(:job) { described_class.new }

  let(:service) { instance_double(DigitalFormsApi::Service::Submissions) }
  let(:poll_metric) { described_class::POLL_METRIC }
  let(:queue_depth_metric) { "#{described_class::STATSD_PREFIX}.queue_depth" }
  let(:duration_metric) { "#{described_class::STATSD_PREFIX}.duration_ms" }

  def pending_attempt(form_id: '21-686c', **attrs)
    submission = create(:digital_forms_api_submission, form_id:)
    create(:digital_forms_api_submission_attempt, submission:, **attrs)
  end

  def response_with(document_id)
    body = { 'submission' => { 'document' => document_id ? { 'documentId' => document_id } : {} } }
    double('Faraday::Env', body:)
  end

  before do
    allow(DigitalFormsApi::Service::Submissions).to receive(:new).and_return(service)
    allow(Flipper).to receive(:enabled?).with(anything).and_call_original
    allow(Flipper).to receive(:enabled?).with(described_class::FLIPPER_FLAG).and_return(true)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    %i[increment gauge measure].each { |m| allow(StatsD).to receive(m) }
  end

  describe 'status inference' do
    # retrieve behavior -> expected attempt status (which the cascade also copies to the parent's
    # latest_status) + expected poll tags. Asserting latest_status == status in every row proves
    # both the cascade (accepted/failed) and the "never written directly" invariant (pending rows).
    {
      'documentId present -> accepted' =>
        { doc: true, status: 'accepted', tags: ['form_id:21-686c', 'outcome:success'] },
      '200 without documentId -> stays pending' =>
        { doc: false, status: 'pending', tags: ['form_id:21-686c', 'outcome:still_pending'] },
      '404 -> failed' =>
        { err: :not_found, status: 'failed', tags: ['form_id:21-686c', 'outcome:failure', 'http_status:404'] },
      'non-404 client error -> stays pending' =>
        { err: :error, status: 'pending', tags: ['form_id:21-686c', 'outcome:error', 'http_status:503'] },
      'unexpected error -> stays pending' =>
        { std: true, status: 'pending', tags: ['form_id:21-686c', 'outcome:error'] }
    }.each do |desc, c|
      it desc, :aggregate_failures do
        attempt = pending_attempt
        if c[:err] then allow(service).to receive(:retrieve).and_raise(build(:digital_forms_service_error, c[:err]))
        elsif c[:std] then allow(service).to receive(:retrieve).and_raise(StandardError, 'boom')
        else allow(service).to receive(:retrieve).and_return(response_with(c[:doc] ? SecureRandom.uuid : nil))
        end

        job.perform
        expect(attempt.reload.status).to eq(c[:status])
        expect(attempt.submission.reload.latest_status).to eq(c[:status]) # cascade only; never written directly
        expect(StatsD).to have_received(:increment).with(poll_metric, tags: c[:tags])
      end
    end
  end

  it 'touches a non-terminal attempt so the queue round-robins (no starvation)', :aggregate_failures do
    attempt = pending_attempt(updated_at: 2.hours.ago)
    allow(service).to receive(:retrieve).and_return(response_with(nil)) # still_pending -> no transition

    expect { job.perform }.to(change { attempt.reload.updated_at })
    expect(attempt.reload).to be_pending # bumped, still pending — moves to the back next run
  end

  describe 'per-record failure isolation (one bad row never aborts the batch)' do
    let!(:bad) { pending_attempt(updated_at: 1.hour.ago) } # polled first (oldest)
    let!(:good) { pending_attempt(updated_at: 5.minutes.ago) }

    before do
      allow(service).to receive(:retrieve).with(good.submission.bip_submission_id, form_id: '21-686c')
                                          .and_return(response_with(SecureRandom.uuid))
    end

    it 'isolates an upstream error on the bad row and still polls the good one' do
      allow(service).to receive(:retrieve).with(bad.submission.bip_submission_id, form_id: '21-686c')
                                          .and_raise(StandardError, 'boom')
      job.perform
      expect(good.reload.status).to eq('accepted')
    end

    it 'isolates a failing transition write (404 then failed! raises)' do
      allow(service).to receive(:retrieve).with(bad.submission.bip_submission_id, form_id: '21-686c')
                                          .and_raise(build(:digital_forms_service_error, :not_found))
      allow_any_instance_of(DigitalFormsApi::SubmissionAttempt)
        .to receive(:failed!).and_raise(ActiveRecord::StatementInvalid, 'deadlock')
      job.perform
      expect(good.reload.status).to eq('accepted')
    end
  end

  it 'gauges the backlog, measures duration, and caps at MAX_POLL_BATCH oldest-first', :aggregate_failures do
    stub_const("#{described_class}::MAX_POLL_BATCH", 1)
    old = pending_attempt(updated_at: 2.hours.ago)
    pending_attempt(updated_at: 5.minutes.ago) # newer -> skipped this run
    allow(service).to receive(:retrieve).and_return(response_with(nil))

    job.perform

    expect(StatsD).to have_received(:gauge).with(queue_depth_metric, 2) # full backlog, uncapped
    expect(StatsD).to have_received(:measure).with(duration_metric, kind_of(Numeric))
    expect(service).to have_received(:retrieve).once.with(old.submission.bip_submission_id, form_id: '21-686c')
  end

  it 'no-ops safely on an empty queue (still gauges 0)', :aggregate_failures do
    expect { job.perform }.not_to raise_error
    expect(DigitalFormsApi::Service::Submissions).not_to have_received(:new)
    expect(StatsD).to have_received(:gauge).with(queue_depth_metric, 0)
  end

  it 'no-ops when the Flipper flag is disabled', :aggregate_failures do
    allow(Flipper).to receive(:enabled?).with(described_class::FLIPPER_FLAG).and_return(false)
    pending_attempt
    job.perform
    expect(DigitalFormsApi::Service::Submissions).not_to have_received(:new)
    expect(StatsD).not_to have_received(:gauge)
  end
end
