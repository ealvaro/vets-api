# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/imaging_study_adapter'
require 'unified_health_data/models/imaging_study'

RSpec.describe UnifiedHealthData::Adapters::ImagingStudyAdapter do
  subject(:adapter) { described_class.new }

  let(:imaging_study_response) do
    [
      {
        'resource' => {
          'resourceType' => 'ImagingStudy',
          'id' => 'imaging-study-123',
          'identifier' => [
            { 'use' => 'usual', 'value' => 'urn:oid:1.2.840.113619.2.123' }
          ],
          'status' => 'available',
          'modality' => [{ 'code' => 'CT' }],
          'started' => '2025-01-15T10:30:00Z',
          'reasonReference' => [
            {
              'reference' => 'DiagnosticReport/15249557843'
            }
          ],
          'description' => 'CT Scan of Chest',
          'subject' => { 'reference' => 'Patient/1234567890V012345' },
          'note' => [
            { 'text' => 'Routine follow-up scan' }
          ],
          'series' => [
            {
              'uid' => 'series-uid-1',
              'number' => 1,
              'modality' => { 'code' => 'CT' },
              'instance' => [
                { 'uid' => 'instance-1', 'number' => 1, 'title' => 'Image 1' },
                { 'uid' => 'instance-2', 'number' => 2, 'title' => 'Image 2' }
              ]
            },
            {
              'uid' => 'series-uid-2',
              'number' => 2,
              'modality' => { 'code' => 'CT' },
              'instance' => [
                { 'uid' => 'instance-3', 'number' => 1, 'title' => 'Image 3' }
              ]
            }
          ]
        }
      }
    ]
  end

  describe '#parse' do
    context 'with valid imaging study response' do
      it 'returns an array of ImagingStudy objects' do
        result = adapter.parse(imaging_study_response)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)
        expect(result.first).to be_a(UnifiedHealthData::ImagingStudy)
      end

      it 'extracts basic fields correctly' do
        result = adapter.parse(imaging_study_response).first

        expect(result.id).to eq('imaging-study-123')
        expect(result.event_id).to eq('15249557843')
        expect(result.status).to eq('available')
        expect(result.modality).to eq('CT')
        expect(result.date).to eq('2025-01-15T10:30:00Z')
        expect(result.description).to eq('CT Scan of Chest')
      end

      it 'extracts identifier correctly' do
        result = adapter.parse(imaging_study_response).first

        expect(result.identifier).to eq('urn:oid:1.2.840.113619.2.123')
      end

      it 'extracts patient_id from subject reference' do
        result = adapter.parse(imaging_study_response).first

        expect(result.patient_id).to eq('1234567890V012345')
      end

      it 'extracts notes correctly' do
        result = adapter.parse(imaging_study_response).first

        expect(result.notes).to eq(['Routine follow-up scan'])
      end

      it 'counts series correctly' do
        result = adapter.parse(imaging_study_response).first

        expect(result.series_count).to eq(2)
      end

      it 'counts total images across all series' do
        result = adapter.parse(imaging_study_response).first

        expect(result.image_count).to eq(3)
      end

      it 'uses numberOfSeries from resource when available' do
        response_with_counts = imaging_study_response.deep_dup
        response_with_counts.first['resource']['numberOfSeries'] = 5
        result = adapter.parse(response_with_counts).first

        expect(result.series_count).to eq(5)
      end

      it 'uses numberOfInstances from resource when available' do
        response_with_counts = imaging_study_response.deep_dup
        response_with_counts.first['resource']['numberOfInstances'] = 10
        result = adapter.parse(response_with_counts).first

        expect(result.image_count).to eq(10)
      end

      it 'parses series data' do
        result = adapter.parse(imaging_study_response).first

        expect(result.series).to be_an(Array)
        expect(result.series.length).to eq(2)
        expect(result.series.first[:uid]).to eq('series-uid-1')
        expect(result.series.first[:modality]).to eq('CT')
      end
    end

    context 'with presigned thumbnail URLs' do
      let(:response_with_thumbnails) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => 'study-with-thumbnails',
              'status' => 'available',
              'series' => [
                {
                  'number' => 1,
                  'modality' => { 'code' => 'CT' },
                  'instance' => [
                    {
                      'number' => 0,
                      'title' => 'JPEG',
                      'extension' => [
                        {
                          'url' => 'http://hl7.org/fhir/StructureDefinition/imagingstudy-instance-uid',
                          'valueString' => 'urn:vaimage:test-image-id'
                        },
                        {
                          'url' => 'http://va.gov/mhv/fhir/StructureDefinition/presigned-url',
                          'valueUrl' => 'https://test-bucket.s3.amazonaws.com/thumb.jpg?sig=abc123'
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        ]
      end

      it 'extracts the presigned thumbnail URL from instance extensions' do
        result = adapter.parse(response_with_thumbnails).first

        instance = result.series.first[:instances].first
        expect(instance[:thumbnail_url]).to eq('https://test-bucket.s3.amazonaws.com/thumb.jpg?sig=abc123')
        expect(instance[:image_id]).to eq('urn:vaimage:test-image-id')
      end

      it 'returns nil thumbnail_url when presigned-url extension is absent' do
        result = adapter.parse(imaging_study_response).first

        instance = result.series.first[:instances].first
        expect(instance[:thumbnail_url]).to be_nil
      end
    end

    context 'with study-level presigned DICOM zip URL' do
      let(:response_with_dicom_zip) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => 'study-with-dicom-zip',
              'status' => 'available',
              'extension' => [
                {
                  'url' => 'http://va.gov/mhv/fhir/StructureDefinition/presigned-url',
                  'valueUrl' => 'https://test-cvix-zips.s3.amazonaws.com/hashed-abc/hashed-def.zip?sig=xyz'
                },
                {
                  'url' => 'http://va.gov/mhv/fhir/StructureDefinition/dicom-zip-size-bytes',
                  'valueDecimal' => 5_646_813
                }
              ],
              'series' => []
            }
          }
        ]
      end

      it 'extracts the presigned DICOM zip URL from study-level extensions' do
        result = adapter.parse(response_with_dicom_zip).first

        expect(result.dicom_zip_url).to eq('https://test-cvix-zips.s3.amazonaws.com/hashed-abc/hashed-def.zip?sig=xyz')
      end

      it 'extracts dicom_size_bytes from study-level extensions' do
        result = adapter.parse(response_with_dicom_zip).first

        expect(result.dicom_size_bytes).to eq(5_646_813)
      end

      it 'returns nil dicom_zip_url when study-level extension is absent' do
        result = adapter.parse(imaging_study_response).first

        expect(result.dicom_zip_url).to be_nil
      end

      it 'returns nil dicom_size_bytes when study-level extension is absent' do
        result = adapter.parse(imaging_study_response).first

        expect(result.dicom_size_bytes).to be_nil
      end
    end

    context 'with Task resource for DICOM progress' do
      let(:response_with_task) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => '13',
              'status' => 'available',
              'series' => []
            }
          },
          {
            'resource' => {
              'resourceType' => 'Task',
              'id' => '4',
              'extension' => [
                {
                  'url' => 'http://va.gov/mhv/fhir/StructureDefinition/imagingstudy-dicom-zip-progress-completed-count',
                  'valueInteger' => 2
                },
                {
                  'url' => 'http://va.gov/mhv/fhir/StructureDefinition/imagingstudy-dicom-zip-progress-total-count',
                  'valueInteger' => 5
                },
                {
                  'url' => 'http://va.gov/mhv/fhir/StructureDefinition/imagingstudy-dicom-zip-progress-phase',
                  'valueString' => 'fetching'
                }
              ],
              'status' => 'in-progress',
              'focus' => { 'reference' => 'ImagingStudy/13' }
            }
          }
        ]
      end

      it 'applies Task progress fields to the matching ImagingStudy' do
        result = adapter.parse(response_with_task).first

        expect(result.dicom_status).to eq('in-progress')
        expect(result.dicom_progress_phase).to eq('fetching')
        expect(result.dicom_progress_completed_count).to eq(2)
        expect(result.dicom_progress_total_count).to eq(5)
      end

      it 'leaves progress fields nil when no Task is present' do
        result = adapter.parse(imaging_study_response).first

        expect(result.dicom_status).to be_nil
        expect(result.dicom_progress_phase).to be_nil
        expect(result.dicom_progress_completed_count).to be_nil
        expect(result.dicom_progress_total_count).to be_nil
      end

      it 'ignores a Task whose focus does not match any ImagingStudy' do
        unmatched = [
          { 'resource' => { 'resourceType' => 'ImagingStudy', 'id' => '13', 'status' => 'available', 'series' => [] } },
          {
            'resource' => {
              'resourceType' => 'Task', 'id' => '99', 'status' => 'in-progress',
              'extension' => [
                { 'url' => 'http://va.gov/mhv/fhir/StructureDefinition/imagingstudy-dicom-zip-progress-phase',
                  'valueString' => 'fetching' }
              ],
              'focus' => { 'reference' => 'ImagingStudy/999' }
            }
          }
        ]
        result = adapter.parse(unmatched).first

        expect(result.dicom_status).to be_nil
        expect(result.dicom_progress_phase).to be_nil
      end

      it 'ignores a Task with no focus field' do
        no_focus = [
          { 'resource' => { 'resourceType' => 'ImagingStudy', 'id' => '13', 'status' => 'available', 'series' => [] } },
          {
            'resource' => {
              'resourceType' => 'Task', 'id' => '99', 'status' => 'completed',
              'extension' => [
                { 'url' => 'http://va.gov/mhv/fhir/StructureDefinition/imagingstudy-dicom-zip-progress-phase',
                  'valueString' => 'completed' }
              ]
            }
          }
        ]
        result = adapter.parse(no_focus).first

        expect(result.dicom_status).to be_nil
        expect(result.dicom_progress_phase).to be_nil
      end

      it 'returns nil for missing Task extensions while preserving Task status' do
        sparse_task = [
          { 'resource' => { 'resourceType' => 'ImagingStudy', 'id' => '13', 'status' => 'available', 'series' => [] } },
          {
            'resource' => {
              'resourceType' => 'Task', 'id' => '4', 'status' => 'in-progress',
              'extension' => [],
              'focus' => { 'reference' => 'ImagingStudy/13' }
            }
          }
        ]
        result = adapter.parse(sparse_task).first

        expect(result.dicom_status).to eq('in-progress')
        expect(result.dicom_progress_phase).to be_nil
        expect(result.dicom_progress_completed_count).to be_nil
        expect(result.dicom_progress_total_count).to be_nil
      end
    end

    context 'with empty input' do
      it 'returns empty array for nil' do
        expect(adapter.parse(nil)).to eq([])
      end

      it 'returns empty array for empty array' do
        expect(adapter.parse([])).to eq([])
      end
    end

    context 'with non-ImagingStudy resources' do
      let(:mixed_response) do
        [
          { 'resource' => { 'resourceType' => 'ImagingStudy', 'id' => '123', 'status' => 'available' } },
          { 'resource' => { 'resourceType' => 'Patient', 'id' => '456' } },
          { 'resource' => { 'resourceType' => 'OperationOutcome', 'id' => '789' } }
        ]
      end

      it 'filters out non-ImagingStudy resources' do
        result = adapter.parse(mixed_response)

        expect(result.length).to eq(1)
        expect(result.first.id).to eq('123')
      end
    end

    context 'with missing optional fields' do
      let(:minimal_response) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => 'minimal-study',
              'status' => 'available'
            }
          }
        ]
      end

      it 'handles missing fields gracefully' do
        result = adapter.parse(minimal_response).first

        expect(result.id).to eq('minimal-study')
        expect(result.event_id).to be_nil
        expect(result.identifier).to be_nil
        expect(result.modality).to be_nil
        expect(result.date).to be_nil
        expect(result.description).to be_nil
        expect(result.notes).to eq([])
        expect(result.patient_id).to be_nil
        expect(result.series_count).to eq(0)
        expect(result.image_count).to eq(0)
        expect(result.series).to eq([])
      end
    end

    context 'with reasonReference (event_id extraction)' do
      let(:response_without_reason_reference) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => 'study-with-event',
              'status' => 'available',
              'series' => []
            }
          }
        ]
      end

      it 'returns nil event_id when reasonReference is absent' do
        result = adapter.parse(response_without_reason_reference).first

        expect(result.event_id).to be_nil
      end
    end

    context 'with modality fallback' do
      let(:series_modality_response) do
        [
          {
            'resource' => {
              'resourceType' => 'ImagingStudy',
              'id' => 'fallback-study',
              'status' => 'available',
              'series' => [
                { 'modality' => { 'code' => 'MR' } }
              ]
            }
          }
        ]
      end

      it 'falls back to first series modality when study-level modality is absent' do
        result = adapter.parse(series_modality_response).first

        expect(result.modality).to eq('MR')
      end
    end
  end

  describe '#parse_single_study' do
    it 'returns nil for nil resource' do
      expect(adapter.parse_single_study(nil)).to be_nil
    end

    it 'returns nil for non-ImagingStudy resource' do
      resource = { 'resourceType' => 'Patient', 'id' => '123' }
      expect(adapter.parse_single_study(resource)).to be_nil
    end
  end
end
