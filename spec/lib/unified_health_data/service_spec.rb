# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::Service, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class }

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  before do
    # Disable V2 status mapping globally for all tests since the feature is not yet enabled
    allow(Flipper).to receive(:enabled?).with(:mhv_medications_v2_status_mapping, anything).and_return(false)
  end

  describe '#get_labs' do
    let(:labs_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'labs_response.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: labs_sample_response
      )
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_labs_by_date)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns all labs/tests with encodedData and/or observations' do
          result = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
          labs = result[:records]
          # 21 total DiagnosticReport entries (12 VistA + 9 OH); 3 filtered out
          # (1 VistA with nil status, 1 OH with nil status, 1 OH with status "partial") = 18 parsed
          expect(labs.size).to eq(18)

          labs_with_encoded_data = labs.select { |lab| lab.encoded_data.present? }
          expect(labs_with_encoded_data).not_to be_empty

          labs_with_observations = labs.select { |lab| lab.observations.present? }
          expect(labs_with_observations).not_to be_empty
        end

        it 'returns labs sorted by date_completed in descending order' do
          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records].sort

          labs_with_dates = labs.select { |lab| lab.date_completed.present? }
          dates = labs_with_dates.map(&:sort_date)
          expect(dates).to eq(dates.sort.reverse)

          labs_without_dates = labs.select { |lab| lab.date_completed.nil? }
          expect(labs.last(labs_without_dates.size)).to eq(labs_without_dates) if labs_without_dates.any?
        end

        it 'returns specific VistA lab with expected attributes' do
          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

          chem_lab = labs.find { |lab| lab.id == 'df64e7c7-d354-43a1-ab57-445844b59b52' }
          expect(chem_lab).to have_attributes(
            'id' => 'df64e7c7-d354-43a1-ab57-445844b59b52',
            'display' => 'CHEM 7',
            'test_code' => 'CH',
            'date_completed' => '2025-01-23T22:01:52+00:00',
            'location' => 'CHYSHR TEST LAB',
            'source' => 'vista',
            'status' => 'final'
          )
          expect(chem_lab.comments).to be_an(Array)
          expect(chem_lab.comments.any? { |c| c.include?('TEST COMMENT') }).to be true
          expect(chem_lab.observations.size).to eq(7)
        end

        it 'returns specific Oracle Health lab with expected attributes' do
          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

          oh_lab = labs.find { |lab| lab.id == '15248982124' }
          oh_lab_with_note = labs.find { |lab| lab.id == 'a21b3621-4f42-4504-b41c-6598c8537212' }

          expect(oh_lab).to have_attributes(
            'id' => '15248982124',
            'display' => 'Blood Culture',
            'test_code' => 'MB',
            'date_completed' => '2025-03-13T17:28:00Z',
            'source' => 'oracle-health',
            'status' => 'final',
            'comments' => nil
          )
          expect(oh_lab.observations.size).to eq(2)

          expect(oh_lab_with_note).to have_attributes(
            'id' => 'a21b3621-4f42-4504-b41c-6598c8537212',
            'display' => 'CH',
            'test_code' => 'CH',
            'date_completed' => '2025-12-10T01:25:00+00:00',
            'source' => 'oracle-health',
            'status' => 'final',
            'comments' => ['Comment on the ORDER (not on the result) for testing']
          )
          expect(oh_lab_with_note.observations.size).to eq(1)
        end

        it 'returns labs with expected attribute types' do
          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

          expect(labs).to all(have_attributes(
                                'id' => be_a(String),
                                'type' => be_a(String),
                                'display' => be_a(String),
                                'test_code' => be_a(String),
                                'test_code_display' => be_a(String).or(be_nil),
                                'date_completed' => be_a(String).or(be_nil),
                                'sort_date' => be_a(String).or(be_nil),
                                'sample_tested' => be_a(String).or(be_nil),
                                'encoded_data' => be_a(String).or(be_nil),
                                'location' => be_a(String).or(be_nil),
                                'ordered_by' => be_a(String).or(be_nil),
                                'body_site' => be_a(String).or(be_nil),
                                'comments' => be_an(Array).or(be_nil),
                                'status' => be_a(String),
                                'source' => be_a(String),
                                'facility_timezone' => be_a(String).or(be_nil),
                                'observations' => be_an(Array)
                              ))
        end
      end

      context 'when data exists for only VistA or OH' do
        it 'returns labs for VistA only' do
          modified_response = labs_sample_response.deep_dup
          modified_response['oracle-health'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_labs_by_date)
            .and_return(Faraday::Response.new(body: modified_response))

          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]
          # 12 VistA records, 1 filtered (nil status) = 11 parsed
          expect(labs.size).to eq(11)
          expect(labs.map(&:source)).to all(eq('vista'))
        end

        it 'returns labs for OH only' do
          modified_response = labs_sample_response.deep_dup
          modified_response['vista'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_labs_by_date)
            .and_return(Faraday::Response.new(body: modified_response))

          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]
          # 9 OH records, 2 filtered (nil status and status "partial") = 7 parsed
          expect(labs.size).to eq(7)
          expect(labs.map(&:source)).to all(eq('oracle-health'))
        end
      end

      context 'when there are no records in VistA or OH' do
        it 'returns empty array' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_labs_by_date)
            .and_return(Faraday::Response.new(body: { 'vista' => {}, 'oracle-health' => {} }))

          labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]
          expect(labs.size).to eq(0)
        end
      end
    end

    it 'returns labs with only encodedData' do
      labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

      labs_with_encoded_only = labs.select { |lab| lab.encoded_data.present? && lab.observations.blank? }
      expect(labs_with_encoded_only).not_to be_empty
    end

    it 'returns labs with only observations' do
      labs = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

      labs_with_observations_only = labs.select { |lab| lab.observations.present? && lab.encoded_data.blank? }
      expect(labs_with_observations_only).not_to be_empty
    end

    it 'logs test code distribution from parsed records' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_labs_and_tests_diagnostic, user)
        .and_return(true)

      service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'labs_and_tests',
          action: 'test_code_distribution',
          log_level_context: 'diagnostic'
        )
      )
    end

    context 'with malformed response' do
      it 'handles gracefully' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .and_return(Faraday::Response.new(body: nil))

        expect { service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31') }.not_to raise_error
      end
    end

    context 'warning propagation' do
      it 'returns warnings when _warnings are present in the response body' do
        response_with_warnings = labs_sample_response.deep_dup
        response_with_warnings['_warnings'] = [
          { source: 'oracle-health', code: 'not-found', diagnostics: 'Binary/abc123 not found', severity: 'warning' }
        ]
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .and_return(Faraday::Response.new(body: response_with_warnings))

        result = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
        expect(result[:warnings]).to eq(
          [{ source: 'oracle-health', code: 'not-found', diagnostics: 'Binary/abc123 not found', severity: 'warning' }]
        )
        expect(result[:records]).to be_an(Array)
        expect(result[:records]).not_to be_empty
      end

      it 'returns empty warnings when no _warnings in response body' do
        result = service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
        expect(result[:warnings]).to eq([])
      end
    end

    context 'when uhd_client raises a service error' do
      let(:error) { Faraday::TimeoutError.new('connection timed out') }

      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .and_raise(error)
        allow(Rails.logger).to receive(:error)
        allow(StatsD).to receive(:increment)
      end

      it 'logs the error with domain context and re-raises' do
        expect do
          service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
        end.to raise_error(Faraday::TimeoutError)

        expect(Rails.logger).to have_received(:error).with(
          hash_including(
            service: 'medical_records',
            resource: 'labs_and_tests',
            action: 'index',
            error_class: 'Faraday::TimeoutError',
            error_message: 'connection timed out'
          )
        )
      end

      it 'increments the error StatsD counter' do
        expect do
          service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
        end.to raise_error(Faraday::TimeoutError)

        expect(StatsD).to have_received(:increment)
          .with('api.uhd.labs_and_tests.error', tags: [])
      end
    end
  end

  describe '#fetch_combined_records' do
    context 'when body is nil' do
      it 'returns an empty array' do
        result = service.send(:fetch_combined_records, nil)

        expect(result).to eq([])
      end
    end

    context 'when body has VistA and Oracle Health records' do
      let(:body) do
        {
          'vista' => {
            'entry' => [
              { 'resource' => { 'id' => 'vista-1', 'resourceType' => 'DiagnosticReport' } }
            ]
          },
          'oracle-health' => {
            'entry' => [
              { 'resource' => { 'id' => 'oracle-1', 'resourceType' => 'DiagnosticReport' } }
            ]
          }
        }
      end

      it 'adds source to each record and combines them' do
        result = service.send(:fetch_combined_records, body)
        expect(result.size).to eq(2)
        vista_record = result.find { |r| r['resource']['id'] == 'vista-1' }
        oracle_record = result.find { |r| r['resource']['id'] == 'oracle-1' }
        expect(vista_record['source']).to eq('vista')
        expect(oracle_record['source']).to eq('oracle-health')
      end
    end
  end

  # Allergies
  describe '#get_allergies' do
    let(:allergies_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'allergies_example.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: allergies_sample_response
      )
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns all allergies' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_allergies_by_date)
            .and_return(sample_client_response)

          allergies = service.get_allergies[:records]
          # 13 total AllergyIntolerance resources, only 10 have active clinicalStatus
          expect(allergies.size).to eq(10)
          expect(allergies.map(&:categories)).to contain_exactly(
            ['medication'],
            ['medication'],
            ['medication'],
            ['medication'],
            ['medication'],
            ['medication'],
            ['medication'],
            ['food'],
            [],
            ['food']
          )
          # Verify specific allergy exists (not checking position due to sorting)
          trazodone_allergy = allergies.find { |a| a.id == '2678' }
          expect(trazodone_allergy).to have_attributes(
            {
              'id' => '2678',
              'name' => 'TRAZODONE',
              'date' => nil,
              'categories' => ['medication'],
              'reactions' => [],
              'location' => nil,
              'observedHistoric' => 'h',
              'notes' => [],
              'provider' => nil
            }
          )
          expect(allergies).to all(have_attributes(
                                     {
                                       'id' => be_a(String),
                                       'name' => be_a(String),
                                       'date' => be_a(String).or(be_nil),
                                       'categories' => be_an(Array),
                                       'reactions' => be_an(Array),
                                       'location' => be_a(String).or(be_nil),
                                       'observedHistoric' => be_a(String).or(be_nil),
                                       'notes' => be_an(Array),
                                       'provider' => be_a(String).or(be_nil)
                                     }
                                   ))
        end

        it 'returns allergies sorted by date in descending order' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_allergies_by_date)
            .and_return(sample_client_response)

          allergies = service.get_allergies[:records].sort

          allergies_with_dates = allergies.select { |allergy| allergy.date.present? }
          # Use sort_date for comparison since that's what's used for sorting
          dates = allergies_with_dates.map(&:sort_date)
          expect(dates).to eq(dates.sort.reverse)

          allergies_without_dates = allergies.select { |allergy| allergy.date.nil? }
          if allergies_without_dates.any?
            expect(allergies.last(allergies_without_dates.size)).to eq(allergies_without_dates)
          end
        end
      end

      context 'when data exists for only VistA or OH' do
        it 'returns allergies for VistA only' do
          modified_response = allergies_sample_response.deep_dup
          modified_response['oracle-health'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_allergies_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          allergies = service.get_allergies[:records]
          # 5 AllergyIntolerance resources, only 4 have active clinicalStatus
          expect(allergies.size).to eq(4)
          expect(allergies.map(&:categories)).to contain_exactly(
            ['medication'],
            ['medication'],
            ['medication'],
            ['medication']
          )
          expect(allergies).to all(have_attributes(
                                     {
                                       'id' => be_a(String),
                                       'name' => be_a(String),
                                       'date' => be_a(String).or(be_nil),
                                       'categories' => be_an(Array),
                                       'reactions' => be_an(Array),
                                       'location' => be_a(String).or(be_nil),
                                       'observedHistoric' => be_a(String).or(be_nil),
                                       'notes' => be_an(Array),
                                       'provider' => be_a(String).or(be_nil)
                                     }
                                   ))
        end

        it 'returns allergies for OH only' do
          modified_response = allergies_sample_response.deep_dup
          modified_response['vista'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_allergies_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          allergies = service.get_allergies[:records]
          # 8 AllergyIntolerance resources, only 6 have active clinicalStatus
          expect(allergies.size).to eq(6)
          expect(allergies.map(&:categories)).to contain_exactly(
            ['medication'],
            ['medication'],
            ['medication'],
            ['food'],
            [],
            ['food']
          )
          expect(allergies).to all(have_attributes(
                                     {
                                       'id' => be_a(String),
                                       'name' => be_a(String),
                                       'date' => be_a(String).or(be_nil),
                                       'categories' => be_an(Array),
                                       'reactions' => be_an(Array),
                                       'location' => be_a(String).or(be_nil),
                                       'observedHistoric' => be_nil, # OH data doesn't include this field
                                       'notes' => be_an(Array),
                                       'provider' => be_a(String).or(be_nil)
                                     }
                                   ))
        end
      end

      context 'when there are no records in VistA or OH' do
        it 'returns empty array allergies' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_allergies_by_date)
            .and_return(Faraday::Response.new(
                          body: { 'vista' => {}, 'oracle-health' => {} }
                        ))
          allergies = service.get_allergies[:records]
          expect(allergies.size).to eq(0)
        end
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_allergies).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_allergies
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'logging and metrics' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_allergies_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_allergies_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'calls log_allergies_metrics when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_allergies_diagnostic, user)
          .and_return(true)

        service.get_allergies

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'allergies',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        ).at_least(:once)
      end

      it 'emits StatsD gauges for allergies index' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_allergies_diagnostic, user)
          .and_return(true)

        service.get_allergies

        expect(StatsD).to have_received(:gauge).with('api.uhd.allergies.index.total', anything)
      end

      it 'does not log diagnostic when flipper disabled' do
        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(resource: 'allergies', action: 'filter'))
        service.get_allergies
      end
    end
  end

  describe '#get_single_allergy' do
    let(:allergies_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'allergies_example.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: allergies_sample_response
      )
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_allergies_by_date)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns a single VistA allergy' do
          allergy = service.get_single_allergy('2679')
          expect(allergy).to have_attributes(
            {
              'id' => '2679',
              'name' => 'MAXZIDE',
              'date' => nil,
              'categories' => ['medication'],
              'reactions' => [],
              'location' => nil,
              'observedHistoric' => 'h',
              'notes' => [],
              'provider' => nil
            }
          )
        end

        it 'returns a single OH allergy' do
          allergy = service.get_single_allergy('132316417')
          expect(allergy).to have_attributes(
            {
              'id' => '132316417',
              'name' => 'Oxymorphone',
              'date' => '2019',
              'categories' => ['medication'],
              'reactions' => ['Anaphylaxis'],
              'location' => nil,
              'observedHistoric' => nil,
              'notes' => ['Testing Contraindication type reaction', 'Secondary comment for contraindication'],
              'provider' => ' Victoria A Borland'
            }
          )
        end
      end
    end

    context 'when allergy is not found' do
      it 'returns nil when no matching allergy exists' do
        allergy = service.get_single_allergy('nonexistent-allergy-id')
        expect(allergy).to be_nil
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_single_allergy).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_single_allergy('banana')
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end
  end

  # Vitals
  describe '#get_vitals' do
    let(:vitals_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'vitals_example.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: vitals_sample_response
      )
    end

    before do
      allow(Rails.logger).to receive(:info)
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns all vitals' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_vitals_by_date)
            .and_return(sample_client_response)

          expect(Rails.logger).to receive(:info)
            .with(
              message: 'Multiple locations found for 8 Vital records:',
              locations: [{ 'locations found' => 2,
                            'names' => '668 Green Primary Care; WAMC Bariatric Surgery' }],
              service: 'unified_health_data'
            )

          vitals = service.get_vitals[:records]
          expect(vitals.size).to eq(18)
          expect(vitals.map(&:type)).to contain_exactly(
            'WEIGHT',
            'WEIGHT',
            'HEIGHT',
            'PULSE',
            'TEMPERATURE',
            'BLOOD_PRESSURE',
            'PULSE_OXIMETRY',
            'RESPIRATION',
            'WEIGHT',
            'BLOOD_PRESSURE',
            'PULSE_OXIMETRY',
            'WEIGHT',
            'TEMPERATURE',
            'RESPIRATION',
            'PULSE',
            'BLOOD_PRESSURE',
            'HEIGHT',
            'WEIGHT'
          )

          # this will be a VistA record
          expect(vitals[0]).to have_attributes(
            {
              'id' => 'be3724c0-f9e2-4e6a-b37e-366aca305613',
              'name' => 'Weight',
              'type' => 'WEIGHT',
              'date' => '2025-08-22T22:16:24Z',
              'measurement' => '165.35 pounds',
              'location' => 'CHY ANOTHER TEST CLINIC',
              'notes' => []
            }
          )

          oh_vital = vitals.find { |vital| vital.id == 'VS-15249708684' }
          expect(oh_vital).to have_attributes(
            {
              'id' => 'VS-15249708684',
              'name' => 'Weight dosing',
              'type' => 'WEIGHT',
              'date' => '2025-07-24T18:23:00.000Z',
              'measurement' => '150.796 pounds',
              'location' => '668 Green Primary Care',
              'notes' => ['Result generated by automated process based on measured weight.']
            }
          )
          expect(vitals).to all(have_attributes(
                                  {
                                    'id' => be_a(String),
                                    'name' => be_a(String),
                                    'date' => be_a(String).or(be_nil),
                                    'type' => be_a(String),
                                    'measurement' => be_a(String),
                                    'location' => be_a(String),
                                    'notes' => be_an(Array)
                                  }
                                ))
        end

        it 'returns vitals sorted by date in descending order' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_vitals_by_date)
            .and_return(sample_client_response)

          vitals = service.get_vitals[:records].sort

          vitals_with_dates = vitals.select { |v| v.date.present? }
          # Use sort_date for comparison since that's what's used for sorting
          dates = vitals_with_dates.map(&:sort_date)
          expect(dates).to eq(dates.sort.reverse)

          vitals_without_dates = vitals.select { |v| v.date.nil? }
          expect(vitals.last(vitals_without_dates.size)).to eq(vitals_without_dates) if vitals_without_dates.any?
        end
      end

      context 'when data exists for only VistA or OH' do
        it 'returns vitals for VistA only' do
          modified_response = vitals_sample_response.deep_dup
          modified_response['oracle-health'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_vitals_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          vitals = service.get_vitals[:records]
          expect(vitals.size).to eq(10)
          expect(vitals.map(&:type)).to contain_exactly(
            'WEIGHT',
            'WEIGHT',
            'HEIGHT',
            'PULSE',
            'TEMPERATURE',
            'BLOOD_PRESSURE',
            'PULSE_OXIMETRY',
            'RESPIRATION',
            'WEIGHT',
            'BLOOD_PRESSURE'
          )

          expect(vitals).to all(have_attributes(
                                  {
                                    'id' => be_a(String),
                                    'name' => be_a(String),
                                    'date' => be_a(String).or(be_nil),
                                    'type' => be_a(String),
                                    'measurement' => be_a(String),
                                    'location' => be_a(String),
                                    'notes' => be_an(Array)
                                  }
                                ))
        end

        it 'returns vitals for OH only' do
          modified_response = vitals_sample_response.deep_dup
          modified_response['vista'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_vitals_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          vitals = service.get_vitals[:records]
          expect(vitals.size).to eq(8)
          expect(vitals.map(&:type)).to contain_exactly(
            'PULSE_OXIMETRY',
            'WEIGHT',
            'TEMPERATURE',
            'RESPIRATION',
            'PULSE',
            'BLOOD_PRESSURE',
            'HEIGHT',
            'WEIGHT'
          )
          expect(vitals).to all(have_attributes(
                                  {
                                    'id' => be_a(String),
                                    'name' => be_a(String),
                                    'date' => be_a(String).or(be_nil),
                                    'type' => be_a(String),
                                    'measurement' => be_a(String),
                                    'location' => be_a(String),
                                    'notes' => be_an(Array)
                                  }
                                ))
        end
      end

      context 'when there are no records in VistA or OH' do
        it 'returns empty array for vitals' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_vitals_by_date)
            .and_return(Faraday::Response.new(
                          body: { 'vista' => {}, 'oracle-health' => {} }
                        ))
          vitals = service.get_vitals[:records]
          expect(vitals.size).to eq(0)
        end
      end
    end

    context 'error handling' do
      it 'propagates unexpected upstream errors' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_vitals_by_date)
          .and_raise(StandardError, 'Unknown fetch error')

        expect do
          service.get_vitals
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'logging and metrics' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_vitals_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vitals_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'calls log_vitals_metrics when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vitals_diagnostic, user)
          .and_return(true)

        service.get_vitals

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'vitals',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'emits StatsD gauges for vitals index' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vitals_diagnostic, user)
          .and_return(true)

        service.get_vitals

        expect(StatsD).to have_received(:gauge).with('api.uhd.vitals.index.total', anything)
      end

      it 'does not log diagnostic when flipper disabled' do
        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(resource: 'vitals', action: 'filter'))
        service.get_vitals
      end
    end
  end

  # Clinical Notes
  describe '#get_care_summaries_and_notes' do
    let(:notes_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'notes_sample_response.json'
      ).read)
    end

    let(:notes_no_vista_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'notes_empty_vista_response.json'
      ).read)
    end

    let(:notes_no_oh_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'notes_empty_oh_response.json'
      ).read)
    end

    let(:notes_empty_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'notes_empty_response.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: notes_sample_response
      )
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:gauge)
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_notes_by_date)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns care summaries and notes' do
          notes = service.get_care_summaries_and_notes[:records]
          expect(notes.size).to eq(7)
          expect(notes.map(&:note_type)).to contain_exactly(
            'physician_procedure_note',
            'physician_procedure_note',
            'physician_procedure_note',
            'consult_result',
            'physician_procedure_note',
            'discharge_summary',
            'other'
          )
          # Verify specific non-addendum note and validate notes entry metadata
          telehealth_note = notes.find { |n| n.id == 'F253-7227761-1834074' }
          expect(telehealth_note).to have_attributes(
            {
              'id' => 'F253-7227761-1834074',
              'name' => 'CARE COORDINATION HOME TELEHEALTH DISCHARGE NOTE',
              'loinc_codes' => ['11506-3'],
              'note_type' => 'physician_procedure_note',
              'date' => '2025-01-14T09:18:00.000+00:00',
              'date_signed' => '2025-01-14T09:29:26+00:00',
              'written_by' => 'MARCI P MCGUIRE',
              'signed_by' => 'MARCI P MCGUIRE',
              'admission_date' => nil,
              'discharge_date' => nil,
              'location' => 'CHYSHR TEST LAB',
              'note' => /VGhpcyBpcyBhIHRlc3QgdGVsZWhlYWx0aCBka/i,
              'addenda' => nil
            }
          )

          # Verify all notes have proper structure
          expect(notes).to all(have_attributes(
                                 {
                                   'id' => be_a(String),
                                   'name' => be_a(String),
                                   'note_type' => be_a(String),
                                   'loinc_codes' => be_an(Array),
                                   'date' => be_a(String),
                                   'date_signed' => be_a(String).or(be_nil),
                                   'written_by' => be_a(String).or(be_nil),
                                   'signed_by' => be_a(String).or(be_nil),
                                   'admission_date' => be_a(String).or(be_nil),
                                   'discharge_date' => be_a(String).or(be_nil),
                                   'location' => be_a(String).or(be_nil),
                                   'note' => be_a(String)
                                 }
                               ))
          # Every addenda entry across addendum records includes the required metadata keys
          notes.select { |record| record.addenda.present? }.each do |record|
            record.addenda.each do |addenda_entry|
              expect(addenda_entry).to include(
                :date, :date_signed, :written_by, :signed_by, :note
              )
              expect(addenda_entry[:note]).to be_a(String)
            end
          end
        end

        it 'returns addendum notes with addendum entry and original content on top-level note' do
          notes = service.get_care_summaries_and_notes[:records]
          # VistA entry[1] is an addendum (relatesTo appends) remapped to F253-7227761-1833586
          addendum_note = notes.find { |n| n.id == 'F253-7227761-1833586' }
          expect(addendum_note).not_to be_nil

          # Only the addendum itself appears in the addenda array (not the original)
          expect(addendum_note.addenda.size).to eq(1)

          addendum_entry = addendum_note.addenda.first
          expect(addendum_entry).to include(:note)
          expect(addendum_entry[:note]).to be_a(String)

          # Top-level note field contains the original note content, not the addendum
          expect(addendum_note.note).to be_a(String)
          expect(addendum_note.note).not_to eq(addendum_entry[:note])
        end

        it 'returns clinical notes sorted by date in descending order' do
          notes = service.get_care_summaries_and_notes[:records].sort

          dates = notes.map { |note| Time.zone.parse(note.date) }
          expect(dates).to eq(dates.sort.reverse)
          expect(notes.first.date).to eq(notes.map(&:date).max)
        end
      end

      context 'when data exists for only VistA or OH' do
        it 'returns care summaries and notes for VistA only' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_notes_by_date)
            .and_return(Faraday::Response.new(
                          body: notes_no_oh_response
                        ))
          notes = service.get_care_summaries_and_notes[:records]
          expect(notes.size).to eq(4)
          expect(notes.map(&:note_type)).to contain_exactly(
            'physician_procedure_note',
            'physician_procedure_note',
            'consult_result',
            'physician_procedure_note'
          )
          expect(notes).to all(have_attributes(
                                 {
                                   'id' => be_a(String),
                                   'name' => be_a(String),
                                   'note_type' => be_a(String),
                                   'loinc_codes' => be_an(Array),
                                   'date' => be_a(String),
                                   'date_signed' => be_a(String).or(be_nil),
                                   'written_by' => be_a(String).or(be_nil),
                                   'signed_by' => be_a(String).or(be_nil),
                                   'admission_date' => be_a(String).or(be_nil),
                                   'discharge_date' => be_a(String).or(be_nil),
                                   'location' => be_a(String).or(be_nil),
                                   'note' => be_a(String)
                                 }
                               ))
          # Validate each addenda entry includes the required metadata keys
          notes.select { |record| record.addenda.present? }.each do |record|
            expect(record.addenda).to all(include(:note))
          end
        end

        it 'returns care summaries and notes for OH only' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_notes_by_date)
            .and_return(Faraday::Response.new(
                          body: notes_no_vista_response
                        ))
          notes = service.get_care_summaries_and_notes[:records]
          expect(notes.size).to eq(2)
          expect(notes.map(&:note_type)).to contain_exactly(
            'discharge_summary',
            'other'
          )
          expect(notes).to all(have_attributes(
                                 {
                                   'id' => be_a(String),
                                   'name' => be_a(String),
                                   'note_type' => be_a(String),
                                   'loinc_codes' => be_an(Array),
                                   'date' => be_a(String),
                                   'date_signed' => be_a(String).or(be_nil),
                                   'written_by' => be_a(String).or(be_nil),
                                   'signed_by' => be_a(String).or(be_nil),
                                   'admission_date' => be_a(String).or(be_nil),
                                   'discharge_date' => be_a(String).or(be_nil),
                                   'location' => be_a(String).or(be_nil),
                                   'note' => be_a(String)
                                 }
                               ))
          # Validate each addenda entry includes the required metadata keys
          notes.select { |record| record.addenda.present? }.each do |record|
            expect(record.addenda).to all(include(:note))
          end
        end
      end

      context 'when there are no records in VistA or OH' do
        it 'returns care summaries and notes' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_notes_by_date)
            .and_return(Faraday::Response.new(
                          body: notes_empty_response
                        ))
          notes = service.get_care_summaries_and_notes[:records]
          expect(notes.size).to eq(0)
        end
      end
    end

    context 'date range filtering' do
      # SCDF may return notes outside the requested range; API filters so only in-range notes are returned
      it 'returns only notes whose date is within the requested start_date and end_date' do
        # Stub returns all notes from fixture (Dec 2024 + Jan/May 2025)
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)

        # Get all notes first (no date filtering applied by service when using wide range)
        all_notes = service.get_care_summaries_and_notes(start_date: '2024-01-01', end_date: '2025-12-31')[:records]

        # Now get filtered notes for Dec 2024 only
        notes = service.get_care_summaries_and_notes(start_date: '2024-12-01', end_date: '2024-12-31')[:records]

        # Verify filtering actually excluded some notes
        expect(notes.size).to be < all_notes.size
        # Fixture has notes in Dec 2024 and Jan/May 2025; only Dec 2024 should be returned
        expect(notes).not_to be_empty
        notes.each do |note|
          note_date = Date.parse(note.date)
          expect(note_date).to be >= Date.parse('2024-12-01')
          expect(note_date).to be <= Date.parse('2024-12-31')
        end
      end

      it 'excludes notes from future years when filtering for a specific year' do
        # Stub returns all notes from fixture (Dec 2024 + Jan/May 2025)
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)

        # Get all notes first
        all_notes = service.get_care_summaries_and_notes(start_date: '2024-01-01', end_date: '2025-12-31')[:records]

        # Now get filtered notes for 2025 only
        notes = service.get_care_summaries_and_notes(start_date: '2025-01-01', end_date: '2025-12-31')[:records]

        # Verify filtering actually excluded some notes (2024 notes should be filtered out)
        expect(notes.size).to be < all_notes.size
        # All returned notes must be in 2025
        expect(notes).not_to be_empty
        notes.each do |note|
          note_date = Date.parse(note.date)
          expect(note_date.year).to eq(2025)
        end
      end

      it 'handles blank string parameters by using default dates' do
        # Verify blank strings are converted to nil and defaults are applied
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .with(patient_id: user.icn, start_date: '1900-01-01', end_date: anything)
          .and_return(sample_client_response)

        # Blank strings should be treated as nil and use defaults
        result = service.get_care_summaries_and_notes(start_date: '', end_date: '')

        # Should return hash with records array (defaults applied, no filtering errors)
        expect(result).to be_a(Hash)
        expect(result[:records]).to be_an(Array)
      end

      it 'excludes notes with blank or invalid dates' do
        # Disable diagnostic logging to simplify test
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, anything)
          .and_return(false)

        # Create mock notes with various date conditions
        note_with_blank_date = instance_double(
          UnifiedHealthData::ClinicalNotes,
          id: 'blank-date-note', date: nil, source: 'vista', note_type: 'progress_note'
        )
        note_with_invalid_date = instance_double(
          UnifiedHealthData::ClinicalNotes,
          id: 'invalid-date-note', date: 'not-a-date', source: 'vista', note_type: 'consult_result'
        )
        note_with_valid_date = instance_double(
          UnifiedHealthData::ClinicalNotes,
          id: 'valid-note', date: '2024-12-15T10:00:00Z', source: 'oracle-health', note_type: 'progress_note'
        )

        # Stub the service to return our test notes
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)

        # Stub parse_notes to return our controlled notes
        allow(service).to receive(:parse_notes).and_return(
          [note_with_blank_date, note_with_invalid_date, note_with_valid_date]
        )

        allow(Rails.logger).to receive(:warn)

        notes = service.get_care_summaries_and_notes(start_date: '2024-12-01', end_date: '2024-12-31')[:records]

        # Only the valid note should be returned
        expect(notes.size).to eq(1)
        expect(notes.first.id).to eq('valid-note')
      end

      it 'logs per-item exclusion details when diagnostic toggle is enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
          .and_return(true)

        note_with_blank_date = instance_double(
          UnifiedHealthData::ClinicalNotes,
          id: 'blank-date-note', date: nil, source: 'vista', note_type: 'progress_note',
          loinc_codes: []
        )
        note_with_valid_date = instance_double(
          UnifiedHealthData::ClinicalNotes,
          id: 'valid-note', date: '2024-12-15T10:00:00Z', source: 'oracle-health', note_type: 'progress_note',
          loinc_codes: ['11506-3']
        )

        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)
        allow(service).to receive(:parse_notes).and_return(
          [note_with_blank_date, note_with_valid_date]
        )
        allow(Rails.logger).to receive(:warn)

        service.get_care_summaries_and_notes(start_date: '2024-12-01', end_date: '2024-12-31')

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            resource: 'clinical_notes',
            action: 'filter',
            stage: 'date_range_exclusion',
            reason: 'blank_date',
            record_id: 'blank-date-note',
            source: 'vista'
          )
        )
      end
    end

    context 'with date parameters' do
      it 'accepts and uses provided start_date and end_date' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .with(patient_id: user.icn, start_date: '2024-01-01', end_date: '2024-12-31')
          .and_return(sample_client_response)

        service.get_care_summaries_and_notes(start_date: '2024-01-01', end_date: '2024-12-31')
      end

      it 'uses default dates when parameters not provided' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .with(patient_id: user.icn, start_date: '1900-01-01', end_date: anything)
          .and_return(sample_client_response)

        service.get_care_summaries_and_notes
      end

      it 'uses default start_date when only end_date provided' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .with(patient_id: user.icn, start_date: '1900-01-01', end_date: '2024-12-31')
          .and_return(sample_client_response)

        service.get_care_summaries_and_notes(end_date: '2024-12-31')
      end

      it 'uses default end_date when only start_date provided' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .with(patient_id: user.icn, start_date: '2024-01-01', end_date: anything)
          .and_return(sample_client_response)

        service.get_care_summaries_and_notes(start_date: '2024-01-01')
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_care_summaries_and_notes).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_care_summaries_and_notes
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'warning propagation' do
      it 'returns warnings when _warnings are present in the response body' do
        response_with_warnings = notes_sample_response.deep_dup
        response_with_warnings['_warnings'] = [
          { source: 'oracle-health', code: 'not-found', diagnostics: 'Binary/abc123 not found', severity: 'warning' }
        ]
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(Faraday::Response.new(body: response_with_warnings))

        result = service.get_care_summaries_and_notes
        expect(result[:warnings]).to eq(
          [{ source: 'oracle-health', code: 'not-found', diagnostics: 'Binary/abc123 not found', severity: 'warning' }]
        )
        expect(result[:records]).to be_an(Array)
        expect(result[:records]).not_to be_empty
      end

      it 'returns empty warnings when no _warnings in response body' do
        result = service.get_care_summaries_and_notes
        expect(result[:warnings]).to eq([])
      end
    end

    context 'LOINC code logging' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'logs LOINC code distribution when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(true)

        service.get_care_summaries_and_notes

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'loinc_distribution',
            record_type: 'Clinical Notes',
            loinc_code_distribution: '11506-3:4,11488-4:1,4189665:1,18842-5:1,4189666:1,96339-7:1',
            total_codes: 6,
            total_records: 7,
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'does not log LOINC code distribution when flipper disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)

        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(action: 'loinc_distribution'))
        service.get_care_summaries_and_notes
      end
    end

    context 'clinical notes logging' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'logs notes response count when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(true)

        service.get_care_summaries_and_notes

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'does not log notes response count when flipper disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)

        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(resource: 'clinical_notes', action: 'filter'))
        service.get_care_summaries_and_notes
      end
    end

    context 'global toggle fallback (integration)' do
      # Integration-style test: verifies that enabling ONLY the global toggle
      # (not the domain toggle) activates diagnostic logging in both the
      # service concern AND the adapter, proving the full fallback path works.

      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_notes_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)

        # Domain toggle OFF, global toggle ON
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(true)
      end

      it 'activates diagnostic logging in the service concern via global fallback' do
        service.get_care_summaries_and_notes

        # Service concern: log_notes_response_count fires
        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        )

        # Service concern: log_notes_index_metrics and log_raw_source_counts both fire with action: 'index'
        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'index',
            log_level_context: 'diagnostic'
          )
        ).at_least(:once)
      end

      it 'activates diagnostic logging in the adapter via global fallback' do
        # Verify the adapter's MedicalRecordsLog instance also picks up the global toggle.
        # The adapter is created inside the service with `ClinicalNotesAdapter.new(user: @user)`,
        # so its @mr_log must independently evaluate the global fallback.
        adapter = UnifiedHealthData::Adapters::ClinicalNotesAdapter.new(user:)
        expect(adapter.instance_variable_get(:@mr_log).diagnostic_enabled?(
                 MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES
               )).to be true
      end

      it 'activates LOINC distribution logging via global fallback' do
        service.get_care_summaries_and_notes

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'loinc_distribution',
            log_level_context: 'diagnostic'
          )
        )
      end
    end

    context 'index metrics and logging' do
      before do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(true)
      end

      it 'logs source breakdown for the index response' do
        service.get_care_summaries_and_notes

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'index',
            total_notes: 7,
            vista_count: be_a(Integer),
            oracle_health_count: be_a(Integer),
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'emits StatsD gauges for note counts by source' do
        service.get_care_summaries_and_notes

        expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.total', 7)
        expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.vista', be_a(Integer))
        expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.oracle_health', be_a(Integer))
      end
    end
  end

  describe '#get_single_summary_or_note' do
    let(:notes_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'notes_sample_response.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: notes_sample_response
      )
    end

    context 'when source is not provided (defaults to oracle-health)' do
      let(:single_oh_note_response) do
        JSON.parse(Rails.root.join(
          'spec', 'fixtures', 'unified_health_data', 'single_oh_note_response.json'
        ).read)
      end

      let(:oh_client_response) do
        Faraday::Response.new(body: single_oh_note_response)
      end

      before do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:increment)
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .and_return(oh_client_response)
      end

      it 'fetches the note via get_note_by_source defaulting to oracle-health' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .with(hash_including(source: 'oracle-health'))
          .and_return(oh_client_response)

        note = service.get_single_summary_or_note('20875576613')
        expect(note).not_to be_nil
        expect(note.id).to eq('20875576613')
      end

      it 'does not call get_notes_by_date' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .not_to receive(:get_notes_by_date)

        service.get_single_summary_or_note('20875576613')
      end
    end

    context 'when source is oracle-health' do
      let(:single_oh_note_response) do
        JSON.parse(Rails.root.join(
          'spec', 'fixtures', 'unified_health_data', 'single_oh_note_response.json'
        ).read)
      end

      let(:oh_client_response) do
        Faraday::Response.new(body: single_oh_note_response)
      end

      before do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:increment)
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .and_return(oh_client_response)
      end

      it 'calls the source-specific endpoint and returns the note' do
        note = service.get_single_summary_or_note('20875576613', source: 'oracle-health')
        expect(note).not_to be_nil
        expect(note.id).to eq('20875576613')
        expect(note.source).to eq('oracle-health')
      end

      it 'parses the DocumentReference fields correctly' do
        note = service.get_single_summary_or_note('20875576613', source: 'oracle-health')
        expect(note.name).to eq('Abbreviated Visit Summary')
        expect(note.date).to eq('2026-02-02T21:13:27Z')
        expect(note.signed_by).to eq('Victoria A Borland')
        expect(note.location).to eq('668 Mann-Grandstaff WA VA Medical Center')
        expect(note.note).to be_present
        expect(note.addenda).to be_nil
      end

      it 'calls get_note_by_source with the correct params' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .with(patient_id: user.icn, source: 'oracle-health', record_id: '20875576613',
                start_date: '1900-01-01', end_date: Time.zone.today.to_s)
          .and_return(oh_client_response)

        service.get_single_summary_or_note('20875576613', source: 'oracle-health')
      end

      it 'does not call get_notes_by_date' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .not_to receive(:get_notes_by_date)

        service.get_single_summary_or_note('20875576613', source: 'oracle-health')
      end

      it 'returns nil when the response body is blank' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .and_return(Faraday::Response.new(body: nil))

        note = service.get_single_summary_or_note('20875576613', source: 'oracle-health')
        expect(note).to be_nil
      end

      it 'returns nil when the Bundle has no DocumentReference entry' do
        bundle_without_doc_ref = {
          'resourceType' => 'Bundle',
          'entry' => [
            { 'resource' => { 'resourceType' => 'Patient', 'id' => '123' } }
          ]
        }
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_note_by_source)
          .and_return(Faraday::Response.new(body: bundle_without_doc_ref))

        note = service.get_single_summary_or_note('20875576613', source: 'oracle-health')
        expect(note).to be_nil
      end
    end

    context 'error handling' do
      before do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:increment)
      end

      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_single_summary_or_note).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_single_summary_or_note('banana')
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'show metrics and logging' do
      before do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:increment)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
          .and_return(true)
      end

      context 'when fetching a note without source (defaults to oracle-health)' do
        let(:single_oh_note_response) do
          JSON.parse(Rails.root.join(
            'spec', 'fixtures', 'unified_health_data', 'single_oh_note_response.json'
          ).read)
        end

        before do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_note_by_source)
            .and_return(Faraday::Response.new(body: single_oh_note_response))
        end

        it 'logs with source not specified and note_found true' do
          service.get_single_summary_or_note('20875576613')

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              service: 'medical_records',
              resource: 'clinical_notes',
              action: 'show',
              source: 'source not specified',
              note_found: true,
              note_type: be_a(String),
              log_level_context: 'diagnostic'
            )
          )
        end

        it 'emits StatsD increment with source tag source not specified' do
          service.get_single_summary_or_note('20875576613')

          expect(StatsD).to have_received(:increment)
            .with('api.uhd.clinical_notes.show.source', tags: ['source:source not specified'])
        end

        it 'emits StatsD not_found increment when note is missing' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_note_by_source)
            .and_return(Faraday::Response.new(body: nil))

          service.get_single_summary_or_note('nonexistent-id')

          expect(StatsD).to have_received(:increment)
            .with('api.uhd.clinical_notes.show.not_found')
        end

        it 'logs note_found false when note is not found' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_note_by_source)
            .and_return(Faraday::Response.new(body: nil))

          service.get_single_summary_or_note('nonexistent-id')

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              resource: 'clinical_notes',
              action: 'show',
              note_found: false,
              note_type: nil
            )
          )
        end
      end

      context 'when fetching an Oracle Health note' do
        let(:single_oh_note_response) do
          JSON.parse(Rails.root.join(
            'spec', 'fixtures', 'unified_health_data', 'single_oh_note_response.json'
          ).read)
        end

        before do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_note_by_source)
            .and_return(Faraday::Response.new(body: single_oh_note_response))
        end

        it 'logs with source oracle-health and note_found true' do
          service.get_single_summary_or_note('20875576613', source: 'oracle-health')

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              service: 'medical_records',
              resource: 'clinical_notes',
              action: 'show',
              source: 'oracle-health',
              note_found: true,
              log_level_context: 'diagnostic'
            )
          )
        end

        it 'emits StatsD increment with source tag oracle-health' do
          service.get_single_summary_or_note('20875576613', source: 'oracle-health')

          expect(StatsD).to have_received(:increment)
            .with('api.uhd.clinical_notes.show.source', tags: ['source:oracle-health'])
        end
      end
    end
  end

  # After Visit Summaries
  describe '#get_all_avs_metadata' do
    let(:all_avs_response) do
      {
        'entry' => [
          {
            'resource' => {
              'resourceType' => 'Bundle',
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
                }
              ]
            }
          },
          {
            'resource' => {
              'resourceType' => 'Bundle',
              'entry' => [
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
                }
              ]
            }
          }
        ]
      }
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_all_avs)
        .and_return(Faraday::Response.new(body: all_avs_response))
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
  end

  describe '#get_appt_avs' do
    let(:avs_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'after_visit_summary.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: avs_sample_response
      )
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_avs)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      context 'when include_binary is not passed it defaults to false' do
        it 'returns avs with metadata and no binary file' do
          avs = service.get_appt_avs(appt_id: '12345')
          expect(avs.size).to eq(2)
          expect(avs.map(&:note_type)).to contain_exactly(
            'ambulatory_patient_summary',
            'ambulatory_patient_summary'
          )
          expect(avs[0]).to have_attributes(
            {
              'appt_id' => '12345',
              'id' => '15249638961',
              'name' => 'Ambulatory Visit Summary',
              'loinc_codes' => %w[4189669 96345-4],
              'note_type' => 'ambulatory_patient_summary',
              'content_type' => 'application/pdf',
              'binary' => nil
            }
          )
          expect(avs).to all(have_attributes(
                               {
                                 'appt_id' => be_a(String),
                                 'id' => be_a(String),
                                 'name' => be_a(String),
                                 'loinc_codes' => be_an(Array),
                                 'note_type' => be_a(String),
                                 'content_type' => be_a(String),
                                 'binary' => be_nil # should all be nil since include_binary is not passed
                               }
                             ))
        end
      end

      context 'when include_binary is passed as true' do
        it 'returns avs with metadata and binary file' do
          avs = service.get_appt_avs(appt_id: '12345', include_binary: true)
          expect(avs.size).to eq(2)
          expect(avs.map(&:note_type)).to contain_exactly(
            'ambulatory_patient_summary',
            'ambulatory_patient_summary'
          )
          expect(avs[0]).to have_attributes(
            {
              'appt_id' => '12345',
              'id' => '15249638961',
              'name' => 'Ambulatory Visit Summary',
              'loinc_codes' => %w[4189669 96345-4],
              'note_type' => 'ambulatory_patient_summary',
              'content_type' => 'application/pdf',
              'binary' => /JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9TdWJ0e/i
            }
          )
          expect(avs).to all(have_attributes(
                               {
                                 'appt_id' => be_a(String),
                                 'id' => be_a(String),
                                 'name' => be_a(String),
                                 'loinc_codes' => be_an(Array),
                                 'note_type' => be_a(String),
                                 'content_type' => be_a(String),
                                 'binary' => be_a(String)
                               }
                             ))
        end
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_appt_avs).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_appt_avs(appt_id: '12345', include_binary: true)
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'LOINC code logging' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_avs)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
      end

      it 'logs LOINC code distribution when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(true)

        service.get_appt_avs(appt_id: '12345', include_binary: true)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'loinc_distribution',
            record_type: 'AVS',
            loinc_code_distribution: '4189669:2,96345-4:2',
            total_codes: 2,
            total_records: 2,
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'does not log LOINC code distribution when flipper disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)

        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(action: 'loinc_distribution'))
        service.get_appt_avs(appt_id: '12345', include_binary: true)
      end
    end
  end

  describe '#get_avs_binary_data' do
    let(:avs_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'after_visit_summary.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: avs_sample_response
      )
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_avs)
        .and_return(sample_client_response)
    end

    context 'happy path' do
      it 'returns avs binary data and content type' do
        avs = service.get_avs_binary_data(appt_id: '12345', doc_id: '15249638961')
        expect(avs).to have_attributes(
          {
            'content_type' => 'application/pdf',
            'binary' => /JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9TdWJ0e/i
          }
        )
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::Service).to receive(:new).with(user).and_return(uhd_service)
        allow(uhd_service).to receive(:get_avs_binary_data).and_raise(StandardError.new('Unknown fetch error'))

        expect do
          uhd_service.get_avs_binary_data(appt_id: '12345', doc_id: 'banana')
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end
  end

  # Prescriptions
  describe '#get_prescriptions' do
    # All Oracle Health stations present in the VCR cassette
    let(:oh_stations) { %w[556 668 757] }

    before do
      # Freeze today so the generated end_date in service matches VCR cassette date range expectations
      allow(Time.zone).to receive(:today).and_return(Date.new(2026, 3, 25))
      allow(Rails.cache).to receive(:exist?).and_return(false)
    end

    context 'with valid prescription responses', :vcr do
      before do
        # Stub the cache to return facility names for all Oracle Health stations in the cassette
        oh_stations.each do |station|
          allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return('Ambulatory Pharmacy')
          allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(true)
        end
      end

      it 'returns prescriptions from both VistA and Oracle Health' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Assert stable count from deterministic VCR cassette to catch regressions
          expect(prescriptions.size).to eq(76)

          # Check that prescriptions are UnifiedHealthData::Prescription objects
          expect(prescriptions).to all(be_a(UnifiedHealthData::Prescription))

          # Verify both sources contribute data
          ids = prescriptions.map(&:prescription_id)
          expect(ids).to include('26305871') # VistA
          expect(ids).to include('20848812135') # Oracle Health
        end
      end

      context 'with current_only: true' do
        it 'applies filtering to exclude old discontinued/expired prescriptions' do
          travel_to(Time.zone.parse('2026-03-25 12:00:00')) do
            VCR.use_cassette('unified_health_data/get_prescriptions_success', allow_playback_repeats: true) do
              all_prescriptions = service.get_prescriptions[:prescriptions]
              filtered_prescriptions = service.get_prescriptions(current_only: true)[:prescriptions]

              expect(filtered_prescriptions).not_to be_empty
              expect(filtered_prescriptions.size).to be <= all_prescriptions.size

              # Verify every remaining prescription is either not expired/discontinued,
              # or its expiration is within the 180-day window
              cutoff = 180.days.ago.to_date
              filtered_prescriptions.each do |prescription|
                status = prescription.refill_status.to_s.downcase
                next unless %w[expired discontinued].include?(status)

                expiration = Date.parse(prescription.expiration_date) if prescription.expiration_date.present?
                expect(expiration).to be >= cutoff if expiration
              end
            end
          end
        end
      end

      it 'properly maps VistA prescription fields' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }

          expect(vista_prescription.refill_status).to eq('refillinprocess')
          expect(vista_prescription.refill_remaining).to eq(4)
          expect(vista_prescription.facility_name).to eq('Dayton Medical Center')
          expect(vista_prescription.prescription_name).to eq('PROMETHAZINE HCL 25MG TAB')
          expect(vista_prescription.instructions).to include('TAKE ONE TABLET BY MOUTH DAILY')
          expect(vista_prescription.station_number).to eq('989')
          expect(vista_prescription.prescription_number).to eq('2721445')
        end
      end

      it 'properly maps Oracle Health prescription fields' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

          expect(oracle_prescription.refill_status).to eq('submitted')
          expect(oracle_prescription.refill_remaining).to eq(1)
          expect(oracle_prescription.facility_name).to eq('Ambulatory Pharmacy')
          expect(oracle_prescription.ordered_date).to eq('2025-11-17T21:21:48Z')
          expect(oracle_prescription.quantity).to eq('18.0')
          expect(oracle_prescription.expiration_date).to eq('2026-11-17T07:59:59Z')
          expect(oracle_prescription.prescription_name).to eq('albuterol (albuterol 90 mcg inhaler [18g])')
          expect(oracle_prescription.station_number).to eq('668')
          expect(oracle_prescription.is_trackable).to be true
          expect(oracle_prescription.tracking).to be_an(Array)
          expect(oracle_prescription.tracking).not_to be_empty
          expect(oracle_prescription.prescription_source).to eq('VA')
          expect(oracle_prescription.is_refillable).to be false
          expect(oracle_prescription.instructions).to include('Inhalation')
          expect(oracle_prescription.facility_phone_number).to be_nil
        end
      end

      it 'parses prescription number from rx-number and station-prefix identifiers' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          rx_with_number = prescriptions.find { |p| p.prescription_id == '20855608527' }

          expect(rx_with_number.prescription_number).to eq('3001-61868975')
        end
      end

      it 'returns nil prescription number when either identifier element is missing' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          rx_without_number = prescriptions.find { |p| p.prescription_id == '20848812135' }

          expect(rx_without_number.prescription_number).to be_nil
        end
      end

      it 'maps completed status to discontinued or expired' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          completed_prescription = prescriptions.find { |p| p.prescription_id == '20848863583' }

          expect(completed_prescription.refill_status).to be_in(%w[discontinued expired])
          expect(completed_prescription.is_refillable).to be false
          expect(completed_prescription.refill_date).to be_nil
        end
      end

      it 'handles different refill statuses correctly' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Verify we have prescriptions with various statuses
          statuses = prescriptions.map(&:refill_status).uniq
          expect(statuses.size).to be > 1

          discontinued_prescription = prescriptions.find { |p| p.prescription_id == '26305874' }
          expect(discontinued_prescription.refill_status).to eq('discontinued')
        end
      end

      it 'properly handles Oracle Health FHIR features' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Test prescription with patientInstruction (should prefer over text)
          oracle_prescription_with_patient_instruction = prescriptions.find { |p| p.prescription_id == '20848812135' }
          expect(oracle_prescription_with_patient_instruction.instructions).to be_a(String)
          expect(oracle_prescription_with_patient_instruction.facility_name).to eq('Ambulatory Pharmacy')
          refill_date = oracle_prescription_with_patient_instruction.refill_date
          expect(refill_date).to be_a(String)
          expect { Time.iso8601(refill_date) }.not_to raise_error
          expect(oracle_prescription_with_patient_instruction.dispensed_date).to be_nil
        end
      end

      context 'Task resource parsing' do
        it 'sets refill_status to submitted when a valid Task exists' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.refill_status).to eq('submitted')
          end
        end

        it 'sets disp_status to Active: Submitted when a valid Task exists' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.disp_status).to eq('Active: Submitted')
          end
        end

        it 'sets refill_submit_date from Task executionPeriod.start' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.refill_submit_date).to be_a(String)
            expect(submitted_prescription.refill_submit_date).to eq('2026-03-20T18:59:55+00:00')
          end
        end

        it 'ignores Tasks with failed status' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848650695 has multiple Tasks but all have status='failed'
            failed_task_prescription = prescriptions.find { |p| p.prescription_id == '20848650695' }

            # Should NOT have refill_submit_date set from failed Tasks
            expect(failed_task_prescription.refill_submit_date).to be_nil
            # Should have normal active status, not submitted
            expect(failed_task_prescription.refill_status).to eq('active')
          end
        end

        it 'sets disp_status to Active (not Active: Submitted) when Tasks are failed' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848650695 has multiple Tasks but all have status='failed'
            failed_task_prescription = prescriptions.find { |p| p.prescription_id == '20848650695' }

            expect(failed_task_prescription.disp_status).to eq('Active')
          end
        end

        it 'does not affect prescriptions without any Tasks' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # VistA prescription 26305871 should have no Task resources
            vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }

            expect(vista_prescription.refill_status).to be_a(String)
          end
        end
      end

      # is_renewable attribute tests
      #
      # VCR Cassette Data Reference (unified_health_data/get_prescriptions_success):
      # ============================================================================
      # VistA Prescriptions:
      #   26305871: dispStatus='Active', isRenewable=true
      #   26305874: dispStatus='Discontinued', isRenewable=true
      #
      # Oracle Health Prescriptions:
      #   20848812135: status='active', intent='order', refills=2, containedCount=3 (completed dispenses)
      #                → NOT renewable (Gate 6: refills remaining > 0)
      #   20848639997: status='active', intent='plan', refills=0, containedCount=1 (no dispenses)
      #                → NOT renewable (Gate 3: no completed dispenses)
      #   20848863583: status='completed', intent='order', refills=0, containedCount=2
      #                → NOT renewable (Gate 1: status not active)
      #   20849028695: status='active', intent='order', refills=0, containedCount=2 (dispense status='in-progress')
      #                → NOT renewable (Gate 7: active processing)
      #
      # VCR Cassette Data Reference (unified_health_data/get_prescriptions_vista_only):
      # ================================================================================
      # VistA Prescriptions:
      #   25804852: dispStatus='Active: On Hold', isRenewable=false
      #   25804855: dispStatus='Expired', isRenewable=false
      #
      context 'is_renewable attribute' do
        context 'VistA prescriptions' do
          it 'computes is_renewable based on dispStatus and refillRemaining instead of upstream isRenewable' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 26305871: dispStatus='Active', refillRemaining=5, upstream isRenewable=true
              # Computed: false (has refills remaining)
              vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }
              expect(vista_prescription.is_renewable).to be false

              # 26305874: dispStatus='Discontinued', refillRemaining=4, upstream isRenewable=true
              # Computed: false (discontinued is never renewable)
              discontinued_vista = prescriptions.find { |p| p.prescription_id == '26305874' }
              expect(discontinued_vista.is_renewable).to be false
            end
          end

          # NOTE: The vista_only cassette has OperationOutcome errors from Oracle Health,
          # which now raises UpstreamPartialFailure. The is_renewable: true case (tested above
          # with get_prescriptions_success cassette) provides coverage for VistA renewability pass-through.
          # If we need to test is_renewable: false specifically, we'd need a cassette with both
          # sources returning valid data but containing non-renewable prescriptions.
        end

        context 'Oracle Health prescriptions' do
          # Oracle Health renewability is computed client-side using 7 gate checks:
          # Gate 1: status == 'active'
          # Gate 2: VA prescription classification (not reportedBoolean, intent='order')
          # Gate 3: Has at least one completed MedicationDispense
          # Gate 4: Has validity period end date
          # Gate 5: Within 120-day renewal window from expiration
          # Gate 6: Refills exhausted OR prescription expired
          # Gate 7: No active processing (no in-progress/preparation dispenses)

          it 'returns false when refills remaining > 0 (Gate 6)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848812135: status='active', intent='order', refills=2, has completed dispenses
              # Fails Gate 6: Still has 2 refills remaining, prescription not expired
              prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }
              expect(prescription.is_renewable).to be false
            end
          end

          it 'returns false when no dispenses exist (Gate 3)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848639997: status='active', intent='plan', refills=0
              # containedCount=1 but contains Encounter, not MedicationDispense
              # Fails Gate 3: No completed dispenses (never been dispensed)
              prescription = prescriptions.find { |p| p.prescription_id == '20848639997' }
              expect(prescription.is_renewable).to be false
            end
          end

          it 'returns false when status is not active (Gate 1)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848863583: status='completed', intent='order', refills=0, has dispenses
              # Fails Gate 1: Status is 'completed', not 'active'
              prescription = prescriptions.find { |p| p.prescription_id == '20848863583' }
              expect(prescription.is_renewable).to be false
            end
          end
        end
      end

      context 'facility name extraction integration' do
        it 'uses cache when available and API when cache misses' do
          # Test cache hit scenario
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read)
              .with("uhd:facility_names:#{station}")
              .and_return('Cached Facility Name')
            allow(Rails.cache).to receive(:exist?)
              .with("uhd:facility_names:#{station}")
              .and_return(true)
          end

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to eq('Cached Facility Name')
          end
        end

        it 'falls back to API when cache is empty' do
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return(nil)
            allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(false)
          end

          # Mock the Lighthouse API call
          mock_client = instance_double(Lighthouse::Facilities::V1::Client)
          mock_facility = double('facility', name: 'API Retrieved Facility')
          allow(Lighthouse::Facilities::V1::Client).to receive(:new).and_return(mock_client)
          allow(mock_client).to receive(:get_facilities).and_return([mock_facility])

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to eq('API Retrieved Facility')
            expect(mock_client).to have_received(:get_facilities)
              .with(facilityIds: 'vha_668').at_least(:once)
          end
        end

        it 'handles API errors gracefully' do
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return(nil)
            allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(false)
          end
          allow(Rails.logger).to receive(:error)
          allow(StatsD).to receive(:increment)

          # Mock API to raise an error
          mock_client = instance_double(Lighthouse::Facilities::V1::Client)
          allow(Lighthouse::Facilities::V1::Client).to receive(:new).and_return(mock_client)
          allow(mock_client).to receive(:get_facilities).and_raise(StandardError, 'API unavailable')

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to be_nil
            # Error is logged multiple times for different prescriptions with same station number
            expect(Rails.logger).to have_received(:error).with(
              'Failed to fetch facility name from API for station 668: API unavailable'
            ).at_least(:once)
            expect(StatsD).to have_received(:increment).with(
              'unified_health_data.facility_name_fallback.api_error'
            ).at_least(:once)
          end
        end
      end

      it 'logs prescription retrieval information' do
        allow(Rails.logger).to receive(:info)

        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          service.get_prescriptions

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              message: 'UHD prescriptions retrieved',
              total_prescriptions: 76,
              service: 'unified_health_data'
            )
          )
        end
      end
    end

    context 'with empty response', :vcr do
      it 'returns empty prescriptions for empty response' do
        VCR.use_cassette('unified_health_data/get_prescriptions_empty') do
          result = service.get_prescriptions
          expect(result[:prescriptions]).to eq([])
          expect(result[:metadata]).to eq({ has_failed_stations: false })
        end
      end
    end

    context 'with partial data (OperationOutcome errors)', :vcr do
      # The vista_only cassette contains OperationOutcome errors from Oracle Health (rate limiting).
      # The detector now raises UpstreamPartialFailure to prevent returning incomplete data.

      it 'raises UpstreamPartialFailure for VistA-only data when Oracle Health has errors' do
        VCR.use_cassette('unified_health_data/get_prescriptions_vista_only') do
          expect { service.get_prescriptions }.to raise_error(Common::Exceptions::UpstreamPartialFailure) do |error|
            expect(error.failed_sources).to include('oracle-health')
          end
        end
      end
    end

    context 'with Oracle Health only data (no errors)', :vcr do
      # The oracle_only cassette has valid Oracle Health data and empty VistA data (no OperationOutcome errors).
      # This tests that we can successfully parse responses when one source has no data.

      it 'handles Oracle Health-only data without errors' do
        VCR.use_cassette('unified_health_data/get_prescriptions_oracle_only') do
          prescriptions = service.get_prescriptions[:prescriptions]
          expect(prescriptions.size).to eq(34)
          expect(prescriptions.map(&:prescription_id)).to contain_exactly(
            '15214174591', '15215168033', '15216187241', '15215488543', '15214174423', '15215979885',
            '15214174571', '15214777121', '15213998699', '15218955729', '15214535999', '15214303643',
            '15214282441', '15215168043', '15213978785', '15214275861', '15214834723', '15215721639',
            '15217757747', '15215020709', '15215098309', '15214174531', '15217281719', '15217757751',
            '15216346305', '15213978755',
            '15214166465', '15214174425',
            '15214282323', '15214661111', '15214192877',
            '15214103419', '15213928373', '15214166467'
          )
        end
      end
    end

    context 'metadata' do
      it 'always returns a hash with prescriptions and metadata' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          result = service.get_prescriptions

          expect(result).to be_a(Hash)
          expect(result[:prescriptions]).to be_an(Array)
          expect(result[:metadata]).to have_key(:has_failed_stations)
          expect(result[:metadata][:has_failed_stations]).to be false
        end
      end

      it 'returns has_failed_stations: true when VistA has partial failure' do
        VCR.use_cassette('unified_health_data/get_prescriptions_vista_partial_failure') do
          result = service.get_prescriptions

          expect(result).to be_a(Hash)
          expect(result[:metadata][:has_failed_stations]).to be true
        end
      end
    end
  end

  describe '#refill_prescription' do
    before do
      allow_any_instance_of(UnifiedHealthData::Client).to receive(:refill_prescription_orders).and_call_original
    end

    context 'with valid refill request', :vcr do
      it 'submits refill requests and returns success/failure breakdown' do
        VCR.use_cassette('unified_health_data/refill_prescription_success') do
          orders = [
            { id: '20848650695', stationNumber: '668' },
            { id: '0000000000001', stationNumber: '570' }
          ]
          result = service.refill_prescription(orders)

          expect(result[:success]).to eq([{ id: '20848650695', status: 'Refill Submitted', station_number: '668' }])
          expect(result[:failed]).to eq([{ id: '0000000000001', error: 'Prescription is not Found',
                                           station_number: '570' }])
        end
      end

      # TODO: Not sure why this is failing
      #
      #   it 'formats request body correctly' do
      #     VCR.use_cassette('unified_health_data/refill_prescription_success') do
      #       orders = [
      #         { 'id' => '12345', 'stationNumber' => '570' },
      #         { 'id' => '67890', 'stationNumber' => '556' }
      #       ]
      #       expected_body = {
      #         patientId: user.icn,
      #         orders: [
      #           { orderId: '12345', stationNumber: '570' },
      #           { orderId: '67890', stationNumber: '556' }
      #         ]
      #       }.to_json

      #       client = UnifiedHealthData::Client.new
      #       expect(client).to receive(:refill_prescription_orders).with(expected_body)

      #       service.refill_prescription(orders)
      #     end
      #   end
    end

    context 'with service errors' do
      it 'handles network errors gracefully' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:refill_prescription_orders)
          .and_raise(StandardError.new('Network error'))

        orders = [{ id: '12345', stationNumber: '570' }]
        result = service.refill_prescription(orders)

        expect(result[:success]).to eq([])
        expect(result[:failed]).to contain_exactly(
          { id: '12345', error: 'Service unavailable', station_number: '570' }
        )
      end

      it 'logs error when refill fails' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:refill_prescription_orders)
          .and_raise(StandardError.new('API error'))
        allow(Rails.logger).to receive(:error)

        service.refill_prescription([{ id: '12345', stationNumber: '570' }])

        expect(Rails.logger).to have_received(:error).with('Error submitting prescription refill: API error')
      end
    end

    context 'with prescription not found', :vcr do
      it 'returns failed refill when prescription is not found' do
        VCR.use_cassette('unified_health_data/refill_prescription_empty') do
          result = service.refill_prescription([{ id: '21431810851', stationNumber: '663' }])

          expect(result[:success]).to eq([])
          expect(result[:failed]).to eq([{ id: '21431810851', error: 'Prescription is not Found',
                                           station_number: '663' }])
        end
      end
    end

    context 'parse_refill_response edge cases' do
      it 'always returns arrays for success and failed keys with nil response body' do
        response = double(body: nil)

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'always returns arrays for success and failed keys with non-array response body' do
        response = double(body: { error: 'Invalid format' })

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'always returns arrays for success and failed keys with empty array response' do
        response = double(body: [])

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'returns empty failed array when only successes exist' do
        response = double(body: [
                            { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' }
                          ])

        result = service.send(:parse_refill_response, response)

        expect(result[:success]).to eq([
                                         { id: '123', status: 'Success', station_number: '570' }
                                       ])
        expect(result[:failed]).to eq([])
        expect(result[:failed]).to be_an(Array)
      end

      it 'returns empty success array when only failures exist' do
        response = double(body: [
                            { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
                          ])

        result = service.send(:parse_refill_response, response)

        expect(result[:success]).to eq([])
        expect(result[:success]).to be_an(Array)
        expect(result[:failed]).to eq([
                                        { id: '456', error: 'Failed', station_number: '571' }
                                      ])
      end
    end

    context 'extract_successful_refills' do
      it 'returns empty array when no successful refills exist' do
        refill_items = [
          { 'success' => false, 'orderId' => '123', 'message' => 'Failed', 'stationNumber' => '570' }
        ]

        result = service.send(:extract_successful_refills, refill_items)

        expect(result).to eq([])
      end

      it 'returns empty array when refill_items is empty' do
        result = service.send(:extract_successful_refills, [])

        expect(result).to eq([])
      end

      it 'extracts successful refills correctly' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' },
          { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
        ]

        result = service.send(:extract_successful_refills, refill_items)

        expect(result).to eq([
                               { id: '123', status: 'Success', station_number: '570' }
                             ])
      end
    end

    context 'extract_failed_refills' do
      it 'returns empty array when no failed refills exist' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' }
        ]

        result = service.send(:extract_failed_refills, refill_items)

        expect(result).to eq([])
      end

      it 'returns empty array when refill_items is empty' do
        result = service.send(:extract_failed_refills, [])

        expect(result).to eq([])
      end

      it 'extracts failed refills correctly' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' },
          { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
        ]

        result = service.send(:extract_failed_refills, refill_items)

        expect(result).to eq([
                               { id: '456', error: 'Failed', station_number: '571' }
                             ])
      end
    end

    context 'validate_refill_response_count' do
      it 'does not raise error when counts match' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'raises error when response has fewer items than sent' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' },
          { id: '789', stationNumber: '572' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 3 orders, received 2 responses'
        )
      end

      it 'raises error when response has more items than sent' do
        normalized_orders = [
          { id: '123', stationNumber: '570' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 1 orders, received 2 responses'
        )
      end

      it 'raises error when no responses received for multiple orders' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [],
          failed: []
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 2 orders, received 0 responses'
        )
      end

      it 'does not raise error when both orders and responses are empty' do
        normalized_orders = []
        result = {
          success: [],
          failed: []
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'handles all success responses correctly' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [
            { id: '123', status: 'submitted', station_number: '570' },
            { id: '456', status: 'submitted', station_number: '571' }
          ],
          failed: []
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'handles all failed responses correctly' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [],
          failed: [
            { id: '123', error: 'Failed', station_number: '570' },
            { id: '456', error: 'Failed', station_number: '571' }
          ]
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end
    end
  end

  # Conditions
  describe '#get_conditions' do
    let(:conditions_sample_response) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'conditions_sample_response.json').read)
    end
    let(:conditions_empty_vista_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'conditions_empty_vista_response.json'
      ).read)
    end
    let(:conditions_empty_oh_response) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'conditions_empty_oh_response.json').read)
    end
    let(:conditions_empty_response) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'conditions_empty_response.json').read)
    end

    let(:condition_attributes) do
      {
        'id' => be_a(String),
        'name' => be_a(String),
        'date' => be_a(String).or(be_nil),
        'provider' => be_a(String).or(be_nil),
        'facility' => be_a(String).or(be_nil),
        'comments' => be_an(Array).or(be_nil)
      }
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: conditions_sample_response
      )
    end

    before do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(sample_client_response)
    end

    it 'returns conditions from both VistA and Oracle Health' do
      conditions = service.get_conditions[:records]
      expect(conditions.size).to eq(18)
      expect(conditions).to all(be_a(UnifiedHealthData::Condition))
      expect(conditions).to all(have_attributes(condition_attributes))
    end

    it 'returns conditions sorted by date in descending order' do
      conditions = service.get_conditions[:records].sort

      conditions_with_dates = conditions.select { |condition| condition.date.present? }
      dates = conditions_with_dates.map { |condition| Time.zone.parse(condition.date) }
      expect(dates).to eq(dates.sort.reverse)

      conditions_without_dates = conditions.select { |condition| condition.date.nil? }
      if conditions_without_dates.any?
        expect(conditions.last(conditions_without_dates.size)).to eq(conditions_without_dates)
      end
    end

    it 'returns conditions from both VistA and Oracle Health with real sample data' do
      conditions = service.get_conditions[:records]
      expect(conditions.size).to eq(18)
      expect(conditions).to all(be_a(UnifiedHealthData::Condition))
      expect(conditions).to all(have_attributes(condition_attributes))

      vista_conditions = conditions.select { |c| c.id.include?('-') }
      oh_conditions = conditions.reject { |c| c.id.include?('-') }
      expect(vista_conditions).not_to be_empty
      expect(oh_conditions).not_to be_empty

      depression_condition = conditions.find { |c| c.id == '2afda724-55ca-4a78-b815-3e6d9c35cd15' }
      covid_condition = conditions.find { |c| c.id == 'p1533314061' }

      expect(depression_condition).to have_attributes(
        name: 'Major depressive disorder, recurrent, mild',
        provider: 'MCGUIRE,MARCI P',
        facility: 'CHYSHR TEST LAB'
      )

      expect(covid_condition).to have_attributes(
        name: 'Disease caused by 2019-nCoV',
        provider: 'SYSTEM, SYSTEM Cerner, Cerner Managed Acct',
        facility: 'WAMC Bariatric Surgery'
      )
    end

    it 'returns empty array when no data exists' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(Faraday::Response.new(
                      body: conditions_empty_response
                    ))

      conditions = service.get_conditions[:records]
      expect(conditions).to eq([])
    end

    it 'returns conditions from Oracle Health only when VistA is empty' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(Faraday::Response.new(
                      body: conditions_empty_vista_response
                    ))

      conditions = service.get_conditions[:records]
      expect(conditions.size).to eq(2)
      expect(conditions).to all(be_a(UnifiedHealthData::Condition))
      covid_condition = conditions.find { |c| c.id == 'p1533314061' }
      expect(covid_condition.name).to eq('Disease caused by 2019-nCoV')
    end

    it 'returns conditions from VistA only when Oracle Health is empty' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(Faraday::Response.new(
                      body: conditions_empty_oh_response
                    ))

      conditions = service.get_conditions[:records]
      expect(conditions.size).to eq(16)
      expect(conditions).to all(be_a(UnifiedHealthData::Condition))
      first_condition = conditions.find { |c| c.id == '2afda724-55ca-4a78-b815-3e6d9c35cd15' }
      expect(first_condition.name).to eq('Major depressive disorder, recurrent, mild')
    end

    # TODO: This DOES actually raise an error, which seems accurate
    #
    # it 'handles malformed responses gracefully' do
    #   allow_any_instance_of(UnifiedHealthData::Client)
    #     .to receive(:get_conditions_by_date)
    #     .and_return(Faraday::Response.new(
    #                   body: 'invalid'
    #                 ))

    #   expect { service.get_conditions }.not_to raise_error
    #   expect(service.get_conditions).to eq([])
    # end

    it 'handles missing data sections without errors' do
      modified_response = JSON.parse(conditions_sample_response.to_json)
      modified_response['vista'] = nil
      modified_response['oracle-health'] = nil

      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(Faraday::Response.new(
                      body: modified_response
                    ))

      expect { service.get_conditions }.not_to raise_error
      expect(service.get_conditions[:records]).to be_an(Array)
    end

    describe '#get_single_condition' do
      let(:condition_id) { '6f5683ba-2ae8-4d8d-85ff-24babcfbabde' }

      it 'returns a single condition when found' do
        condition = service.get_single_condition(condition_id)
        expect(condition).to be_a(UnifiedHealthData::Condition)
        expect(condition.id).to eq(condition_id)
        expect(condition.name).to eq('Carcinoma in situ of skin, unspecified')
        expect(condition.provider).to eq('MCGUIRE,MARCI P')
        expect(condition.facility).to eq('CHYSHR TEST LAB')
      end

      it 'returns nil when condition not found' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_conditions_by_date)
          .and_return(Faraday::Response.new(
                        body: conditions_empty_response
                      ))
        condition = service.get_single_condition('nonexistent-id')
        expect(condition).to be_nil
      end

      it 'handles malformed responses gracefully' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_conditions_by_date)
          .and_return(Faraday::Response.new(
                        body: nil
                      ))
        expect { service.get_single_condition(condition_id) }.not_to raise_error
        condition = service.get_single_condition(condition_id)
        expect(condition).to be_nil
      end
    end

    context 'logging and metrics' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_conditions_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_conditions_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'calls log_conditions_metrics when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_conditions_diagnostic, user)
          .and_return(true)

        service.get_conditions

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'conditions',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'emits StatsD gauges for conditions index' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_conditions_diagnostic, user)
          .and_return(true)

        service.get_conditions

        expect(StatsD).to have_received(:gauge).with('api.uhd.conditions.index.total', anything)
      end

      it 'does not log diagnostic when flipper disabled' do
        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(resource: 'conditions', action: 'filter'))
        service.get_conditions
      end
    end
  end

  # Vaccines
  describe '#get_immunizations' do
    let(:vaccines_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'immunizations_sample.json'
      ).read)
    end

    let(:sample_client_response) do
      Faraday::Response.new(
        body: vaccines_sample_response
      )
    end

    context 'happy path' do
      context 'when data exists for both VistA + OH' do
        it 'returns all vaccines' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_immunizations_by_date)
            .and_return(sample_client_response)

          vaccines = service.get_immunizations[:records]
          expect(vaccines.size).to eq(24)

          # Verify specific vaccines exist:
          # polio vax: M20875036615 (VistA polio vaccine)
          # vax with note: M20875183434 (OH Flu vaccine with note and manufacturer)
          vista_vaccine = vaccines.find { |v| v.id == 'c648f661-d8a1-4369-b7f1-1ed5c9b5f874' }
          vaccine_oh_with_note = vaccines.find { |v| v.id == 'M20875183434' }

          expect(vista_vaccine).to have_attributes(
            {
              'id' => 'c648f661-d8a1-4369-b7f1-1ed5c9b5f874',
              'cvx_code' => 90_715,
              'date' => '2024-03-04T14:00:00Z',
              'dose_number' => 'COMPLETE',
              'dose_series' => nil,
              'group_name' => 'TDAP',
              'location' => 'GREELEY NURSE',
              'manufacturer' => nil,
              'note' => nil,
              'reaction' => nil,
              'short_description' => 'TDAP',
              'administration_site' => 'RIGHT DELTOID',
              'lot_number' => nil,
              'status' => 'completed'
            }
          )

          expect(vaccine_oh_with_note).to have_attributes(
            {
              'id' => 'M20875183434',
              'cvx_code' => 140,
              'date' => '2025-12-10T16:20:00-06:00',
              'dose_number' => 'Unknown',
              'dose_series' => nil,
              'group_name' => 'INFLUENZA VIRUS VACCINE, INACTIVATED',
              'location' => '556 Captain James A Lovell IL VA Medical Center',
              'manufacturer' => 'Seqirus USA Inc',
              'note' => 'Added comment "note"',
              'reaction' => nil,
              'short_description' => 'influenza virus vaccine, inactivated',
              'administration_site' => 'Shoulder, left (deltoid)',
              'lot_number' => 'AX5586C',
              'status' => 'completed'
            }
          )

          expect(vaccines).to all(have_attributes(
                                    {
                                      'id' => be_a(String),
                                      'cvx_code' => be_a(Integer),
                                      'date' => be_a(String),
                                      'dose_number' => be_a(String).or(be_nil),
                                      'dose_series' => be_a(String).or(be_nil),
                                      'group_name' => be_a(String).or(be_nil),
                                      'location' => be_a(String).or(be_nil),
                                      'manufacturer' => be_a(String).or(be_nil),
                                      'note' => be_a(String).or(be_nil),
                                      'reaction' => be_a(String).or(be_nil),
                                      'short_description' => be_a(String).or(be_nil),
                                      'administration_site' => be_a(String).or(be_nil),
                                      'lot_number' => be_a(String).or(be_nil),
                                      'status' => be_a(String).or(be_nil)
                                    }
                                  ))
        end

        it 'returns vaccines sorted by date in descending order' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_immunizations_by_date)
            .and_return(sample_client_response)

          vaccines = service.get_immunizations[:records].sort

          vaccines_with_dates = vaccines.select { |vaccine| vaccine.date.present? }
          # Use sort_date for comparison since that's what's used for sorting
          dates = vaccines_with_dates.map(&:sort_date)
          expect(dates).to eq(dates.sort.reverse)

          vaccines_without_dates = vaccines.select { |vaccine| vaccine.date.nil? }
          if vaccines_without_dates.any?
            expect(vaccines.last(vaccines_without_dates.size)).to eq(vaccines_without_dates)
          end
        end
      end

      context 'when data exists for only VistA or OH' do
        it 'returns vaccines for VistA only' do
          modified_response = vaccines_sample_response.deep_dup
          modified_response['oracle-health'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_immunizations_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          vaccines = service.get_immunizations[:records]
          expect(vaccines.size).to eq(15)

          expect(vaccines).to all(have_attributes(
                                    {
                                      'id' => be_a(String),
                                      'cvx_code' => be_a(Integer),
                                      'date' => be_a(String),
                                      'dose_number' => be_a(String).or(be_nil),
                                      'dose_series' => be_a(String).or(be_nil),
                                      'group_name' => be_a(String).or(be_nil),
                                      'location' => be_a(String).or(be_nil),
                                      'manufacturer' => be_a(String).or(be_nil),
                                      'note' => be_a(String).or(be_nil),
                                      'reaction' => be_a(String).or(be_nil),
                                      'short_description' => be_a(String).or(be_nil),
                                      'administration_site' => be_a(String).or(be_nil),
                                      'lot_number' => be_a(String).or(be_nil),
                                      'status' => be_a(String).or(be_nil)
                                    }
                                  ))
        end

        it 'returns vaccines for OH only' do
          modified_response = vaccines_sample_response.deep_dup
          modified_response['vista'] = {}
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_immunizations_by_date)
            .and_return(Faraday::Response.new(
                          body: modified_response
                        ))
          vaccines = service.get_immunizations[:records]
          expect(vaccines.size).to eq(9)

          expect(vaccines).to all(have_attributes(
                                    {
                                      'id' => be_a(String),
                                      'cvx_code' => be_a(Integer),
                                      'date' => be_a(String),
                                      'dose_number' => be_a(String).or(be_nil),
                                      'dose_series' => be_a(String).or(be_nil),
                                      'group_name' => be_a(String).or(be_nil),
                                      'location' => be_a(String).or(be_nil),
                                      'manufacturer' => be_a(String).or(be_nil),
                                      'note' => be_a(String).or(be_nil),
                                      'reaction' => be_a(String).or(be_nil),
                                      'short_description' => be_a(String).or(be_nil),
                                      'administration_site' => be_a(String).or(be_nil),
                                      'lot_number' => be_a(String).or(be_nil),
                                      'status' => be_a(String).or(be_nil)
                                    }
                                  ))
        end
      end

      context 'when there are no records in VistA or OH' do
        it 'returns empty array vaccines' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_immunizations_by_date)
            .and_return(Faraday::Response.new(
                          body: { 'vista' => {}, 'oracle-health' => {} }
                        ))
          vaccines = service.get_immunizations[:records]
          expect(vaccines.size).to eq(0)
        end
      end
    end

    context 'error handling' do
      it 'propagates unknown errors from the client' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_immunizations_by_date)
          .and_raise(StandardError.new('Unknown fetch error'))

        expect do
          service.get_immunizations
        end.to raise_error(StandardError, 'Unknown fetch error')
      end
    end

    context 'logging and metrics' do
      before do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_immunizations_by_date)
          .and_return(sample_client_response)
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vaccines_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'calls log_vaccines_metrics when flipper enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vaccines_diagnostic, user)
          .and_return(true)

        service.get_immunizations

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'vaccines',
            action: 'filter',
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'emits StatsD gauges for vaccines index' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_vaccines_diagnostic, user)
          .and_return(true)

        service.get_immunizations

        expect(StatsD).to have_received(:gauge).with('api.uhd.vaccines.index.total', anything)
      end

      it 'does not log diagnostic when flipper disabled' do
        expect(Rails.logger).not_to receive(:info)
          .with(hash_including(resource: 'vaccines', action: 'filter'))
        service.get_immunizations
      end
    end
  end

  # CCD
  describe '#get_ccd_url' do
    let(:client_double) { instance_double(UnifiedHealthData::Client) }
    let(:ccd_body) do
      JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_ready_success.json').read)
    end
    let(:ccd_response) { Faraday::Response.new(body: ccd_body) }
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
    let(:ccd_response) { Faraday::Response.new(response_body: ccd_body, status: response_status) }

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

    let(:jobs_response) { Faraday::Response.new(body: mixed_jobs_body) }

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

  describe 'ICN validation' do
    let(:user_without_icn) { build(:user, :loa3, icn: nil) }
    let(:user_with_empty_icn) { build(:user, :loa3, icn: '') }

    context 'when user has nil ICN' do
      let(:service_without_icn) { described_class.new(user_without_icn) }

      it 'allows initialization without error' do
        expect { described_class.new(user_without_icn) }.not_to raise_error
      end

      it 'raises ParameterMissing when calling get_labs' do
        expect { service_without_icn.get_labs(start_date: 1.year.ago.to_s, end_date: Time.zone.now.to_s) }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_conditions' do
        expect { service_without_icn.get_conditions }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_prescriptions' do
        expect { service_without_icn.get_prescriptions }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_vitals' do
        expect { service_without_icn.get_vitals }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_allergies' do
        expect { service_without_icn.get_allergies }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_immunizations' do
        expect { service_without_icn.get_immunizations }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling initiate_ccd' do
        expect { service_without_icn.initiate_ccd }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end

      it 'raises ParameterMissing when calling get_ccd_jobs' do
        expect { service_without_icn.get_ccd_jobs }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end
    end

    context 'when user has empty string ICN' do
      let(:service_with_empty_icn) { described_class.new(user_with_empty_icn) }

      it 'allows initialization without error' do
        expect { described_class.new(user_with_empty_icn) }.not_to raise_error
      end

      it 'raises ParameterMissing when calling a method that requires ICN' do
        expect { service_with_empty_icn.get_labs(start_date: 1.year.ago.to_s, end_date: Time.zone.now.to_s) }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end
    end

    context 'when user is nil' do
      let(:nil_user_service) { described_class.new(nil) }

      it 'allows initialization without error' do
        expect { described_class.new(nil) }.not_to raise_error
      end

      it 'raises ParameterMissing when calling a method that requires ICN' do
        expect { nil_user_service.get_allergies }
          .to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when methods do not require ICN' do
      let(:service_without_icn) { described_class.new(user_without_icn) }
      let(:client_double) { instance_double(UnifiedHealthData::Client) }
      let(:ccd_body) do
        JSON.parse(Rails.root.join('spec', 'fixtures', 'unified_health_data', 'ccd_ready_success.json').read)
      end
      let(:ccd_response) { Faraday::Response.new(body: ccd_body, status: 200) }

      before do
        allow(UnifiedHealthData::Client).to receive(:new).and_return(client_double)
        allow(client_double).to receive(:get_ccd).and_return(ccd_response)
      end

      it 'get_ccd_status works without ICN' do
        expect { service_without_icn.get_ccd_status(job_id: '12043') }.not_to raise_error
      end

      it 'get_ccd_url works without ICN' do
        expect { service_without_icn.get_ccd_url(job_id: '12043') }.not_to raise_error
      end
    end

    context 'when user has valid ICN' do
      it 'initializes successfully' do
        expect { described_class.new(user) }.not_to raise_error
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

    let(:initiate_response) { Faraday::Response.new(response_body: initiate_body, status: 202) }

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

  # ------------------------------------------------------------------
  # Private helper method specs
  # ------------------------------------------------------------------

  describe '#extract_warnings' do
    it 'returns warnings from the body and removes them' do
      body = {
        'vista' => { 'entry' => [] },
        '_warnings' => [{ 'source' => 'oracle-health', 'code' => 'not-found' }]
      }

      warnings = service.send(:extract_warnings, body)

      expect(warnings).to eq([{ 'source' => 'oracle-health', 'code' => 'not-found' }])
      expect(body).not_to have_key('_warnings')
    end

    it 'returns empty array when body has no _warnings key' do
      body = { 'vista' => { 'entry' => [] } }

      expect(service.send(:extract_warnings, body)).to eq([])
    end

    it 'returns empty array when body is nil' do
      expect(service.send(:extract_warnings, nil)).to eq([])
    end

    it 'returns empty array when body is not a Hash' do
      expect(service.send(:extract_warnings, 'invalid')).to eq([])
    end
  end

  describe '#validate_date_param' do
    it 'does not raise for a valid YYYY-MM-DD date string' do
      expect { service.send(:validate_date_param, '2024-06-15', 'start_date') }.not_to raise_error
    end

    it 'raises ArgumentError for an invalid date string' do
      expect do
        service.send(:validate_date_param, 'not-a-date', 'start_date')
      end.to raise_error(ArgumentError, /Invalid start_date/)
    end

    it 'raises ArgumentError for nil date' do
      expect do
        service.send(:validate_date_param, nil, 'end_date')
      end.to raise_error(ArgumentError, /Invalid end_date/)
    end
  end

  describe '#normalize_orders' do
    it 'returns empty array when orders is nil' do
      expect(service.send(:normalize_orders, nil)).to eq([])
    end

    it 'returns empty array when orders is empty' do
      expect(service.send(:normalize_orders, [])).to eq([])
    end

    it 'converts hash orders to indifferent access' do
      orders = [{ 'id' => '123', 'stationNumber' => '570' }]
      result = service.send(:normalize_orders, orders)
      expect(result.first[:id]).to eq('123')
      expect(result.first['id']).to eq('123')
    end

    it 'passes through objects that do not respond to with_indifferent_access' do
      struct_order = OpenStruct.new(id: '123', stationNumber: '570')
      orders = [struct_order]
      result = service.send(:normalize_orders, orders)
      expect(result.first).to eq(struct_order)
    end
  end

  describe '#build_refill_request_body' do
    it 'builds correct request body from normalized orders' do
      orders = [
        { id: '12345', stationNumber: '570' },
        { id: '67890', stationNumber: '556' }
      ]
      result = service.send(:build_refill_request_body, orders)

      expect(result[:patientId]).to eq(user.icn)
      expect(result[:orders]).to eq([
                                      { orderId: '12345', stationNumber: '570' },
                                      { orderId: '67890', stationNumber: '556' }
                                    ])
    end

    it 'converts ids and station numbers to strings' do
      orders = [{ id: 12_345, stationNumber: 570 }]
      result = service.send(:build_refill_request_body, orders)

      expect(result[:orders].first[:orderId]).to eq('12345')
      expect(result[:orders].first[:stationNumber]).to eq('570')
    end

    it 'handles empty orders' do
      result = service.send(:build_refill_request_body, [])

      expect(result[:patientId]).to eq(user.icn)
      expect(result[:orders]).to eq([])
    end
  end

  describe '#build_error_response' do
    it 'builds error response with Service unavailable for each order' do
      orders = [
        { id: '123', stationNumber: '570' },
        { id: '456', stationNumber: '556' }
      ]
      result = service.send(:build_error_response, orders)

      expect(result[:success]).to eq([])
      expect(result[:failed].size).to eq(2)
      expect(result[:failed].first).to eq({ id: '123', error: 'Service unavailable', station_number: '570' })
      expect(result[:failed].last).to eq({ id: '456', error: 'Service unavailable', station_number: '556' })
    end

    it 'returns empty failed array for empty orders' do
      result = service.send(:build_error_response, [])

      expect(result[:success]).to eq([])
      expect(result[:failed]).to eq([])
    end
  end

  describe '#extract_document_reference' do
    it 'returns the DocumentReference resource from a FHIR Bundle' do
      body = {
        'resourceType' => 'Bundle',
        'entry' => [
          { 'resource' => { 'resourceType' => 'Patient', 'id' => '123' } },
          { 'resource' => { 'resourceType' => 'DocumentReference', 'id' => '456', 'status' => 'current' } }
        ]
      }

      result = service.send(:extract_document_reference, body)
      expect(result['resourceType']).to eq('DocumentReference')
      expect(result['id']).to eq('456')
    end

    it 'returns nil when no DocumentReference is present' do
      body = {
        'resourceType' => 'Bundle',
        'entry' => [
          { 'resource' => { 'resourceType' => 'Patient', 'id' => '123' } }
        ]
      }

      expect(service.send(:extract_document_reference, body)).to be_nil
    end

    it 'returns nil when entries is not an Array' do
      body = { 'resourceType' => 'Bundle', 'entry' => 'invalid' }

      expect(service.send(:extract_document_reference, body)).to be_nil
    end

    it 'returns nil when body is nil' do
      expect(service.send(:extract_document_reference, nil)).to be_nil
    end

    it 'returns nil when body is not a Hash' do
      expect(service.send(:extract_document_reference, 'string')).to be_nil
    end
  end

  describe '#remap_vista_uid' do
    it 'remaps VistA note IDs based on vista-uid identifier' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-id',
                'identifier' => [
                  { 'system' => 'vista-uid', 'value' => 'urn:va:note:500:12345:6789' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_uid, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('500-12345-6789')
    end

    it 'does not remap when no vista-uid identifier is present' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-id',
                'identifier' => [
                  { 'system' => 'other-system', 'value' => 'some-value' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_uid, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('original-id')
    end

    it 'handles entries without identifiers' do
      records = {
        'vista' => {
          'entry' => [
            { 'resource' => { 'id' => 'original-id' } }
          ]
        }
      }

      expect { service.send(:remap_vista_uid, records) }.not_to raise_error
      expect(records['vista']['entry'].first['resource']['id']).to eq('original-id')
    end
  end

  describe '#remap_vista_identifier' do
    it 'remaps VistA allergy IDs based on va.gov systems identifier' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-allergy-id',
                'identifier' => [
                  { 'system' => 'https://va.gov/systems/mhv', 'value' => 'remapped-id-123' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_identifier, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('remapped-id-123')
    end

    it 'does not remap when no matching identifier is present' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-allergy-id',
                'identifier' => [
                  { 'system' => 'http://other.system/id', 'value' => 'other-value' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_identifier, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('original-allergy-id')
    end

    it 'handles entries without identifiers' do
      records = {
        'vista' => {
          'entry' => [
            { 'resource' => { 'id' => 'original-allergy-id' } }
          ]
        }
      }

      expect { service.send(:remap_vista_identifier, records) }.not_to raise_error
      expect(records['vista']['entry'].first['resource']['id']).to eq('original-allergy-id')
    end
  end

  describe '#parse_notes' do
    it 'returns empty array when records is nil' do
      expect(service.send(:parse_notes, nil)).to eq([])
    end

    it 'returns empty array when records is empty' do
      expect(service.send(:parse_notes, [])).to eq([])
    end

    it 'compacts out nil values from parse failures' do
      result = service.send(:parse_notes, [nil, nil])
      expect(result).to eq([])
    end
  end

  describe '#filter_parsed_notes_by_date_range' do
    let(:note_in_range) do
      double('ClinicalNote', date: '2024-06-15T10:00:00Z', id: 'in-range', source: 'vista',
                             note_type: 'progress', blank?: false)
    end
    let(:note_out_of_range) do
      double('ClinicalNote', date: '2023-01-01T10:00:00Z', id: 'out-of-range', source: 'vista',
                             note_type: 'progress', blank?: false)
    end
    let(:note_blank_date) do
      double('ClinicalNote', date: nil, id: 'blank-date', source: 'vista',
                             note_type: 'progress', blank?: false)
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
    end

    it 'returns only notes within the date range' do
      notes = [note_in_range, note_out_of_range]
      result = service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(result.size).to eq(1)
      expect(result.first.id).to eq('in-range')
    end

    it 'excludes notes with blank dates' do
      notes = [note_in_range, note_blank_date]
      result = service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(result.size).to eq(1)
      expect(result.first.id).to eq('in-range')
    end

    it 'returns all notes when start_date is blank' do
      notes = [note_in_range, note_out_of_range]
      result = service.send(:filter_parsed_notes_by_date_range, notes, nil, '2024-12-31')

      expect(result).to eq(notes)
    end

    it 'returns all notes when end_date is blank' do
      notes = [note_in_range, note_out_of_range]
      result = service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', nil)

      expect(result).to eq(notes)
    end

    it 'returns all notes when notes is empty' do
      expect(service.send(:filter_parsed_notes_by_date_range, [], '2024-01-01', '2024-12-31')).to eq([])
    end
  end

  describe '#get_care_summaries_and_notes date validation' do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:gauge)
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_notes_by_date)
        .and_return(Faraday::Response.new(
                      body: { 'vista' => { 'entry' => [] }, 'oracle-health' => { 'entry' => [] } }
                    ))
    end

    it 'raises ArgumentError for invalid start_date' do
      expect do
        service.get_care_summaries_and_notes(start_date: 'not-valid', end_date: '2024-12-31')
      end.to raise_error(ArgumentError, /Invalid start_date/)
    end

    it 'raises ArgumentError for invalid end_date' do
      expect do
        service.get_care_summaries_and_notes(start_date: '2024-01-01', end_date: 'garbage')
      end.to raise_error(ArgumentError, /Invalid end_date/)
    end

    it 'does not raise for valid date parameters' do
      expect do
        service.get_care_summaries_and_notes(start_date: '2024-01-01', end_date: '2024-12-31')
      end.not_to raise_error
    end
  end

  describe '#default_start_date and #default_end_date' do
    it 'returns 1900-01-01 as default start date' do
      expect(service.send(:default_start_date)).to eq('1900-01-01')
    end

    it 'returns today as default end date' do
      expect(service.send(:default_end_date)).to eq(Time.zone.today.to_s)
    end
  end
end
