# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsEvidence::ReconcileCreatedSubmissionsJob, type: :job do
  subject(:job) { described_class.new }

  let(:status) { BenefitsDocuments::Constants::UPLOAD_STATUS }
  let(:user_account) { create(:user_account, icn: '123498767V234859') }

  def created_submission(content_name: 'DD214.pdf', age: 1.hour.ago, claim_id: 'SC10879', account: user_account)
    metadata = { personalisation: { file_name: 'DD214.pdf', content_name:,
                                    document_type_id: 34, document_type: 'Correspondence' } }
    create(:cst_sc_evidence_submission, user_account: account, caseflow_claim_id: claim_id,
                                        upload_status: status[:CREATED], created_at: age,
                                        template_metadata: metadata.to_json)
  end

  def stub_search(files)
    allow_any_instance_of(ClaimsEvidenceApi::Service::Search)
      .to receive(:find).and_return(double(body: { 'files' => files }))
  end

  def found_document(upload_source: described_class::UPLOAD_SOURCE)
    { 'uuid' => 'filed-uuid',
      'currentVersion' => { 'systemData' => { 'uploadSource' => upload_source } } }
  end

  describe '#perform' do
    it 'marks a record SUCCESS when Claims Evidence has the document' do
      submission = created_submission
      stub_search([found_document])

      job.perform

      expect(submission.reload.upload_status).to eq(status[:SUCCESS])
    end

    # An empty result is not proof the document is missing -- indexing lag looks the same.
    it 'leaves a record CREATED when Claims Evidence does not have the document' do
      submission = created_submission
      stub_search([])

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    # A response we could not read is not an answer either.
    it 'leaves a record CREATED when the search answers with something other than a result set' do
      submission = created_submission
      allow_any_instance_of(ClaimsEvidenceApi::Service::Search).to receive(:find).and_return(double(body: ''))

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    it 'searches for the recorded contentName, not the Veteran filename' do
      created_submission(content_name: 'DD214_34_SC10879.pdf')
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search)
        .to receive(:find).with(filters: { contentName: 'DD214_34_SC10879.pdf' })
        .and_return(double(body: { 'files' => [] }))

      job.perform
    end

    # The Veteran's file is received before the record is written, so a live record is only
    # in flight for the Claims Evidence call. Anything younger may still be running.
    it 'does not modify a record younger than the threshold' do
      submission = created_submission(age: 1.minute.ago)
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search).not_to receive(:find)

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    it 'does not modify a record older than the search window' do
      submission = created_submission(age: 2.days.ago)
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search).not_to receive(:find)

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    # CREATED is a live in-flight status on the Lighthouse, EVSS and CHAMPVA paths.
    it 'ignores records that are not supplemental claim uploads' do
      lighthouse = create(:bd_evidence_submission_for_deletion, upload_status: status[:CREATED],
                                                                created_at: 1.hour.ago)
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search).not_to receive(:find)

      job.perform

      expect(lighthouse.reload.upload_status).to eq(status[:CREATED])
    end

    it 'does not modify a record with no contentName to search for' do
      submission = created_submission(content_name: nil)
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search).not_to receive(:find)

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    it 'does not modify a record whose metadata cannot be parsed' do
      submission = created_submission
      submission.update!(template_metadata: 'not-json')
      expect_any_instance_of(ClaimsEvidenceApi::Service::Search).not_to receive(:find)

      job.perform

      expect(submission.reload.upload_status).to eq(status[:CREATED])
    end

    describe 'deciding whether the document Claims Evidence returned is ours' do
      it 'marks the record SUCCESS when the document was uploaded by us' do
        submission = created_submission
        stub_search([found_document])

        job.perform

        expect(submission.reload.upload_status).to eq(status[:SUCCESS])
      end

      # 'lighthouse' is a real value: a VA.gov upload, but through a different path than vet-api's Claims Evidence.
      ['lighthouse', 'VBMS-UI', nil].each do |upload_source|
        it "leaves the record CREATED when uploadSource is #{upload_source.inspect}" do
          submission = created_submission
          stub_search([found_document(upload_source:)])

          job.perform

          expect(submission.reload.upload_status).to eq(status[:CREATED])
        end
      end

      it 'counts a document with a different upload source' do
        created_submission
        stub_search([found_document(upload_source: 'lighthouse')])
        allow(StatsD).to receive(:increment).and_call_original

        job.perform

        expect(StatsD).to have_received(:increment).with(
          'worker.claims_evidence.reconcile_created_submissions.count', 1,
          tags: ['outcome:upload_source_mismatch']
        )
      end
    end

    it 'reports what it settled' do
      created_submission
      stub_search([found_document])
      allow(StatsD).to receive(:increment).and_call_original

      job.perform

      expect(StatsD).to have_received(:increment).with(
        'worker.claims_evidence.reconcile_created_submissions.count', 1, tags: ['outcome:filed']
      )
    end

    it 'counts a record whose metadata carries no contentName' do
      created_submission(content_name: nil)
      allow(StatsD).to receive(:increment).and_call_original

      job.perform

      expect(StatsD).to have_received(:increment).with(
        'worker.claims_evidence.reconcile_created_submissions.count', 1,
        tags: ['outcome:invalid_metadata']
      )
    end

    describe 'reporting records it has given up on' do
      it 'reports none while every record is still being retried' do
        created_submission
        stub_search([found_document])
        allow(StatsD).to receive(:gauge).and_call_original

        job.perform

        expect(StatsD).to have_received(:gauge)
          .with('worker.claims_evidence.reconcile_created_submissions.exhausted', 0)
      end

      it 'reports a record it has stopped retrying' do
        created_submission(age: 25.hours.ago)
        allow(StatsD).to receive(:gauge).and_call_original

        job.perform

        expect(StatsD).to have_received(:gauge)
          .with('worker.claims_evidence.reconcile_created_submissions.exhausted', 1)
      end
    end

    it 'reports the error count even when nothing errored' do
      created_submission
      stub_search([found_document])
      allow(StatsD).to receive(:increment).and_call_original

      job.perform

      expect(StatsD).to have_received(:increment).with(
        'worker.claims_evidence.reconcile_created_submissions.error', 0
      )
    end

    # One unresolvable record must not stop the rest; the next run tries again.
    it 'carries on when a single record cannot be resolved' do
      failing = created_submission(content_name: 'first.pdf')
      resolvable = created_submission(content_name: 'second.pdf')

      allow_any_instance_of(ClaimsEvidenceApi::Service::Search).to receive(:find) do |_s, filters:|
        raise Common::Client::Errors::ClientError if filters[:contentName] == 'first.pdf'

        double(body: { 'files' => [found_document] })
      end

      job.perform

      expect(failing.reload.upload_status).to eq(status[:CREATED])
      expect(resolvable.reload.upload_status).to eq(status[:SUCCESS])
    end

    it 'does not retry, leaving the schedule to pick the work back up' do
      expect(described_class.sidekiq_options['retry']).to be(0)
    end
  end
end
