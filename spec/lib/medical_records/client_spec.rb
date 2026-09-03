# frozen_string_literal: true

require 'rails_helper'
require 'medical_records/client'
require 'stringio'

describe MedicalRecords::Client do
  context 'when a valid session exists', :vcr do
    before do
      VCR.use_cassette 'mr_client/session' do
        VCR.use_cassette 'mr_client/get_a_patient_by_identifier' do
          @client ||= begin
            client = MedicalRecords::Client.new(session: { user_uuid: '12345', user_id: '22406991' },
                                                icn: '1013868614V792025')
            client.authenticate
            client
          end
        end
      end

      MedicalRecords::Client.send(:public, *MedicalRecords::Client.protected_instance_methods)
    end

    after do
      MedicalRecords::Client.send(:protected, *MedicalRecords::Client.protected_instance_methods)
    end

    let(:client) { @client }

    describe ':patient_not_found guards' do
      let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

      before do
        # Simulate patient_fhir_id being nil (patient not found)
        allow(client).to receive(:patient_fhir_id).and_return(nil)
      end

      it 'list_vitals returns :patient_not_found' do
        expect(client.send(:list_vitals)).to eq(:patient_not_found)
      end

      it 'list_clinical_notes returns :patient_not_found' do
        expect(client.send(:list_clinical_notes)).to eq(:patient_not_found)
      end

      it 'get_clinical_note returns :patient_not_found' do
        expect(client.send(:get_clinical_note, '123')).to eq(:patient_not_found)
      end

      it 'list_labs_and_tests returns :patient_not_found' do
        expect(client.send(:list_labs_and_tests)).to eq(:patient_not_found)
      end

      it 'get_diagnostic_report returns :patient_not_found' do
        expect(client.send(:get_diagnostic_report, '123')).to eq(:patient_not_found)
      end

      it 'get_condition returns :patient_not_found' do
        expect(client.send(:get_condition, '123')).to eq(:patient_not_found)
      end

      it 'list_labs_document_reference returns :patient_not_found' do
        expect(client.send(:list_labs_document_reference)).to eq(:patient_not_found)
      end
    end

    describe 'Getting a patient by identifier' do
      let(:patient_id) { 12_345 }

      it 'adds adds a custom header to bypass FHIR server cache', :vcr do
        VCR.use_cassette 'mr_client/get_a_patient_by_identifier' do
          client.get_patient_by_identifier(client.fhir_client, patient_id)
          expect(
            a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
          ).to have_been_made.at_least_once
        end
      end
    end

    it 'gets a list of allergies', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_allergies' do
        allergy_list = client.list_allergies
        expect(
          a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
        ).to have_been_made.at_least_once
        expect(allergy_list).to be_a(FHIR::Bundle)
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        allergy_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.recordedDate
          curr_date = curr.resource.recordedDate
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    it 'gets a single allergy', :vcr do
      VCR.use_cassette 'mr_client/get_an_allergy' do
        allergy_id = 30_242
        allergy = client.get_allergy(allergy_id)
        expect(allergy).to be_a(FHIR::AllergyIntolerance)
        expect(allergy.id).to eq(allergy_id.to_s)
      end
    end

    it 'gets a list of vaccines', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_vaccines' do
        vaccine_list = client.list_vaccines
        expect(vaccine_list).to be_a(FHIR::Bundle)
        expect(
          a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
        ).to have_been_made.at_least_once
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        vaccine_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.occurrenceDateTime
          curr_date = curr.resource.occurrenceDateTime
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    it 'gets a single vaccine', :vcr do
      VCR.use_cassette 'mr_client/get_a_vaccine' do
        vaccine = client.get_vaccine(2_954)
        expect(vaccine).to be_a(FHIR::Immunization)
      end
    end

    it 'gets a list of vitals', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_vitals' do
        vitals_list = client.list_vitals
        expect(vitals_list).to be_a(FHIR::Bundle)
        expect(
          a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
        ).to have_been_made.at_least_once
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        vitals_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.effectiveDateTime
          curr_date = curr.resource.effectiveDateTime
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    it 'gets a list of health conditions', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_health_conditions' do
        condition_list = client.list_conditions
        expect(
          a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
        ).to have_been_made.at_least_once
        expect(condition_list).to be_a(FHIR::Bundle)
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        condition_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.recordedDate
          curr_date = curr.resource.recordedDate
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    it 'gets a single health condition', :vcr do
      VCR.use_cassette 'mr_client/get_a_health_condition' do
        condition = client.get_condition(4169)
        expect(condition).to be_a(FHIR::Condition)
      end
    end

    it 'gets a list of care summaries & notes', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_clinical_notes' do
        note_list = client.list_clinical_notes
        expect(
          a_request(:any, //).with(headers: { 'Cache-Control' => 'no-cache' })
        ).to have_been_made.at_least_once
        expect(note_list).to be_a(FHIR::Bundle)
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        note_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.context&.period&.end || prev.resource.date
          curr_date = curr.resource.context&.period&.end || curr.resource.date
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    describe 'list_clinical_notes sorting by LOINC code' do
      before { allow(client).to receive(:patient_found?).and_return(true) }

      def make_doc_ref(date:, loinc_code: nil, period_end: nil)
        type = if loinc_code
                 FHIR::CodeableConcept.new(
                   coding: [FHIR::Coding.new(system: 'http://loinc.org', code: loinc_code)]
                 )
               end
        context = FHIR::DocumentReference::Context.new(period: FHIR::Period.new(end: period_end)) if period_end
        FHIR::DocumentReference.new(type:, date:, context:)
      end

      def stub_and_sort(*resources)
        bundle = FHIR::Bundle.new(entry: resources.map { |r| FHIR::Bundle::Entry.new(resource: r) })
        allow(client).to receive(:fhir_search).and_return(bundle)
        client.list_clinical_notes
      end

      it 'sorts non-discharge-summary notes by resource.date (else branch)' do
        result = stub_and_sort(
          make_doc_ref(loinc_code: '11506-3', date: '2023-01-01'),
          make_doc_ref(loinc_code: '11488-4', date: '2023-06-15'),
          make_doc_ref(loinc_code: '11506-3', date: '2024-03-10')
        )
        expect(result.entry.map { |e| e.resource.date }).to eq(%w[2024-03-10 2023-06-15 2023-01-01])
      end

      it 'sorts discharge summaries by context.period.end, not resource.date' do
        result = stub_and_sort(
          make_doc_ref(loinc_code: '11506-3', date: '2023-06-15'),
          make_doc_ref(loinc_code: '18842-5', date: '2020-01-01', period_end: '2024-12-01')
        )
        # Discharge summary sorts first because period.end (2024-12-01) > procedure date (2023-06-15)
        expect(result.entry.map { |e| e.resource.date }).to eq(%w[2020-01-01 2023-06-15])
      end

      it 'uses resource.date when LOINC code is nil (no type coding)' do
        result = stub_and_sort(
          make_doc_ref(loinc_code: '11506-3', date: '2023-05-01'),
          make_doc_ref(date: '2024-01-01') # no LOINC code — falls into else branch
        )
        expect(result.entry.map { |e| e.resource.date }).to eq(%w[2024-01-01 2023-05-01])
      end

      it 'falls back to resource.date for discharge summaries missing context.period.end' do
        result = stub_and_sort(
          make_doc_ref(loinc_code: '11506-3', date: '2023-06-15'),
          make_doc_ref(loinc_code: '18842-5', date: '2024-02-01') # discharge summary without period_end
        )
        # Without period.end, discharge summary falls back to resource.date (2024-02-01)
        expect(result.entry.map { |e| e.resource.date }).to eq(%w[2024-02-01 2023-06-15])
      end
    end

    it 'gets a list of labs & tests', :vcr do
      VCR.use_cassette 'mr_client/get_a_list_of_chemhem_labs' do
        chemhem_list = client.list_labs_and_tests
        expect(chemhem_list).to be_a(FHIR::Bundle)
        # Verify that the list is sorted reverse chronologically (with nil values to the end).
        chemhem_list.entry.each_cons(2) do |prev, curr|
          prev_date = prev.resource.effectiveDateTime
          curr_date = curr.resource.effectiveDateTime
          expect(curr_date.nil? || prev_date >= curr_date).to be true
        end
      end
    end

    it 'gets a single diagnostic report', :vcr do
      VCR.use_cassette 'mr_client/get_a_diagnostic_report' do
        report = client.get_diagnostic_report(1234)
        expect(report).to be_a(FHIR::DiagnosticReport)
      end
    end

    it 'gets a multi-page list of FHIR resources', :vcr do
      VCR.use_cassette 'mr_client/get_multiple_fhir_pages' do
        allergies_list = client.list_allergies
        expect(allergies_list).to be_a(FHIR::Bundle)
        expect(allergies_list.total).to eq(5)
        expect(allergies_list.entry.count).to eq(5)
      end
    end

    describe('#sort_bundle') do
      describe 'sorting with non-nested fields' do
        let(:bundle) { FHIR::Bundle.new(entry: [entry1, entry2, entry3]) }
        let(:entry1) { FHIR::Bundle::Entry.new(resource: resource1) }
        let(:entry2) { FHIR::Bundle::Entry.new(resource: resource2) }
        let(:entry3) { FHIR::Bundle::Entry.new(resource: resource3) }
        let(:resource1) { FHIR::AllergyIntolerance.new(onsetDateTime: '2005') }
        let(:resource2) { FHIR::AllergyIntolerance.new(onsetDateTime: '2000') }
        let(:resource3) { FHIR::AllergyIntolerance.new(onsetDateTime: '2010') }
        let(:resource4) { FHIR::AllergyIntolerance.new }

        context 'when sorting by date in ascending order' do
          it 'returns the entries sorted by date' do
            sorted = client.send(:sort_bundle, bundle, :onsetDateTime)
            expect(sorted.entry.map { |e| e.resource.onsetDateTime }).to eq(%w[2000 2005 2010])
          end
        end

        context 'when sorting by date in descending order' do
          it 'returns the entries sorted by date' do
            sorted = client.send(:sort_bundle, bundle, :onsetDateTime, :desc)
            expect(sorted.entry.map { |e| e.resource.onsetDateTime }).to eq(%w[2010 2005 2000])
          end
        end

        context 'when one of the resources lacks the sorting field' do
          let(:bundle_with_missing_field) { FHIR::Bundle.new(entry: [entry1, entry4, entry2]) }
          let(:entry4) { FHIR::Bundle::Entry.new(resource: resource4) }

          context 'in ascending order' do
            it 'places the entry with the missing field at the end' do
              sorted = client.send(:sort_bundle, bundle_with_missing_field, :onsetDateTime)
              expect(sorted.entry.last.resource.onsetDateTime).to be_nil
            end
          end

          context 'in descending order' do
            it 'places the entry with the missing field at the end' do
              sorted = client.send(:sort_bundle, bundle_with_missing_field, :onsetDateTime, :desc)
              expect(sorted.entry.last.resource.onsetDateTime).to be_nil
            end
          end
        end
      end

      describe 'sorting with nested fields' do
        # Setup for creating a FHIR::Bundle with DocumentReference resources
        let(:bundle) { FHIR::Bundle.new }

        let(:doc_ref1) { FHIR::DocumentReference.new(id: '1', date: '2020-01-01', context: context1) }
        let(:context1) { FHIR::DocumentReference::Context.new(period: period1) }
        let(:period1) { FHIR::Period.new(start: '2020-01-01') }

        let(:doc_ref2) { FHIR::DocumentReference.new(id: '2', date: '2021-01-01') } # Missing nested field

        let(:doc_ref3) { FHIR::DocumentReference.new(id: '3', date: '2022-01-01', context: context3) }
        let(:context3) { FHIR::DocumentReference::Context.new(period: period3) }
        let(:period3) { FHIR::Period.new(start: '2022-01-01') }

        before do
          bundle.entry = [doc_ref1, doc_ref2, doc_ref3].map { |resource| FHIR::Bundle::Entry.new(resource:) }
        end

        it 'sorts by a nested field in ascending order' do
          sorted_bundle = client.send(:sort_bundle, bundle, 'context.period.start', :asc)
          expect(sorted_bundle.entry.map { |e| e.resource.id }).to eq(%w[1 3 2]) # '3' last due to missing field
        end

        it 'sorts by a nested field in descending order' do
          sorted_bundle = client.send(:sort_bundle, bundle, 'context.period.start', :desc)
          expect(sorted_bundle.entry.map { |e| e.resource.id }).to eq(%w[3 1 2]) # '3' last due to missing field
        end

        it 'handles sorting with a non-existent nested field path' do
          sorted_bundle = client.send(:sort_bundle, bundle, 'context.period.end', :asc)
          expect( # All entries treated as having missing field
            sorted_bundle.entry.map do |e|
              e.resource.id
            end
          ).to eq(%w[1 2 3])
        end
      end
    end

    describe('#sort_bundle_with_criteria') do
      let(:bundle) { FHIR::Bundle.new(entry: [entry1, entry2, entry3]) }
      let(:entry1) { FHIR::Bundle::Entry.new(resource: resource1) }
      let(:entry2) { FHIR::Bundle::Entry.new(resource: resource2) }
      let(:entry3) { FHIR::Bundle::Entry.new(resource: resource3) }
      let(:resource1) { FHIR::Patient.new(birthDate: 1930) }
      let(:resource2) { FHIR::Patient.new(birthDate: 1945) }
      let(:resource3) { FHIR::Patient.new(birthDate: 1925) }

      context 'when sorting with mixed resource types' do
        let(:resource4) { FHIR::Observation.new(valueQuantity: FHIR::Quantity.new(value: 1940)) }
        let(:entry4) { FHIR::Bundle::Entry.new(resource: resource4) }

        before { bundle.entry << entry4 }

        it 'sorts based on a custom criteria handling different resource types' do
          sorted = client.send(:sort_bundle_with_criteria, bundle) do |resource|
            case resource
            when FHIR::Patient
              resource.birthDate
            when FHIR::Observation
              resource.valueQuantity.value
            else
              0
            end
          end
          expected_order = [resource3, resource1, resource4, resource2] # [1925, 1930, 1940, 1945]
          expect(sorted.entry.map(&:resource)).to eq(expected_order)
        end
      end

      # Null/nil exception regression test (fix 6a)
      context 'when bundle.entry is nil (fix 6a)' do
        it 'returns the bundle unchanged when entry is nil' do
          bundle = double('FHIR::Bundle', entry: nil)

          result = client.send(:sort_bundle_with_criteria, bundle, :desc, &:date)
          expect(result).to eq(bundle)
        end

        it 'sorts normally when entry is a valid array' do
          entry_old = double('entry_old', resource: double('resource_old', date: '2024-01-01'))
          entry_new = double('entry_new', resource: double('resource_new', date: '2024-06-01'))
          bundle = double('FHIR::Bundle', entry: [entry_old, entry_new])
          allow(bundle).to receive(:entry=)

          result = client.send(:sort_bundle_with_criteria, bundle, :desc, &:date)
          expect(result).to eq(bundle)
        end
      end

      it 'sorts entries ascending using a custom block' do
        r1 = FHIR::Patient.new(birthDate: '1990')
        r2 = FHIR::Patient.new(birthDate: '1970')
        r3 = FHIR::Patient.new(birthDate: '1985')
        bundle = FHIR::Bundle.new(entry: [r1, r2, r3].map do |resource|
          FHIR::Bundle::Entry.new(resource:)
        end)

        result = client.send(:sort_bundle_with_criteria, bundle, :asc, &:birthDate)
        expect(result.entry.map { |e| e.resource.birthDate }).to eq(%w[1970 1985 1990])
      end

      it 'places nil values at the end in ascending order' do
        r1 = FHIR::Patient.new(birthDate: '1990')
        r2 = FHIR::Patient.new
        r3 = FHIR::Patient.new(birthDate: '1970')
        bundle = FHIR::Bundle.new(entry: [r1, r2, r3].map do |resource|
          FHIR::Bundle::Entry.new(resource:)
        end)

        result = client.send(:sort_bundle_with_criteria, bundle, :asc, &:birthDate)
        expect(result.entry.last.resource.birthDate).to be_nil
      end
    end

    describe '#sort_lab_entries' do
      let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

      it 'sorts DiagnosticReport entries by effectiveDateTime in reverse chronological order' do
        report1 = FHIR::DiagnosticReport.new(effectiveDateTime: '2020-01-01')
        report2 = FHIR::DiagnosticReport.new(effectiveDateTime: '2023-06-15')
        report3 = FHIR::DiagnosticReport.new(effectiveDateTime: '2021-07-10')
        entries = [report1, report2, report3]
        client.send(:sort_lab_entries, entries)
        expect(entries.map(&:effectiveDateTime)).to eq(%w[2023-06-15 2021-07-10 2020-01-01])
      end

      it 'sorts DocumentReference entries by date in reverse chronological order' do
        doc1 = FHIR::DocumentReference.new(date: '2019-05-01')
        doc2 = FHIR::DocumentReference.new(date: '2022-12-25')
        entries = [doc1, doc2]
        client.send(:sort_lab_entries, entries)
        expect(entries.map(&:date)).to eq(%w[2022-12-25 2019-05-01])
      end

      it 'sorts mixed DiagnosticReport and DocumentReference entries together' do
        report = FHIR::DiagnosticReport.new(effectiveDateTime: '2020-06-01')
        doc = FHIR::DocumentReference.new(date: '2022-01-15')
        entries = [report, doc]
        client.send(:sort_lab_entries, entries)
        expect(entries.first).to eq(doc)
        expect(entries.last).to eq(report)
      end

      it 'sorts unknown resource types after dated entries (sort key 0)' do
        report = FHIR::DiagnosticReport.new(effectiveDateTime: '2020-01-01')
        unknown = FHIR::Patient.new
        entries = [unknown, report]
        client.send(:sort_lab_entries, entries)
        expect(entries.first).to eq(report)
        expect(entries.last).to eq(unknown)
      end
    end

    describe '#fetch_nested_value' do
      let(:val1) { 2020 }
      let(:val2) { 2021 }
      let(:doc_ref) { FHIR::DocumentReference.new(date: val1, context:) }
      let(:context) { FHIR::DocumentReference::Context.new(period:) }
      let(:period) { FHIR::Period.new(start: val2) }

      it 'fetches a non-nested field' do
        expect(client.fetch_nested_value(doc_ref, 'date')).to eq(val1)
      end

      it 'fetches a nested field' do
        expect(client.fetch_nested_value(doc_ref, 'context.period.start')).to eq(val2)
      end

      it 'returns nil for a non-existent field' do
        expect(client.fetch_nested_value(doc_ref, 'start')).to be_nil
        expect(client.fetch_nested_value(doc_ref, 'context.start')).to be_nil
      end
    end

    describe '#merge_bundles' do
      let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

      it 'merges entries from two bundles and updates total' do
        bundle1 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '1'))
                                   ])
        bundle2 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '2')),
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '3'))
                                   ])
        result = client.send(:merge_bundles, bundle1, bundle2)
        expect(result.entry.length).to eq(3)
        expect(result.total).to eq(3)
        expect(result.entry.map { |e| e.resource.id }).to eq(%w[1 2 3])
      end

      it 'handles bundle2 with nil entry' do
        bundle1 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '1'))
                                   ])
        bundle2 = FHIR::Bundle.new
        bundle2.entry = nil
        result = client.send(:merge_bundles, bundle1, bundle2)
        expect(result.entry.length).to eq(1)
        expect(result.total).to eq(1)
      end

      it 'handles bundle1 with nil entry' do
        bundle1 = FHIR::Bundle.new
        bundle1.entry = nil
        bundle2 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '1'))
                                   ])
        result = client.send(:merge_bundles, bundle1, bundle2)
        expect(result.entry.length).to eq(1)
        expect(result.total).to eq(1)
      end

      it 'raises an error when inputs are not bundles' do
        bundle1 = FHIR::Bundle.new
        non_bundle = FHIR::Patient.new
        expect do
          client.send(:merge_bundles, bundle1, non_bundle)
        end.to raise_error(RuntimeError, 'Both inputs must be FHIR Bundles')
      end

      it 'returns a cloned bundle with merged entries' do
        bundle1 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '1'))
                                   ])
        bundle2 = FHIR::Bundle.new(entry: [
                                     FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '2'))
                                   ])
        result = client.send(:merge_bundles, bundle1, bundle2)
        expect(result.entry.length).to eq(2)
        expect(result.resourceType).to eq('Bundle')
      end
    end

    describe '#handle_api_errors' do
      context 'when response is successful' do
        let(:result) { OpenStruct.new(code: 200, resource: FHIR::Bundle.new) }

        it 'does not raise an exception' do
          expect { client.handle_api_errors(result) }.not_to raise_error
        end
      end

      context 'when response has no error code but the resource is nil' do
        let(:result) { OpenStruct.new(code: 200, resource: nil, body: {}.to_json) }

        it 'raises a BackendServiceException as an upstream bad gateway' do
          client.handle_api_errors(result)
        rescue Common::Exceptions::BackendServiceException => e
          expect(e.key).to eq('MEDICALRECORDS_502')
        else
          raise 'expected BackendServiceException to be raised'
        end
      end

      context 'when response is an error' do
        let(:result) { OpenStruct.new(code: 400, body: { issue: [{ diagnostics: 'Error Message' }] }.to_json) }

        it 'raises a BackendServiceException' do
          expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
        end
      end

      context 'when diagnostics are missing in the response' do
        let(:result) { OpenStruct.new(code: 400, body: {}.to_json) }

        it 'handles missing diagnostics gracefully' do
          expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
        end
      end

      context 'when response body is HTML instead of JSON' do
        let(:html_body) { '<html><body><h1>500 Internal Server Error</h1></body></html>' }
        let(:result) { OpenStruct.new(code: 500, body: html_body) }

        it 'raises a BackendServiceException with a non-JSON diagnostic message' do
          expect(Rails.logger).to receive(:error).with(
            'MedicalRecords received non-JSON error response',
            hash_including(body_size: html_body.length)
          )
          expect { client.handle_api_errors(result) }.to raise_error(
            Common::Exceptions::BackendServiceException
          ) do |error|
            expect(error.message).to include('Upstream service returned a non-JSON response')
          end
        end
      end

      context 'when response body is non-JSON text' do
        let(:result) { OpenStruct.new(code: 502, body: 'Bad Gateway') }

        it 'raises a BackendServiceException and logs safe metadata' do
          expect(Rails.logger).to receive(:error).with(
            'MedicalRecords received non-JSON error response',
            hash_including(body_size: 11)
          )
          expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
        end
      end

      it 'does not raise when result code is nil and a resource is present' do
        result = OpenStruct.new(code: nil, resource: FHIR::Bundle.new)
        expect { client.send(:handle_api_errors, result) }.not_to raise_error
      end

      it 'does not raise for status codes below 400 when a resource is present' do
        result = OpenStruct.new(code: 200, resource: FHIR::Bundle.new)
        expect { client.send(:handle_api_errors, result) }.not_to raise_error
      end

      it 'raises BackendServiceException for 401 Unauthorized' do
        result = OpenStruct.new(code: 401, body: { issue: [{ diagnostics: 'Unauthorized' }] }.to_json)
        expect { client.send(:handle_api_errors, result) }.to raise_error(Common::Exceptions::BackendServiceException)
      end

      it 'raises BackendServiceException for 404 Not Found' do
        result = OpenStruct.new(code: 404, body: { issue: [{ diagnostics: 'Not found' }] }.to_json)
        expect { client.send(:handle_api_errors, result) }.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end
  end

  context 'when the patient is not found', :vcr do
    it 'returns :patient_not_found for 202 response', :vcr do
      VCR.use_cassette 'mr_client/session' do
        VCR.use_cassette 'mr_client/get_a_patient_by_identifier_not_found' do
          partial_client = MedicalRecords::Client.new(session: { user_uuid: '12345',
                                                                 user_id: '22406991' }, icn: '1013868614V792025')
          partial_client.authenticate

          VCR.use_cassette 'mr_client/get_a_list_of_allergies' do
            result = partial_client.list_allergies
            expect(result).to eq(:patient_not_found)
          end
        end
      end
    end
  end

  describe '#parse_error_diagnostics' do
    let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

    it 'extracts diagnostics from a valid JSON body with issue array' do
      body = { issue: [{ diagnostics: 'Something went wrong' }] }.to_json
      expect(client.send(:parse_error_diagnostics, body)).to eq('Something went wrong')
    end

    it 'returns nil when JSON body has no issue key' do
      body = { error: 'Unknown' }.to_json
      expect(client.send(:parse_error_diagnostics, body)).to be_nil
    end

    it 'returns nil when issue array is empty' do
      body = { issue: [] }.to_json
      expect(client.send(:parse_error_diagnostics, body)).to be_nil
    end

    it 'returns nil when issue has no diagnostics field' do
      body = { issue: [{ severity: 'error' }] }.to_json
      expect(client.send(:parse_error_diagnostics, body)).to be_nil
    end

    it 'returns upstream message and logs error for non-JSON body' do
      expect(Rails.logger).to receive(:error).with(
        'MedicalRecords received non-JSON error response',
        hash_including(body_size: anything)
      )
      result = client.send(:parse_error_diagnostics, '<html>Error</html>')
      expect(result).to eq('Upstream service returned a non-JSON response')
    end

    it 'handles nil body gracefully' do
      # nil.to_s => "" which is invalid JSON
      expect(Rails.logger).to receive(:error).with(
        'MedicalRecords received non-JSON error response',
        hash_including(body_size: 0)
      )
      result = client.send(:parse_error_diagnostics, nil)
      expect(result).to eq('Upstream service returned a non-JSON response')
    end
  end

  describe '#fhir_search' do
    let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }
    let(:fhir_model) { FHIR::AllergyIntolerance }
    let(:search_params) do
      {
        search: {
          parameters: {
            patient: 'patient-123',
            'clinical-status': 'active'
          }
        }
      }
    end
    let(:mock_fhir_client) { double('FHIR::Client') }
    let(:first_bundle) { FHIR::Bundle.new(entry: [entry1, entry2], next_link: 'https://example.com/fhir?_getpages=abc&_getpagesoffset=1') }
    let(:second_bundle) { FHIR::Bundle.new(entry: [entry3]) }
    let(:entry1) { FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '1')) }
    let(:entry2) { FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '2')) }
    let(:entry3) { FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '3')) }

    before do
      allow(client).to receive_messages(
        fhir_client: mock_fhir_client,
        default_headers: { 'Cache-Control' => 'no-cache' },
        rewrite_next_link: nil
      )
      allow(client).to receive(:handle_api_errors).and_raise(
        Common::Exceptions::BackendServiceException.new(400, 'Error')
      )
      MedicalRecords::Client.send(:public, *MedicalRecords::Client.protected_instance_methods)
    end

    after do
      MedicalRecords::Client.send(:protected, *MedicalRecords::Client.protected_instance_methods)
    end

    context 'when there is only one page of results' do
      let(:first_reply) { double('FHIR::ClientReply', resource: first_bundle) }

      before do
        allow(client).to receive(:fhir_search_query).and_return(first_reply)
        allow(first_bundle).to receive(:next_link).and_return(nil)
      end

      it 'returns the single bundle without pagination' do
        result = client.fhir_search(fhir_model, search_params)

        expect(client).to have_received(:fhir_search_query).with(fhir_model, search_params)
        expect(client).to have_received(:rewrite_next_link).with(first_bundle)
        expect(result).to eq(first_bundle)
        expect(result.entry.length).to eq(2)
      end
    end

    context 'when there are multiple pages of results' do
      let(:first_reply) { double('FHIR::ClientReply', resource: first_bundle) }
      let(:second_reply) { double('FHIR::ClientReply', resource: second_bundle) }
      let(:next_link) { 'https://example.com/fhir?_getpages=abc&_getpagesoffset=1' }

      before do
        allow(client).to receive(:fhir_search_query).and_return(first_reply)

        # First call to next_link returns the link, second call returns nil
        allow(first_bundle).to receive(:next_link).and_return(next_link)
        allow(second_bundle).to receive(:next_link).and_return(nil)

        allow(mock_fhir_client).to receive(:next_page)
          .with(first_reply, headers: { 'Cache-Control' => 'no-cache' })
          .and_return(second_reply)

        allow(client).to receive(:merge_bundles)
          .with(first_bundle, second_bundle)
          .and_return(FHIR::Bundle.new(entry: [entry1, entry2, entry3]))
      end

      context 'when retry feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_retry_next_page).and_return(false)
        end

        it 'fetches all pages and merges them into a single bundle' do
          result = client.fhir_search(fhir_model, search_params)

          expect(client).to have_received(:fhir_search_query).with(fhir_model, search_params)
          expect(client).to have_received(:rewrite_next_link).with(first_bundle)
          expect(client).to have_received(:rewrite_next_link).with(second_bundle)
          expect(mock_fhir_client).to have_received(:next_page)
            .with(first_reply, headers: { 'Cache-Control' => 'no-cache' })
          expect(client).to have_received(:merge_bundles).with(first_bundle, second_bundle)
          expect(result.entry.length).to eq(3)
        end

        it 'handles API errors on next page requests' do
          error_reply = double('FHIR::ClientReply', resource: nil)
          allow(mock_fhir_client).to receive(:next_page).and_return(error_reply)

          expect { client.fhir_search(fhir_model, search_params) }.to raise_error(Common::Exceptions::BackendServiceException)
          expect(client).to have_received(:handle_api_errors).with(error_reply)
        end
      end

      context 'when retry feature flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_retry_next_page).and_return(true)
          allow(client).to receive(:with_retries).and_yield.and_return(second_reply)
        end

        it 'uses retries when fetching next pages' do
          result = client.fhir_search(fhir_model, search_params)

          expect(client).to have_received(:with_retries).with(fhir_model)
          expect(mock_fhir_client).to have_received(:next_page)
            .with(first_reply, headers: { 'Cache-Control' => 'no-cache' })
          expect(result.entry.length).to eq(3)
        end

        it 'handles API errors with retries on next page requests' do
          error_reply = double('FHIR::ClientReply', resource: nil)
          # Override the parent context setup for this specific test
          allow(mock_fhir_client).to receive(:next_page).and_return(error_reply)
          allow(client).to receive(:merge_bundles)
          allow(client).to receive(:with_retries).and_yield.and_return(error_reply)

          expect { client.fhir_search(fhir_model, search_params) }.to raise_error(Common::Exceptions::BackendServiceException)
          expect(client).to have_received(:handle_api_errors).with(error_reply)
        end
      end
    end

    context 'when there are three pages of results' do
      let(:first_reply) { double('FHIR::ClientReply', resource: first_bundle) }
      let(:second_reply) { double('FHIR::ClientReply', resource: second_bundle) }
      let(:third_bundle) { FHIR::Bundle.new(entry: [FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '4'))]) }
      let(:third_reply) { double('FHIR::ClientReply', resource: third_bundle) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_retry_next_page).and_return(false)
        allow(client).to receive(:fhir_search_query).and_return(first_reply)

        # Configure next_link behavior for pagination
        allow(first_bundle).to receive(:next_link).and_return('page2_link')
        allow(second_bundle).to receive(:next_link).and_return('page3_link')
        allow(third_bundle).to receive(:next_link).and_return(nil)

        allow(mock_fhir_client).to receive(:next_page)
          .with(first_reply, headers: { 'Cache-Control' => 'no-cache' })
          .and_return(second_reply)
        allow(mock_fhir_client).to receive(:next_page)
          .with(second_reply, headers: { 'Cache-Control' => 'no-cache' })
          .and_return(third_reply)

        # Mock merge_bundles to return progressively larger bundles
        intermediate_bundle = FHIR::Bundle.new(entry: [entry1, entry2, entry3])
        end_bundle = FHIR::Bundle.new(entry: [entry1, entry2, entry3,
                                              FHIR::Bundle::Entry.new(resource: FHIR::AllergyIntolerance.new(id: '4'))])

        allow(client).to receive(:merge_bundles)
          .with(first_bundle, second_bundle)
          .and_return(intermediate_bundle)
        allow(client).to receive(:merge_bundles)
          .with(intermediate_bundle, third_bundle)
          .and_return(end_bundle)
      end

      it 'fetches all three pages and merges them sequentially' do
        result = client.fhir_search(fhir_model, search_params)

        expect(mock_fhir_client).to have_received(:next_page).twice
        expect(client).to have_received(:merge_bundles).twice
        expect(client).to have_received(:rewrite_next_link).exactly(3).times
        expect(result.entry.length).to eq(4)
      end
    end

    context 'when the initial search query fails' do
      before do
        # Override the parent context setup and make fhir_search_query raise an exception directly
        allow(client).to receive(:handle_api_errors).and_call_original
        allow(client).to receive(:fhir_search_query).and_raise(
          Common::Exceptions::BackendServiceException.new(400, 'Error')
        )
      end

      it 'handles API errors from the initial query' do
        expect { client.fhir_search(fhir_model, search_params) }.to raise_error(Common::Exceptions::BackendServiceException)

        expect(client).to have_received(:fhir_search_query).with(fhir_model, search_params)
      end
    end
  end

  describe '#default_headers' do
    let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

    it 'includes Cache-Control no-cache header' do
      headers = client.send(:default_headers)
      expect(headers['Cache-Control']).to eq('no-cache')
    end

    it 'includes x-api-key from settings' do
      headers = client.send(:default_headers)
      expect(headers).to have_key('x-api-key')
    end
  end

  describe '#rewrite_next_link' do
    let(:client) { MedicalRecords::Client.new(session: { user_id: 'test' }, icn: 'test') }

    it 'rewrites full URL to relative path for /v1/fhir' do
      next_url = 'https://example.org/v1/fhir?_getpages=abc&_getpagesoffset=1&_count=2'
      bundle = FHIR::Bundle.new(
        link: [FHIR::Bundle::Link.new(relation: 'next', url: next_url)]
      )
      allow(client).to receive(:base_path).and_return('https://fwdproxy.va.gov/v1/fhir/')
      client.send(:rewrite_next_link, bundle)

      expect(bundle.link.find { |l| l.relation == 'next' }.url)
        .to eq('https://fwdproxy.va.gov/v1/fhir?_getpages=abc&_getpagesoffset=1&_count=2')
    end

    it 'rewrites full URL to relative path for /fhir' do
      next_url = 'https://example.org/fhir?_getpages=xyz&_count=1'
      bundle = FHIR::Bundle.new(
        link: [FHIR::Bundle::Link.new(relation: 'next', url: next_url)]
      )
      allow(client).to receive(:base_path).and_return('https://fwdproxy.va.gov/fhir/')
      client.send(:rewrite_next_link, bundle)

      expect(bundle.link.find { |l| l.relation == 'next' }.url)
        .to eq('https://fwdproxy.va.gov/fhir?_getpages=xyz&_count=1')
    end

    it 'returns nil without modifying bundle when no next link is present' do
      bundle = FHIR::Bundle.new(
        link: [FHIR::Bundle::Link.new(relation: 'self', url: 'https://example.org/fhir?page=1')]
      )
      result = client.send(:rewrite_next_link, bundle)
      expect(result).to be_nil
      expect(bundle.link.find { |l| l.relation == 'self' }.url).to eq('https://example.org/fhir?page=1')
    end

    it 'returns nil when bundle has no links' do
      bundle = FHIR::Bundle.new
      expect(client.send(:rewrite_next_link, bundle)).to be_nil
    end
  end

  def extract_date(resource)
    case resource
    when FHIR::DiagnosticReport
      resource.effectiveDateTime.to_i
    when FHIR::DocumentReference
      resource.date.to_i
    else
      0
    end
  end

  describe 'FHIR client patch — custom header injection' do
    subject(:host) { host_class.new(base_fhir_headers, parsed_resource, reply) }

    let(:host_class) do
      Class.new do
        include FHIR::Sections::Crud
        include FHIR::Sections::Feed
        include FHIR::Sections::Search

        attr_reader :fhir_headers_calls, :resource_url_calls, :last_get, :last_post, :strip_base_calls

        def initialize(base_fhir_headers, parsed_resource, reply)
          @default_format = 'application/fhir+json'
          @base_fhir_headers = base_fhir_headers
          @parsed_resource = parsed_resource
          @reply = reply
          @fhir_headers_calls = []
          @resource_url_calls = []
          @strip_base_calls = []
        end

        # Stubs for FHIR::Client helpers referenced by the patched methods.
        def fhir_headers(opts = {})
          @fhir_headers_calls << opts
          @base_fhir_headers
        end

        def resource_url(opts)
          @resource_url_calls << opts
          '/Patient/123'
        end

        def parse_reply(_klass, _format, _reply)
          @parsed_resource
        end

        def strip_base(url)
          @strip_base_calls << url
          url.gsub('http://example.com', '')
        end

        def get(url, headers = {})
          @last_get = [url, headers]
          @reply
        end

        def post(url, body = nil, headers = {})
          @last_post = [url, body, headers]
          @reply
        end
      end
    end

    let(:base_fhir_headers) { { 'Accept' => 'application/fhir+json' } }
    let(:parsed_resource) { double('ParsedResource') }
    let(:reply) { OpenStruct.new(resource: nil, resource_class: nil) }

    describe 'Crud#read' do
      let(:klass) { FHIR::Patient }

      it 'merges custom headers into the GET request' do
        custom = { 'X-Cache-Control' => 'no-cache' }
        host.read(klass, '123', nil, nil, headers: custom)

        expect(host.last_get).to eq(['/Patient/123', base_fhir_headers.merge(custom)])
      end

      it 'uses an empty hash when no custom headers are provided' do
        host.read(klass, '123')

        expect(host.last_get).to eq(['/Patient/123', base_fhir_headers])
      end

      it 'passes the accept header to fhir_headers when a format is given' do
        host.read(klass, '123', 'application/fhir+xml')

        expect(host.fhir_headers_calls.last).to eq(accept: 'application/fhir+xml')
      end

      it 'passes an empty hash to fhir_headers when no format is given' do
        host.read(klass, '123')

        expect(host.fhir_headers_calls.last).to eq({})
      end

      it 'includes summary in options forwarded to resource_url' do
        host.read(klass, '123', nil, :text)

        expect(host.resource_url_calls.last).to include(summary: :text)
      end

      it 'sets resource and resource_class on the reply' do
        result = host.read(klass, '123')

        expect(result.resource).to eq(parsed_resource)
        expect(result.resource_class).to eq(klass)
      end
    end

    describe 'Feed#next_page' do
      let(:link) { Struct.new(:url).new('http://example.com/Patient?page=2') }
      let(:bundle) { Struct.new(:next_link).new(link) }
      let(:current) { Struct.new(:resource, :resource_class).new(bundle, FHIR::Patient) }

      it 'merges custom headers into the GET request' do
        custom = { 'X-Api-Key' => 'abc123' }
        host.next_page(current, headers: custom)

        expect(host.last_get).to eq(['/Patient?page=2', base_fhir_headers.merge(custom)])
      end

      it 'uses an empty hash when no custom headers are provided' do
        host.next_page(current)

        expect(host.last_get).to eq(['/Patient?page=2', base_fhir_headers])
      end

      it 'returns nil when the bundle has no link' do
        no_link = Struct.new(:next_link).new(nil)
        no_link_current = Struct.new(:resource, :resource_class).new(no_link, FHIR::Patient)

        expect(host.next_page(no_link_current)).to be_nil
      end

      it 'does not call get when the bundle has no link' do
        no_link = Struct.new(:next_link).new(nil)
        no_link_current = Struct.new(:resource, :resource_class).new(no_link, FHIR::Patient)
        host.next_page(no_link_current)

        expect(host.last_get).to be_nil
      end

      it 'strips the base URL from the link before requesting' do
        host.next_page(current)

        expect(host.strip_base_calls.last).to eq('http://example.com/Patient?page=2')
      end

      it 'sets resource and resource_class on the reply' do
        result = host.next_page(current)

        expect(result.resource).to eq(parsed_resource)
        expect(result.resource_class).to eq(FHIR::Patient)
      end

      context 'when navigating backward' do
        let(:prev_link) { Struct.new(:url).new('http://example.com/Patient?page=1') }
        let(:prev_bundle) { Struct.new(:previous_link).new(prev_link) }
        let(:prev_current) { Struct.new(:resource, :resource_class).new(prev_bundle, FHIR::Patient) }

        it 'calls previous_link on the bundle' do
          host.next_page(prev_current, {}, FHIR::Sections::Feed::BACKWARD)

          expect(host.last_get).to eq(['/Patient?page=1', base_fhir_headers])
        end

        it 'returns nil when no previous link exists' do
          no_prev = Struct.new(:previous_link).new(nil)
          no_prev_current = Struct.new(:resource, :resource_class).new(no_prev, FHIR::Patient)

          expect(host.next_page(no_prev_current, {}, FHIR::Sections::Feed::BACKWARD)).to be_nil
        end
      end

      context 'when navigating to the first page' do
        let(:first_link) { Struct.new(:url).new('http://example.com/Patient?page=1') }
        let(:first_bundle) { Struct.new(:first_link).new(first_link) }
        let(:first_current) { Struct.new(:resource, :resource_class).new(first_bundle, FHIR::Patient) }

        it 'calls first_link on the bundle' do
          host.next_page(first_current, {}, FHIR::Sections::Feed::FIRST)

          expect(host.last_get).to eq(['/Patient?page=1', base_fhir_headers])
        end
      end

      context 'when navigating to the last page' do
        let(:last_link) { Struct.new(:url).new('http://example.com/Patient?page=9') }
        let(:last_bundle) { Struct.new(:last_link).new(last_link) }
        let(:last_current) { Struct.new(:resource, :resource_class).new(last_bundle, FHIR::Patient) }

        it 'calls last_link on the bundle' do
          host.next_page(last_current, {}, FHIR::Sections::Feed::LAST)

          expect(host.last_get).to eq(['/Patient?page=9', base_fhir_headers])
        end
      end

      context 'when combining page direction with custom headers' do
        let(:prev_link) { Struct.new(:url).new('http://example.com/Patient?page=1') }
        let(:prev_bundle) { Struct.new(:previous_link).new(prev_link) }
        let(:prev_current) { Struct.new(:resource, :resource_class).new(prev_bundle, FHIR::Patient) }

        it 'merges custom headers on a backward navigation' do
          custom = { 'X-Request-ID' => 'req-42' }
          host.next_page(prev_current, { headers: custom }, FHIR::Sections::Feed::BACKWARD)

          expect(host.last_get).to eq(['/Patient?page=1', base_fhir_headers.merge(custom)])
        end
      end
    end

    describe 'Search#search' do
      let(:klass) { FHIR::Patient }

      context 'when using GET (no search flag or body)' do
        it 'merges custom headers into the GET request' do
          custom = { 'X-Cache-Control' => 'no-cache' }
          host.search(klass, headers: custom)

          expect(host.last_get).to eq(['/Patient/123', base_fhir_headers.merge(custom)])
        end

        it 'uses an empty hash when no custom headers are provided' do
          host.search(klass)

          expect(host.last_get).to eq(['/Patient/123', base_fhir_headers])
        end
      end

      context 'when using POST (search body present)' do
        it 'merges custom headers into the POST request' do
          custom = { 'X-Api-Key' => 'key' }
          host.search(klass, search: { body: 'name=test' }, headers: custom)

          post_url, post_body, post_headers = host.last_post
          expect(post_url).to eq('/Patient/123')
          expect(post_body).to eq('name=test')
          expect(post_headers).to include('X-Api-Key' => 'key')
        end

        it 'sets the search flag to true' do
          options = { search: { body: 'name=test' } }
          host.search(klass, options)

          expect(options[:search][:flag]).to be true
        end

        it 'sends the form-urlencoded content type to fhir_headers' do
          host.search(klass, search: { body: 'name=test' })

          expect(host.fhir_headers_calls.last).to eq(content_type: 'application/x-www-form-urlencoded')
        end
      end

      context 'when search flag is explicitly true without a body' do
        it 'uses POST' do
          host.search(klass, search: { flag: true })

          expect(host.last_post).not_to be_nil
        end
      end

      it 'sets resource and resource_class on the reply' do
        result = host.search(klass)

        expect(result.resource).to eq(parsed_resource)
        expect(result.resource_class).to eq(klass)
      end
    end
  end
end
