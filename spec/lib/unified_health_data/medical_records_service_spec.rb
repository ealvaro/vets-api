# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/medical_records_service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::MedicalRecordsService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class }

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  # Labs and Tests
  describe '#get_labs' do
    let(:labs_sample_response) do
      JSON.parse(Rails.root.join(
        'spec', 'fixtures', 'unified_health_data', 'labs_response.json'
      ).read)
    end

    let(:sample_client_response) do
      build_faraday_response(labs_sample_response)
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
            'test_code_display' => 'Chemistry and hematology',
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
            'test_code_display' => 'Microbiology',
            'date_completed' => '2025-03-13T17:28:00Z',
            'source' => 'oracle-health',
            'status' => 'final',
            'comments' => nil
          )
          expect(oh_lab.observations.size).to eq(2)

          expect(oh_lab_with_note).to have_attributes(
            'id' => 'a21b3621-4f42-4504-b41c-6598c8537212',
            'display' => 'CRP',
            'test_code' => 'CH',
            'test_code_display' => 'Chemistry and hematology',
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
            .and_return(build_faraday_response(modified_response))

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
            .and_return(build_faraday_response(modified_response))

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
            .and_return(build_faraday_response({ 'vista' => {}, 'oracle-health' => {} }))

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
          .and_return(build_faraday_response(nil))

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
          .and_return(build_faraday_response(response_with_warnings))

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

    context 'date validation via normalize_date_range' do
      it 'passes valid dates through unchanged' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .with(patient_id: user.icn, start_date: '2025-01-01', end_date: '2025-12-31')
          .and_return(sample_client_response)

        service.get_labs(start_date: '2025-01-01', end_date: '2025-12-31')
      end

      it 'raises ArgumentError for invalid start_date' do
        expect do
          service.get_labs(start_date: 'any', end_date: '2025-12-31')
        end.to raise_error(ArgumentError, "Invalid start_date: 'any'. Expected format: YYYY-MM-DD")
      end

      it 'raises ArgumentError for invalid end_date' do
        expect do
          service.get_labs(start_date: '2025-01-01', end_date: 'any')
        end.to raise_error(ArgumentError, "Invalid end_date: 'any'. Expected format: YYYY-MM-DD")
      end

      it 'defaults nil start_date to 1900-01-01' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .with(patient_id: user.icn, start_date: '1900-01-01', end_date: '2025-12-31')
          .and_return(sample_client_response)

        service.get_labs(start_date: nil, end_date: '2025-12-31')
      end

      it 'defaults nil end_date to today' do
        freeze_time do
          expect_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_labs_by_date)
            .with(patient_id: user.icn, start_date: '2025-01-01', end_date: Time.zone.today.to_s)
            .and_return(sample_client_response)

          service.get_labs(start_date: '2025-01-01', end_date: nil)
        end
      end

      it 'defaults blank start_date to 1900-01-01' do
        expect_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_labs_by_date)
          .with(patient_id: user.icn, start_date: '1900-01-01', end_date: '2025-12-31')
          .and_return(sample_client_response)

        service.get_labs(start_date: '', end_date: '2025-12-31')
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
      build_faraday_response(allergies_sample_response)
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response({ 'vista' => {}, 'oracle-health' => {} }))
          allergies = service.get_allergies[:records]
          expect(allergies.size).to eq(0)
        end
      end
    end

    context 'error handling' do
      it 'handles unknown errors' do
        uhd_service = double
        allow(UnifiedHealthData::MedicalRecordsService).to receive(:new).with(user).and_return(uhd_service)
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
      build_faraday_response(allergies_sample_response)
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
              'date' => '2024-12-17T18:47:21Z',
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
        allow(UnifiedHealthData::MedicalRecordsService).to receive(:new).with(user).and_return(uhd_service)
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
      build_faraday_response(vitals_sample_response)
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
                            'names' => '668 Mann-Grandstaff WA VA Medical Center; 0089C-AMC Womack-Liberty' }],
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
              'location' => '668 Mann-Grandstaff WA VA Medical Center',
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response({ 'vista' => {}, 'oracle-health' => {} }))
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
      build_faraday_response(notes_sample_response)
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
            .and_return(build_faraday_response(notes_no_oh_response))
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
            .and_return(build_faraday_response(notes_no_vista_response))
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
            .and_return(build_faraday_response(notes_empty_response))
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
        allow(UnifiedHealthData::MedicalRecordsService).to receive(:new).with(user).and_return(uhd_service)
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
          .and_return(build_faraday_response(response_with_warnings))

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
      build_faraday_response(notes_sample_response)
    end

    context 'when source is not provided (defaults to oracle-health)' do
      let(:single_oh_note_response) do
        JSON.parse(Rails.root.join(
          'spec', 'fixtures', 'unified_health_data', 'single_oh_note_response.json'
        ).read)
      end

      let(:oh_client_response) do
        build_faraday_response(single_oh_note_response)
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
        build_faraday_response(single_oh_note_response)
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
        expect(note.date).to eq('2026-02-02T21:13:10Z') # encounter-derived from context.period.end
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
          .and_return(build_faraday_response(nil))

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
          .and_return(build_faraday_response(bundle_without_doc_ref))

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
        allow(UnifiedHealthData::MedicalRecordsService).to receive(:new).with(user).and_return(uhd_service)
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
            .and_return(build_faraday_response(single_oh_note_response))
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
            .and_return(build_faraday_response(nil))

          service.get_single_summary_or_note('nonexistent-id')

          expect(StatsD).to have_received(:increment)
            .with('api.uhd.clinical_notes.show.not_found')
        end

        it 'logs note_found false when note is not found' do
          allow_any_instance_of(UnifiedHealthData::Client)
            .to receive(:get_note_by_source)
            .and_return(build_faraday_response(nil))

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
            .and_return(build_faraday_response(single_oh_note_response))
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
      build_faraday_response(conditions_sample_response)
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
        facility: '0089C-AMC Womack-Liberty'
      )
    end

    it 'returns empty array when no data exists' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(build_faraday_response(conditions_empty_response))

      conditions = service.get_conditions[:records]
      expect(conditions).to eq([])
    end

    it 'returns conditions from Oracle Health only when VistA is empty' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(build_faraday_response(conditions_empty_vista_response))

      conditions = service.get_conditions[:records]
      expect(conditions.size).to eq(2)
      expect(conditions).to all(be_a(UnifiedHealthData::Condition))
      covid_condition = conditions.find { |c| c.id == 'p1533314061' }
      expect(covid_condition.name).to eq('Disease caused by 2019-nCoV')
    end

    it 'returns conditions from VistA only when Oracle Health is empty' do
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_conditions_by_date)
        .and_return(build_faraday_response(conditions_empty_oh_response))

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
    #     .and_return(instance_double(Faraday::Response,
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
        .and_return(build_faraday_response(modified_response))

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
          .and_return(build_faraday_response(conditions_empty_response))
        condition = service.get_single_condition('nonexistent-id')
        expect(condition).to be_nil
      end

      it 'handles malformed responses gracefully' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:get_conditions_by_date)
          .and_return(build_faraday_response(nil))
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
      build_faraday_response(vaccines_sample_response)
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response(modified_response))
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
            .and_return(build_faraday_response({ 'vista' => {}, 'oracle-health' => {} }))
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

  # ------------------------------------------------------------------
  # Private helper method specs
  # ------------------------------------------------------------------

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

    it 'excludes notes with unparseable dates' do
      note_with_invalid_date = double('ClinicalNote', date: 'not-a-date', id: 'invalid-date',
                                                      source: 'vista', note_type: 'consult', blank?: false)
      notes = [note_in_range, note_with_invalid_date]

      result = service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(result.size).to eq(1)
      expect(result.first.id).to eq('in-range')
    end

    it 'logs exclusion details for notes with blank dates' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
        .and_return(true)

      notes = [note_in_range, note_blank_date]
      service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          resource: 'clinical_notes',
          action: 'filter',
          stage: 'date_range_exclusion',
          reason: 'blank_date',
          record_id: 'blank-date',
          source: 'vista'
        )
      )
    end

    it 'logs exclusion details for notes outside date range' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
        .and_return(true)

      notes = [note_in_range, note_out_of_range]
      service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          resource: 'clinical_notes',
          action: 'filter',
          stage: 'date_range_exclusion',
          reason: 'out_of_range',
          record_id: 'out-of-range',
          source: 'vista'
        )
      )
    end

    it 'logs exclusion details for notes with unparseable dates' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, anything)
        .and_return(true)

      note_with_invalid_date = double('ClinicalNote', date: 'not-a-date', id: 'invalid-date',
                                                      source: 'oracle-health', note_type: 'progress', blank?: false)
      notes = [note_in_range, note_with_invalid_date]
      service.send(:filter_parsed_notes_by_date_range, notes, '2024-01-01', '2024-12-31')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          resource: 'clinical_notes',
          action: 'filter',
          stage: 'date_range_exclusion',
          reason: 'unparseable_date',
          record_id: 'invalid-date',
          source: 'oracle-health'
        )
      )
    end
  end

  describe '#get_care_summaries_and_notes date validation' do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:gauge)
      allow_any_instance_of(UnifiedHealthData::Client)
        .to receive(:get_notes_by_date)
        .and_return(build_faraday_response({ 'vista' => { 'entry' => [] }, 'oracle-health' => { 'entry' => [] } }))
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
end
