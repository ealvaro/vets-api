# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/ccd_service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::CcdService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class }

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  describe '#get_ccd_url' do
    let(:client_double) { instance_double(UnifiedHealthData::Client) }
    let(:ccd_body) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_ready_success.json').read)
    end
    let(:ccd_response) { build_faraday_response(ccd_body) }
    let(:job_id) { '12043' }

    before do
      allow(UnifiedHealthData::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:get_ccd).and_return(ccd_response)
    end

    it 'calls get_ccd on the client with the job_id' do
      service.get_ccd_url(job_id:)

      expect(client_double).to have_received(:get_ccd).with(job_id:)
    end

    it 'returns the presigned URL for the default xml format' do
      result = service.get_ccd_url(job_id:)

      expect(result).to be_present
      expect(result).to include('original.xml')
    end

    it 'returns the presigned URL for html format' do
      result = service.get_ccd_url(job_id:, format: 'html')

      expect(result).to be_present
      expect(result).to include('rendered.html')
    end

    it 'returns the presigned URL for pdf format' do
      result = service.get_ccd_url(job_id:, format: 'pdf')

      expect(result).to be_present
      expect(result).to include('rendered.pdf')
    end

    it 'returns nil for an unknown format' do
      result = service.get_ccd_url(job_id:, format: 'txt')

      expect(result).to be_nil
    end

    context 'when the response has no Binary resources' do
      let(:ccd_body) do
        {
          'resourceType' => 'Bundle',
          'type' => 'collection',
          'entry' => [
            {
              'resource' => {
                'resourceType' => 'DocumentReference',
                'id' => '999',
                'meta' => { 'lastUpdated' => '2026-01-01T00:00:00Z' }
              }
            }
          ]
        }
      end

      it 'returns nil' do
        result = service.get_ccd_url(job_id:)

        expect(result).to be_nil
      end
    end
  end

  describe '#get_ccd_status' do
    let(:client_double) { instance_double(UnifiedHealthData::Client) }
    let(:ccd_response) { build_faraday_response(ccd_body, status: response_status) }

    before do
      allow(UnifiedHealthData::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:get_ccd).and_return(ccd_response)
    end

    context 'when task correlation is in progress (UUID job_id, nil task_id)' do
      let(:ccd_body) do
        JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_generate.json').read)
      end
      let(:response_status) { 202 }
      let(:job_id) { 'b0733653-30b4-411f-a997-7453039e510c' }

      it 'calls get_ccd on the client with the job_id' do
        service.get_ccd_status(job_id:)

        expect(client_double).to have_received(:get_ccd).with(job_id:)
      end

      it 'returns a Ccd model with UUID job_id and nil task_id' do
        result = service.get_ccd_status(job_id:)

        expect(result).to be_a(UnifiedHealthData::Ccd)
        expect(result.status).to eq('NOT_READY')
        expect(result.job_id).to eq('b0733653-30b4-411f-a997-7453039e510c')
        expect(result.task_id).to be_nil
        expect(result.source).to eq('oracle-health')
        expect(result.message).to eq('CCD processing requested; awaiting task correlation')
        expect(result.retry_after_seconds).to eq(10)
        expect(result.http_status).to eq(202)
      end
    end

    context 'when task is correlated but not ready (short-format job_id and task_id)' do
      let(:ccd_body) do
        JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_task_not_ready.json').read)
      end
      let(:response_status) { 202 }
      let(:job_id) { '13002' }

      it 'calls get_ccd on the client with the job_id' do
        service.get_ccd_status(job_id:)

        expect(client_double).to have_received(:get_ccd).with(job_id:)
      end

      it 'returns a Ccd model with matching job_id and task_id' do
        result = service.get_ccd_status(job_id:)

        expect(result).to be_a(UnifiedHealthData::Ccd)
        expect(result.status).to eq('NOT_READY')
        expect(result.job_id).to eq('13002')
        expect(result.task_id).to eq('13002')
        expect(result.source).to eq('oracle-health')
        expect(result.message).to eq('CCD processing requested or in progress')
        expect(result.retry_after_seconds).to eq(10)
        expect(result.http_status).to eq(202)
      end
    end

    context 'when job has succeeded (FHIR Bundle with format statuses)' do
      let(:ccd_body) do
        JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_ready_success.json').read)
      end
      let(:response_status) { 200 }
      let(:job_id) { '12043' }

      it 'calls get_ccd on the client with the job_id' do
        service.get_ccd_status(job_id:)

        expect(client_double).to have_received(:get_ccd).with(job_id:)
      end

      it 'returns a Ccd model with per-format statuses and metadata' do
        result = service.get_ccd_status(job_id:)

        expect(result).to be_a(UnifiedHealthData::Ccd)
        expect(result.job_id).to eq('12043')
        expect(result.task_id).to eq('12043')
        expect(result.source).to eq('oracle-health')
        expect(result.message).to eq('Success')
        expect(result.authored_on).to eq('2026-03-03T10:18:36.400-05:00')
        expect(result.xml).to eq('READY')
        expect(result.html).to eq('READY')
        expect(result.pdf).to eq('READY')
        expect(result.http_status).to eq(200)
      end
    end
  end

  describe '#get_ccd_jobs' do
    let(:client_double) { instance_double(UnifiedHealthData::Client) }

    let(:mixed_jobs_body) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_patient_all_jobs_mixed.json').read)
    end

    let(:jobs_response) { build_faraday_response(mixed_jobs_body) }

    before do
      allow(UnifiedHealthData::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:get_ccd_jobs_by_user).and_return(jobs_response)
    end

    context 'when Tasks are present' do
      it 'calls get_ccd_jobs_by_user on the client with the patient_id' do
        service.get_ccd_jobs

        expect(client_double).to have_received(:get_ccd_jobs_by_user).with(patient_id: user.icn)
      end

      it 'returns an array of Ccd models parsed from Task entries' do
        result = service.get_ccd_jobs

        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
        expect(result).to all(be_a(UnifiedHealthData::Ccd))
      end

      it 'extracts task metadata from each Task' do
        result = service.get_ccd_jobs

        expect(result.map(&:task_id)).to eq(%w[5001 5002 5003])
        expect(result.map(&:status)).to all(eq('completed'))
        expect(result.map(&:message)).to all(eq('FULL_SUCCESS'))
      end
    end

    context 'when no Tasks are present' do
      let(:mixed_jobs_body) do
        { 'resourceType' => 'Bundle', 'type' => 'searchset', 'entry' => [] }
      end

      it 'returns an empty array' do
        result = service.get_ccd_jobs

        expect(result).to eq([])
      end
    end

    context 'when response contains only OperationOutcome entries' do
      let(:mixed_jobs_body) do
        {
          'resourceType' => 'Bundle',
          'type' => 'searchset',
          'entry' => [
            {
              'resource' => {
                'resourceType' => 'OperationOutcome',
                'issue' => [{ 'severity' => 'information', 'diagnostics' => 'No jobs found' }]
              }
            }
          ]
        }
      end

      it 'returns an empty array' do
        result = service.get_ccd_jobs

        expect(result).to eq([])
      end
    end
  end

  describe '#initiate_ccd' do
    let(:client_double) { instance_double(UnifiedHealthData::Client) }

    let(:initiate_body) do
      {
        'status' => 'NOT_READY',
        'jobId' => '790f06ca-5ab7-473c-b7cf-112643a0a108',
        'taskId' => nil,
        'source' => 'oracle-health',
        'message' => 'CCD processing requested; awaiting task correlation',
        'retryAfterSeconds' => 10
      }
    end

    let(:initiate_response) { build_faraday_response(initiate_body, status: 202) }

    before do
      allow(UnifiedHealthData::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:generate_ccd).and_return(initiate_response)
    end

    it 'calls generate_ccd to initiate generation' do
      service.initiate_ccd

      expect(client_double).to have_received(:generate_ccd).with(
        patient_id: user.icn,
        start_date: '1900-01-01',
        end_date: Time.zone.today.to_s
      )
    end

    it 'returns the parsed initiation response' do
      result = service.initiate_ccd

      expect(result).to be_a(UnifiedHealthData::Ccd)
      expect(result.status).to eq('NOT_READY')
      expect(result.job_id).to eq('790f06ca-5ab7-473c-b7cf-112643a0a108')
      expect(result.task_id).to be_nil
      expect(result.source).to eq('oracle-health')
      expect(result.message).to eq('CCD processing requested; awaiting task correlation')
      expect(result.retry_after_seconds).to eq(10)
      expect(result.http_status).to eq(202)
    end
  end
end
