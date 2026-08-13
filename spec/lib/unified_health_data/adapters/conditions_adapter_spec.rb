# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/conditions_adapter'

RSpec.describe UnifiedHealthData::Adapters::ConditionsAdapter, type: :service do
  let(:adapter) { UnifiedHealthData::Adapters::ConditionsAdapter.new }
  let(:conditions_sample_response) do
    JSON.parse(Rails.root.join(
      'spec', 'fixtures', 'unified_health_data', 'conditions_sample_response.json'
    ).read)
  end

  before do
    allow(UnifiedHealthData::Condition).to receive(:new).and_call_original
  end

  describe '#parse' do
    it 'returns the expected fields for vista condition with all fields' do
      vista_records = conditions_sample_response['vista']['entry']
      parsed_conditions = adapter.parse(vista_records)
      expect(parsed_conditions.size).to eq(16)

      expect(parsed_conditions).to all(have_attributes(
                                         id: be_a(String),
                                         name: be_a(String),
                                         date: be_a(String).or(be_nil),
                                         provider: be_a(String),
                                         facility: be_a(String),
                                         comments: be_an(Array)
                                       ))
    end

    it 'returns the expected fields for oracle-health condition with all fields' do
      oh_records = conditions_sample_response['oracle-health']['entry']
      parsed_conditions = adapter.parse(oh_records)

      expect(oh_records.size).to be > parsed_conditions.size
      expect(parsed_conditions.size).to eq(2)
      expect(parsed_conditions).to all(have_attributes(
                                         id: be_a(String),
                                         name: be_a(String),
                                         date: be_a(String).or(be_nil),
                                         provider: be_a(String),
                                         facility: be_a(String),
                                         comments: be_an(Array)
                                       ))
    end

    it 'returns the expected fields with VistA sample data' do
      vista_records = conditions_sample_response['vista']['entry']
      # First VistA condition with all fields
      parsed_condition = adapter.parse_single_condition(vista_records[3])

      expect(parsed_condition).to have_attributes(
        id: '6f5683ba-2ae8-4d8d-85ff-24babcfbabde',
        name: 'Carcinoma in situ of skin, unspecified',
        date: '2024-01-03T04:00:00Z',
        provider: 'MCGUIRE,MARCI P',
        facility: 'CHYSHR TEST LAB',
        comments: ['Carcinoma of right ear']
      )
    end

    it 'returns the expected fields with Oracle Health sample data' do
      oh_records = conditions_sample_response['oracle-health']['entry']
      parsed_condition = adapter.parse_single_condition(oh_records[1])

      expect(parsed_condition).to have_attributes(
        id: 'p1533314061',
        name: 'Disease caused by 2019-nCoV',
        date: '2025-01-20T19:29:02.000Z',
        provider: 'SYSTEM, SYSTEM Cerner, Cerner Managed Acct',
        facility: '0089C-AMC Womack-Liberty',
        comments: ['This problem was added by Discern Expert for positive COVID-19 lab test.']
      )
    end

    it 'handles empty records gracefully' do
      parsed_conditions = adapter.parse([])
      expect(parsed_conditions).to eq([])
    end
  end

  describe 'filtering by clinical status' do
    context 'with filtering enabled (default)' do
      it 'filters out conditions with non-active clinical status' do
        records = [
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '1',
              'onsetDateTime' => '2024-01-15',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'resolved' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Resolved Condition' }]
              }
            }
          }
        ]

        expect(adapter.parse(records)).to eq([])
      end

      it 'filters out conditions with missing clinical status' do
        records = [
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '1',
              'onsetDateTime' => '2024-01-15',
              'code' => {
                'coding' => [{ 'display' => 'Condition Without Status' }]
              }
              # Missing clinicalStatus
            }
          }
        ]

        expect(adapter.parse(records)).to eq([])
      end

      it 'includes conditions with active clinical status' do
        records = [
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '1',
              'onsetDateTime' => '2024-01-15',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'active' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Active Condition' }]
              }
            }
          }
        ]

        result = adapter.parse(records)
        expect(result.length).to eq(1)
        expect(result.first.name).to eq('Active Condition')
        expect(result.first.date).to eq('2024-01-15')
        expect(result.first.id).to eq('1')
      end

      it 'filters mixed active and inactive conditions' do
        records = [
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '1',
              'onsetDateTime' => '2024-01-15',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'active' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Active Condition' }]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '2',
              'onsetDateTime' => '2024-01-10',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'resolved' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Resolved Condition' }]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '3',
              'recordedDate' => '2024-01-20',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'active' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Another Active Condition' }]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '4',
              'onsetDateTime' => '2024-01-05',
              'code' => {
                'coding' => [{ 'display' => 'No Status Condition' }]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '5',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'active' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'No Date Condition' }]
              }
            }
          }
        ]

        result = adapter.parse(records)
        expect(result.length).to eq(3)
        expect(result.map(&:name)).to contain_exactly('Active Condition', 'Another Active Condition',
                                                      'No Date Condition')
      end
    end

    context 'with filtering disabled' do
      it 'includes conditions with any clinical status when filter_by_status is false' do
        records = [
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '1',
              'onsetDateTime' => '2024-01-15',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'resolved' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Resolved Condition' }]
              }
            }
          },
          {
            'resource' => {
              'resourceType' => 'Condition',
              'id' => '2',
              'onsetDateTime' => '2024-01-20',
              'clinicalStatus' => {
                'coding' => [{ 'code' => 'active' }]
              },
              'code' => {
                'coding' => [{ 'display' => 'Active Condition' }]
              }
            }
          }
        ]

        result = adapter.parse(records, filter_by_status: false)
        expect(result.length).to eq(2)
        expect(result.map(&:name)).to contain_exactly('Resolved Condition', 'Active Condition')
      end
    end

    context 'with parse_single_condition' do
      it 'returns nil for condition with inactive status' do
        record = {
          'resource' => {
            'resourceType' => 'Condition',
            'id' => '1',
            'onsetDateTime' => '2024-01-15',
            'clinicalStatus' => {
              'coding' => [{ 'code' => 'inactive' }]
            },
            'code' => {
              'coding' => [{ 'display' => 'Test' }]
            }
          }
        }

        expect(adapter.parse_single_condition(record)).to be_nil
      end

      it 'returns condition object for active condition' do
        record = {
          'resource' => {
            'resourceType' => 'Condition',
            'id' => '1',
            'onsetDateTime' => '2024-01-15',
            'clinicalStatus' => {
              'coding' => [{ 'code' => 'active' }]
            },
            'code' => {
              'coding' => [{ 'display' => 'Active Test' }]
            }
          }
        }

        result = adapter.parse_single_condition(record)
        expect(result).not_to be_nil
        expect(result.name).to eq('Active Test')
        expect(result.date).to eq('2024-01-15')
        expect(result.id).to eq('1')
      end

      it 'returns condition object regardless of clinical status when filter_by_status is false' do
        record = {
          'resource' => {
            'resourceType' => 'Condition',
            'id' => '1',
            'onsetDateTime' => '2024-01-15',
            'clinicalStatus' => {
              'coding' => [{ 'code' => 'resolved' }]
            },
            'code' => {
              'coding' => [{ 'display' => 'Resolved Test' }]
            }
          }
        }

        result = adapter.parse_single_condition(record, filter_by_status: false)
        expect(result).not_to be_nil
        expect(result.name).to eq('Resolved Test')
        expect(result.date).to eq('2024-01-15')
      end
    end
  end

  describe 'date extraction' do
    def build_condition(overrides = {})
      {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => '1',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'coding' => [{ 'display' => 'Active Condition' }] }
        }.merge(overrides)
      }
    end

    it 'prefers recordedDate when both recordedDate and onsetDateTime are present' do
      record = build_condition('recordedDate' => '2025-01-20T19:29:02.000Z',
                               'onsetDateTime' => '2025-01-20')

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2025-01-20T19:29:02.000Z')
    end

    it 'uses recordedDate when only recordedDate is present' do
      record = build_condition('recordedDate' => '2024-01-20')

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2024-01-20')
    end

    it 'falls back to onsetDateTime when recordedDate is missing' do
      record = build_condition('onsetDateTime' => '2024-01-15')

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2024-01-15')
    end

    it 'increments a StatsD metric when falling back to onsetDateTime' do
      record = build_condition('onsetDateTime' => '2024-01-15')

      expect(StatsD).to receive(:increment).with('unified_health_data.condition.replace_date_with_onset')
      adapter.parse_single_condition(record)
    end

    it 'does not increment the fallback metric when recordedDate is present' do
      record = build_condition('recordedDate' => '2024-01-20', 'onsetDateTime' => '2024-01-15')

      expect(StatsD).not_to receive(:increment).with('unified_health_data.condition.replace_date_with_onset')
      adapter.parse_single_condition(record)
    end

    it 'returns a nil date when neither recordedDate nor onsetDateTime is present' do
      record = build_condition

      result = adapter.parse_single_condition(record)
      expect(result.date).to be_nil
    end
  end

  describe 'filter diagnostic logging' do
    let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
    let(:adapter_with_user) { UnifiedHealthData::Adapters::ConditionsAdapter.new(user:) }

    let(:active_condition) do
      {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'active-cond',
          'onsetDateTime' => '2024-01-15',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'coding' => [{ 'display' => 'Active Condition' }] }
        }
      }
    end

    let(:resolved_condition) do
      {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'resolved-cond',
          'onsetDateTime' => '2024-01-10',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'resolved' }] },
          'code' => { 'coding' => [{ 'display' => 'Resolved Condition' }] }
        }
      }
    end

    let(:missing_status_condition) do
      {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'no-status-cond',
          'onsetDateTime' => '2024-01-05',
          'code' => { 'coding' => [{ 'display' => 'No Status Condition' }] }
        }
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_conditions_diagnostic, user)
        .and_return(true)
      allow(StatsD).to receive(:increment)
    end

    it 'logs diagnostic with inactive_clinical_status reason for resolved conditions' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'conditions',
          action: 'filter',
          record_id: 'resolved-cond',
          reason: 'inactive_clinical_status',
          log_level_context: 'diagnostic'
        )
      )

      adapter_with_user.parse([resolved_condition])
    end

    it 'logs diagnostic with missing_clinical_status reason for conditions without status' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'conditions',
          action: 'filter',
          record_id: 'no-status-cond',
          reason: 'missing_clinical_status',
          log_level_context: 'diagnostic'
        )
      )

      adapter_with_user.parse([missing_status_condition])
    end

    it 'increments StatsD counter with correct reason tag' do
      adapter_with_user.parse([resolved_condition, missing_status_condition])

      expect(StatsD).to have_received(:increment).with(
        'unified_health_data.condition.filtered_record',
        tags: ['reason:inactive_clinical_status']
      )
      expect(StatsD).to have_received(:increment).with(
        'unified_health_data.condition.filtered_record',
        tags: ['reason:missing_clinical_status']
      )
    end

    it 'does not log or increment for active conditions' do
      expect(Rails.logger).not_to receive(:info).with(
        hash_including(resource: 'conditions', action: 'filter')
      )
      expect(StatsD).not_to receive(:increment).with(
        'unified_health_data.condition.filtered_record', anything
      )

      adapter_with_user.parse([active_condition])
    end
  end

  describe 'facility_timezone' do
    let(:facility_service) { instance_double(UnifiedHealthData::FacilityService) }

    before do
      allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_service)
      allow(facility_service).to receive(:get_facility_timezone).and_return(nil)
    end

    it 'passes through year-only dates without conversion' do
      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-1',
          'onsetDateTime' => '2002',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' }
        }
      }

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2002')
      expect(result.facility_timezone).to be_nil
    end

    it 'passes through date-only dates without conversion' do
      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-2',
          'onsetDateTime' => '2025-11-25',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' }
        }
      }

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2025-11-25')
      expect(result.facility_timezone).to be_nil
    end

    it 'converts full datetime to facility time when station is found' do
      allow(facility_service).to receive(:get_facility_timezone)
        .with('989').and_return('America/Denver')

      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-3',
          'onsetDateTime' => '2024-01-03T04:00:00Z',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' },
          'contained' => [
            {
              'resourceType' => 'Location',
              'id' => 'location-983',
              'identifier' => [
                { 'use' => 'usual',
                  'system' => 'urn:oid:2.16.840.1.113883.4.349.4.989',
                  'value' => 'HospitalLocationTO.983' }
              ]
            }
          ]
        }
      }

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2024-01-02T21:00:00-07:00')
      expect(result.facility_timezone).to eq('America/Denver')
    end

    it 'returns original date when no contained resources exist' do
      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-4',
          'recordedDate' => '2025-12-10T17:39:48.000Z',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' }
        }
      }

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2025-12-10T17:39:48.000Z')
      expect(result.facility_timezone).to be_nil
    end

    it 'returns original date when station number cannot be resolved' do
      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-5',
          'recordedDate' => '2025-12-10T02:03:54.000Z',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' },
          'contained' => [
            { 'resourceType' => 'Practitioner', 'id' => 'prac-1' }
          ]
        }
      }

      result = adapter.parse_single_condition(record)
      expect(result.date).to eq('2025-12-10T02:03:54.000Z')
      expect(result.facility_timezone).to be_nil
    end

    it 'attributes timezone conversion errors to the conditions resource' do
      mr_log = instance_double(MedicalRecords::MedicalRecordsLog)
      allow(MedicalRecords::MedicalRecordsLog).to receive(:new).and_return(mr_log)
      allow(mr_log).to receive(:warn)
      allow(facility_service).to receive(:get_facility_timezone)
        .with('989').and_return('Invalid/Timezone')

      record = {
        'resource' => {
          'resourceType' => 'Condition',
          'id' => 'cond-6',
          'onsetDateTime' => '2024-01-03T04:00:00Z',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'Test condition' },
          'contained' => [
            {
              'resourceType' => 'Location',
              'id' => 'location-983',
              'identifier' => [
                { 'use' => 'usual',
                  'system' => 'urn:oid:2.16.840.1.113883.4.349.4.989',
                  'value' => 'HospitalLocationTO.983' }
              ]
            }
          ]
        }
      }

      UnifiedHealthData::Adapters::ConditionsAdapter.new.parse_single_condition(record)

      expect(mr_log).to have_received(:warn).with(
        hash_including(
          resource: MedicalRecords::MedicalRecordsLog::CONDITIONS,
          action: 'timezone_conversion'
        )
      )
    end
  end
end
