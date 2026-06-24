# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/avs_service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::AvsService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  describe '#get_all_avs_metadata' do
    let(:all_avs_response) do
      {
        'resourceType' => 'Bundle',
        'type' => 'collection',
        'entry' => [
          {
            'resource' => {
              'resourceType' => 'DocumentReference',
              'id' => 'doc-1',
              'type' => {
                'coding' => [
                  {
                    'system' => 'https://fhir.cerner.com/codeSet/72',
                    'code' => '4189669',
                    'display' => 'Ambulatory Patient Summary',
                    'userSelected' => true
                  },
                  {
                    'system' => 'http://loinc.org',
                    'code' => '96345-4',
                    'display' => 'Ambulatory Patient Summary',
                    'userSelected' => false
                  }
                ]
              },
              'context' => {
                'encounter' => [
                  { 'reference' => 'Encounter/enc-1' }
                ]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'DocumentReference',
              'id' => 'doc-2',
              'type' => {
                'coding' => [
                  {
                    'system' => 'https://fhir.cerner.com/codeSet/72',
                    'code' => '2820526',
                    'display' => 'Primary Care Note',
                    'userSelected' => true
                  }
                ]
              },
              'context' => {
                'encounter' => [
                  { 'reference' => 'Encounter/enc-2' }
                ]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Encounter',
              'id' => 'enc-1',
              'appointment' => [
                { 'reference' => 'Appointment/4818609' }
              ]
            }
          },
          {
            'resource' => {
              'resourceType' => 'Encounter',
              'id' => 'enc-2',
              'appointment' => [
                { 'reference' => 'Appointment/4818609' },
                { 'reference' => 'Appointment/9990001' }
              ]
            }
          },
          {
            'resource' => {
              'resourceType' => 'OperationOutcome',
              'id' => 'oo-1',
              'issue' => [{ 'severity' => 'information', 'code' => 'informational' }]
            }
          },
          {
            'resource' => {
              'resourceType' => 'Appointment',
              'id' => 'appt-1'
            }
          }
        ]
      }
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_all_avs)
        .and_return(build_faraday_response(all_avs_response))
    end

    it 'returns extracted document references and encounters' do
      result = service.get_all_avs_metadata(start_date: '2025-01-01', end_date: '2025-12-31')

      doc_refs, encounters = result
      expect(doc_refs.size).to eq(2)
      expect(doc_refs.first['id']).to eq('doc-1')
      expect(doc_refs.last['id']).to eq('doc-2')
      expect(encounters.size).to eq(2)
      expect(encounters.first['id']).to eq('enc-1')
      expect(encounters.last['id']).to eq('enc-2')
    end

    it 'excludes non-DocumentReference and non-Encounter resource types' do
      result = service.get_all_avs_metadata(start_date: '2025-01-01', end_date: '2025-12-31')

      doc_refs, encounters = result
      all_returned = doc_refs + encounters
      returned_types = all_returned.map { |entry| entry['resourceType'] }.uniq
      expect(returned_types).to contain_exactly('DocumentReference', 'Encounter')
    end

    it 'returns empty arrays when start_date is after end_date' do
      expect_any_instance_of(UnifiedHealthData::Client).not_to receive(:get_all_avs)
      result = service.get_all_avs_metadata(start_date: '2025-12-31', end_date: '2025-01-01')
      expect(result).to eq([[], []])
    end

    it 'does not short-circuit when start_date equals end_date' do
      result = service.get_all_avs_metadata(start_date: '2025-06-15', end_date: '2025-06-15')
      doc_refs, encounters = result
      expect(doc_refs.size).to eq(2)
      expect(encounters.size).to eq(2)
    end

    it 'accepts Date objects for start_date and end_date' do
      result = service.get_all_avs_metadata(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31))

      doc_refs, encounters = result
      expect(doc_refs.size).to eq(2)
      expect(encounters.size).to eq(2)
    end
  end

  describe '#get_avs_binary_data' do
    let(:avs_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'after_visit_summary.json'
      ).read)
    end

    let(:sample_client_response) do
      build_faraday_response(avs_sample_response)
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_by_docref)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      it 'returns avs binary data and content type' do
        avs = service.get_avs_binary_data(doc_id: '15249638961')
        expect(avs).to have_attributes(
          {
            'content_type' => 'application/pdf',
            'binary' => /JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9TdWJ0e/i
          }
        )
      end

      it 'fetches the binary by doc_id only (no appt_id)' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_by_docref)
          .with(doc_id: '15249638961')
          .and_return(sample_client_response)
        service.get_avs_binary_data(doc_id: '15249638961')
      end

      it 'returns nil when the doc_id is not present in the response' do
        avs = service.get_avs_binary_data(doc_id: 'unknown-doc')
        expect(avs).to be_nil
      end
    end

    context 'when the binary is a separate Bundle entry (Oracle Health live shape)' do
      # Live document-reference/oracle-health/:id?includeBinary=true responses return the PDF
      # as a top-level Binary entry referenced by content[].attachment.url, not inline.
      let(:avs_sample_response) do
        JSON.parse(Rails.root.join(
          'spec', 'fixtures', 'unified_health_data', 'after_visit_summary_binary_reference.json'
        ).read)
      end

      it 'resolves the sibling Binary referenced by content[].attachment.url' do
        avs = service.get_avs_binary_data(doc_id: '20875864668')
        expect(avs).not_to be_nil
        expect(avs).to have_attributes(
          'content_type' => 'application/pdf',
          'binary' => start_with('JVBERi0xLjQKJeLj')
        )
      end
    end

    context 'when the user has no ICN' do
      let(:user) { build(:user, :loa3, icn: nil) }

      it 'raises ParameterMissing' do
        expect do
          service.get_avs_binary_data(doc_id: '15249638961')
        end.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'error handling' do
      it 'propagates unknown errors raised by the client' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_by_docref)
          .and_raise(StandardError.new('Unknown fetch error'))

        expect do
          service.get_avs_binary_data(doc_id: '15249638961')
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end
  end
end
