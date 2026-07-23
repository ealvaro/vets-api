# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/vista_prescription_adapter'
require 'unified_health_data/adapters/oracle_health_prescription_adapter'

RSpec.describe MyHealth::PrescriptionHelperV2 do
  let(:helper_class) do
    Class.new do
      include MyHealth::PrescriptionHelperV2::Filtering
      include MyHealth::PrescriptionHelperV2::Sorting

      attr_accessor :current_user

      def initialize
        @current_user = nil
      end
    end
  end

  let(:helper) { helper_class.new }

  def build_prescription(attrs = {})
    defaults = {
      id: SecureRandom.uuid,
      prescription_name: 'Test Med',
      disp_status: 'Active',
      refill_status: 'active',
      is_refillable: false,
      is_renewable: false,
      is_trackable: false,
      dispensed_date: nil,
      station_number: '123',
      prescription_source: 'VA',
      dispenses: []
    }
    merged = defaults.merge(attrs)
    merged[:id] = attrs[:prescription_id] if attrs.key?(:prescription_id)
    OpenStruct.new(merged)
  end

  # Helper to create a resource-like object for sorting tests
  def build_resource(records)
    OpenStruct.new(records:, metadata: {})
  end

  describe 'MyHealth::PrescriptionHelperV2::Filtering' do
    describe '#filter_data_by_refill_and_renew' do
      it 'includes items that are refillable' do
        refillable_item = build_prescription(is_refillable: true, refill_remaining: 3)
        non_refillable_item = build_prescription(is_refillable: false, disp_status: 'Discontinued')
        data = [refillable_item, non_refillable_item]

        result = helper.filter_data_by_refill_and_renew(data)

        expect(result).to include(refillable_item)
        expect(result).not_to include(non_refillable_item)
      end

      it 'includes items that are renewable (is_renewable: true)' do
        renewable_item = build_prescription(is_renewable: true, is_refillable: false)
        non_renewable_item = build_prescription(is_renewable: false, is_refillable: false)
        data = [renewable_item, non_renewable_item]

        result = helper.filter_data_by_refill_and_renew(data)

        expect(result).to include(renewable_item)
        expect(result).not_to include(non_renewable_item)
      end

      it 'includes items that are both refillable and renewable' do
        both_item = build_prescription(is_refillable: true, is_renewable: true)
        data = [both_item]

        result = helper.filter_data_by_refill_and_renew(data)

        expect(result).to include(both_item)
      end

      it 'excludes items that are neither refillable nor renewable' do
        neither_item = build_prescription(is_refillable: false, is_renewable: false)
        data = [neither_item]

        result = helper.filter_data_by_refill_and_renew(data)

        expect(result).to be_empty
      end

      it 'returns empty array for empty input' do
        result = helper.filter_data_by_refill_and_renew([])
        expect(result).to eq([])
      end

      it 'handles mixed collection correctly' do
        refillable = build_prescription(is_refillable: true, is_renewable: false)
        renewable = build_prescription(is_refillable: false, is_renewable: true)
        neither = build_prescription(is_refillable: false, is_renewable: false)
        data = [refillable, renewable, neither]

        result = helper.filter_data_by_refill_and_renew(data)

        expect(result.length).to eq(2)
        expect(result).to include(refillable, renewable)
        expect(result).not_to include(neither)
      end
    end

    describe '#renewable' do
      it 'returns true when is_renewable is true' do
        prescription = build_prescription(is_renewable: true)
        expect(helper.renewable(prescription)).to be true
      end

      it 'returns false when is_renewable is false' do
        prescription = build_prescription(is_renewable: false)
        expect(helper.renewable(prescription)).to be false
      end

      it 'returns false when is_renewable is nil' do
        prescription = build_prescription(is_renewable: nil)
        expect(helper.renewable(prescription)).to be false
      end

      it 'returns false when item does not respond to is_renewable' do
        item = OpenStruct.new(id: '1')
        expect(helper.renewable(item)).to be false
      end
    end

    describe '#filter_discontinued_non_va_meds' do
      it 'filters out non-VA medications with discontinued status' do
        items = [
          build_prescription(prescription_source: 'NV', refill_status: 'discontinued'),
          build_prescription(prescription_source: 'NV', refill_status: 'Discontinued'),
          build_prescription(prescription_source: 'NV', refill_status: 'active'),
          build_prescription(prescription_source: 'VA', refill_status: 'discontinued')
        ]

        result = helper.filter_discontinued_non_va_meds(items)

        expect(result.length).to eq(2)
        expect(result.map(&:prescription_source)).to contain_exactly('NV', 'VA')
      end

      it 'keeps non-VA medications with nil refill_status' do
        items = [
          build_prescription(prescription_source: 'NV', refill_status: nil),
          build_prescription(prescription_source: 'NV', refill_status: 'discontinued')
        ]

        result = helper.filter_discontinued_non_va_meds(items)

        expect(result.length).to eq(1)
        expect(result.first.refill_status).to be_nil
      end

      it 'returns empty array for empty input' do
        result = helper.filter_discontinued_non_va_meds([])
        expect(result).to eq([])
      end

      it 'keeps items without prescription_source or refill_status methods' do
        item_without_methods = OpenStruct.new(id: '1', prescription_name: 'Test')
        items = [
          item_without_methods,
          build_prescription(prescription_source: 'NV', refill_status: 'discontinued')
        ]

        result = helper.filter_discontinued_non_va_meds(items)

        expect(result.length).to eq(1)
        expect(result).to include(item_without_methods)
      end
    end
  end

  describe 'MyHealth::PrescriptionHelperV2::Sorting' do
    let(:helper_class) do
      Class.new do
        include MyHealth::PrescriptionHelperV2::Sorting
      end
    end
    let(:helper) { helper_class.new }

    describe '#apply_sorting' do
      let(:prescription1) do
        double('prescription1',
               prescription_name: 'Zoloft',
               disp_status: 'Active',
               dispensed_date: Date.new(2024, 1, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:prescription2) do
        double('prescription2',
               prescription_name: 'Aspirin',
               disp_status: 'Active',
               dispensed_date: Date.new(2024, 3, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:prescription3) do
        double('prescription3',
               prescription_name: 'Metformin',
               disp_status: 'Inactive',
               dispensed_date: Date.new(2024, 2, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:prescriptions) { [prescription1, prescription2, prescription3] }

      let(:resource) do
        records = prescriptions.dup
        metadata = {}
        double('resource').tap do |r|
          allow(r).to receive_messages(records:, metadata:)
          allow(r).to receive(:records=) { |new_records| records.replace(new_records) }
          allow(r).to receive(:metadata=) { |new_metadata| metadata.replace(new_metadata) }
        end
      end

      before do
        allow(prescription1).to receive(:respond_to?).with(:dispenses).and_return(true)
        allow(prescription1).to receive(:respond_to?).with(:sorted_dispensed_date).and_return(false)
        allow(prescription2).to receive(:respond_to?).with(:dispenses).and_return(true)
        allow(prescription2).to receive(:respond_to?).with(:sorted_dispensed_date).and_return(false)
        allow(prescription3).to receive(:respond_to?).with(:dispenses).and_return(true)
        allow(prescription3).to receive(:respond_to?).with(:sorted_dispensed_date).and_return(false)
      end

      context 'when sort_param is nil' do
        it 'applies default sorting' do
          result = helper.apply_sorting(resource, nil)

          expect(result.metadata[:sort]).to eq({
                                                 'disp_status' => 'ASC',
                                                 'prescription_name' => 'ASC',
                                                 'dispensed_date' => 'DESC'
                                               })
        end
      end

      context 'when sort_param is alphabetical-rx-name' do
        it 'sorts by prescription_name ascending with secondary sort by dispensed_date descending' do
          result = helper.apply_sorting(resource, 'alphabetical-rx-name')

          expect(result.metadata[:sort]).to eq({
                                                 'prescription_name' => 'ASC',
                                                 'dispensed_date' => 'DESC'
                                               })
        end
      end

      context 'when sort_param is last-fill-date' do
        it 'sorts by dispensed_date descending with secondary sort by prescription_name ascending' do
          result = helper.apply_sorting(resource, 'last-fill-date')

          expect(result.metadata[:sort]).to eq({
                                                 'dispensed_date' => 'DESC',
                                                 'prescription_name' => 'ASC'
                                               })
        end
      end

      context 'when sort_param is unknown' do
        it 'applies default sorting' do
          result = helper.apply_sorting(resource, 'unknown-sort')

          expect(result.metadata[:sort]).to eq({
                                                 'disp_status' => 'ASC',
                                                 'prescription_name' => 'ASC',
                                                 'dispensed_date' => 'DESC'
                                               })
        end
      end

      context 'when sort_param is -alphabetical-rx-name' do
        it 'sorts by prescription_name descending with secondary sort by dispensed_date descending' do
          result = helper.apply_sorting(resource, '-alphabetical-rx-name')
          expected_record_order = resource.records.sort do |first_record, second_record|
            prescription_name_comparison = second_record.prescription_name.to_s <=> first_record.prescription_name.to_s
            next prescription_name_comparison unless prescription_name_comparison.zero?

            second_record.dispensed_date <=> first_record.dispensed_date
          end

          expect(result.metadata[:sort]).to eq({
                                                 'prescription_name' => 'DESC',
                                                 'dispensed_date' => 'DESC'
                                               })
          expect(result.records).to eq(expected_record_order)
        end
      end
    end

    describe '#build_sort_metadata' do
      it 'returns descending metadata for -alphabetical-rx-name' do
        result = helper.build_sort_metadata('-alphabetical-rx-name')
        expect(result).to eq({
                               'prescription_name' => 'DESC',
                               'dispensed_date' => 'DESC'
                             })
      end

      it 'returns last-fill-date metadata for last-fill-date' do
        result = helper.build_sort_metadata('last-fill-date')
        expect(result).to eq({
                               'dispensed_date' => 'DESC',
                               'prescription_name' => 'ASC'
                             })
      end

      it 'returns default metadata for unrecognized sort param' do
        result = helper.build_sort_metadata('-last-fill-date')
        expect(result).to eq({
                               'disp_status' => 'ASC',
                               'prescription_name' => 'ASC',
                               'dispensed_date' => 'DESC'
                             })
      end

      it 'returns alphabetical sort metadata for alphabetical-rx-name' do
        result = helper.build_sort_metadata('alphabetical-rx-name')
        expect(result).to eq({
                               'prescription_name' => 'ASC',
                               'dispensed_date' => 'DESC'
                             })
      end
    end

    describe 'case-insensitive sorting' do
      let(:upper_med) do
        double('upper_med',
               prescription_name: 'BACITRACIN',
               disp_status: 'Active',
               dispensed_date: Date.new(2024, 1, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:lower_med) do
        double('lower_med',
               prescription_name: 'atorvastatin',
               disp_status: 'Active',
               dispensed_date: Date.new(2024, 2, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:title_med) do
        double('title_med',
               prescription_name: 'Celecoxib',
               disp_status: 'Active',
               dispensed_date: Date.new(2024, 3, 1),
               prescription_source: 'VA',
               dispenses: [],
               orderable_item: nil)
      end

      let(:mixed_case_resource) do
        records = [upper_med, lower_med, title_med]
        metadata = {}
        double('resource').tap do |r|
          allow(r).to receive_messages(records:, metadata:)
          allow(r).to receive(:records=) { |new_records| records.replace(new_records) }
          allow(r).to receive(:metadata=) { |new_metadata| metadata.replace(new_metadata) }
        end
      end

      before do
        [upper_med, lower_med, title_med].each do |med|
          allow(med).to receive(:respond_to?).with(:dispenses).and_return(true)
          allow(med).to receive(:respond_to?).with(:sorted_dispensed_date).and_return(false)
        end
      end

      context 'with alphabetical-rx-name sort' do
        it 'sorts names case-insensitively' do
          result = helper.apply_sorting(mixed_case_resource, 'alphabetical-rx-name')
          names = result.records.map(&:prescription_name)

          expect(names).to eq(%w[atorvastatin BACITRACIN Celecoxib])
        end
      end

      context 'with default sort' do
        it 'sorts names case-insensitively within the same status' do
          result = helper.apply_sorting(mixed_case_resource, nil)
          names = result.records.map(&:prescription_name)

          expect(names).to eq(%w[atorvastatin BACITRACIN Celecoxib])
        end
      end

      context 'with Active: Non-VA medications' do
        let(:non_va_upper) do
          double('non_va_upper',
                 prescription_name: nil,
                 disp_status: 'Active: Non-VA',
                 dispensed_date: Date.new(2024, 1, 1),
                 prescription_source: 'NV',
                 dispenses: [],
                 orderable_item: 'DOCUSATE')
        end

        let(:non_va_lower) do
          double('non_va_lower',
                 prescription_name: nil,
                 disp_status: 'Active: Non-VA',
                 dispensed_date: Date.new(2024, 2, 1),
                 prescription_source: 'NV',
                 dispenses: [],
                 orderable_item: 'aspirin')
        end

        let(:non_va_title) do
          double('non_va_title',
                 prescription_name: nil,
                 disp_status: 'Active: Non-VA',
                 dispensed_date: Date.new(2024, 3, 1),
                 prescription_source: 'NV',
                 dispenses: [],
                 orderable_item: 'Buspirone')
        end

        let(:non_va_resource) do
          records = [non_va_upper, non_va_lower, non_va_title]
          metadata = {}
          double('resource').tap do |r|
            allow(r).to receive_messages(records:, metadata:)
            allow(r).to receive(:records=) { |new_records| records.replace(new_records) }
            allow(r).to receive(:metadata=) { |new_metadata| metadata.replace(new_metadata) }
          end
        end

        before do
          [non_va_upper, non_va_lower, non_va_title].each do |med|
            allow(med).to receive(:respond_to?).with(:dispenses).and_return(true)
            allow(med).to receive(:respond_to?).with(:sorted_dispensed_date).and_return(false)
          end
        end

        it 'sorts Non-VA orderable_item names case-insensitively with alphabetical-rx-name' do
          result = helper.apply_sorting(non_va_resource, 'alphabetical-rx-name')
          names = result.records.map(&:orderable_item)

          expect(names).to eq(%w[aspirin Buspirone DOCUSATE])
        end
      end
    end

    describe 'sorting with UnifiedHealthData::Prescription objects' do
      # Reproduces production ArgumentError when sorting prescriptions with mixed date types.
      # UnifiedHealthData::Prescription stores sorted_dispensed_date as String and dispensed_date
      # as String, but get_sorted_dispensed_date can return a Date (from extract_last_refill_date)
      # or a String (from sorted_dispensed_date), causing <=> to fail on type mismatch.

      def build_unified_prescription(attrs = {})
        UnifiedHealthData::Prescription.new({
          id: SecureRandom.uuid,
          prescription_name: 'Test Med',
          disp_status: 'Active',
          is_refillable: false,
          is_renewable: false,
          is_trackable: false,
          dispensed_date: nil,
          station_number: '123',
          prescription_source: 'VA',
          dispenses: [],
          sorted_dispensed_date: nil
        }.merge(attrs))
      end

      context 'when one prescription has dispenses (Date) and another uses sorted_dispensed_date (String)' do
        let(:med_with_dispenses) do
          build_unified_prescription(
            prescription_name: 'Aspirin',
            disp_status: 'Active',
            dispenses: [{ refill_date: '2025-03-15' }],
            sorted_dispensed_date: nil
          )
        end

        let(:med_with_string_date) do
          build_unified_prescription(
            prescription_name: 'Aspirin',
            disp_status: 'Active',
            dispenses: [],
            sorted_dispensed_date: '2025-01-10'
          )
        end

        let(:resource) do
          records = [med_with_string_date, med_with_dispenses]
          OpenStruct.new(records:, metadata: {})
        end

        it 'sorts without error when dates are mixed types in default_sort' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end

        it 'sorts without error when dates are mixed types in last-fill-date sort' do
          expect { helper.apply_sorting(resource, 'last-fill-date') }.not_to raise_error
        end

        it 'sorts without error when dates are mixed types in alphabetical sort' do
          expect { helper.apply_sorting(resource, 'alphabetical-rx-name') }.not_to raise_error
        end
      end

      context 'when prescriptions only use sorted_dispensed_date strings (no dispenses)' do
        let(:med_a) do
          build_unified_prescription(
            prescription_name: 'Aspirin',
            disp_status: 'Active',
            sorted_dispensed_date: '2025-03-15'
          )
        end

        let(:med_b) do
          build_unified_prescription(
            prescription_name: 'Aspirin',
            disp_status: 'Active',
            sorted_dispensed_date: '2025-01-10'
          )
        end

        let(:resource) do
          OpenStruct.new(records: [med_b, med_a], metadata: {})
        end

        it 'does not raise because both dates are coerced from sorted_dispensed_date (same type)' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end
      end

      context 'when sorted_dispensed_date is nil and one prescription has dispenses' do
        let(:med_with_dispenses) do
          build_unified_prescription(
            prescription_name: 'Zoloft',
            disp_status: 'Active',
            dispenses: [{ refill_date: '2025-06-01' }],
            sorted_dispensed_date: nil
          )
        end

        let(:med_with_nil_dates) do
          # sorted_dispensed_date is nil and dispenses is empty. Because
          # UnifiedHealthData::Prescription defines sorted_dispensed_date as an
          # attribute, respond_to?(:sorted_dispensed_date) is true, so
          # get_sorted_dispensed_date returns nil&.to_date (nil) without ever
          # reaching the dispensed_date fallback.
          build_unified_prescription(
            prescription_name: 'Zoloft',
            disp_status: 'Active',
            dispenses: [],
            sorted_dispensed_date: nil,
            dispensed_date: '2025-04-01'
          )
        end

        let(:resource) do
          OpenStruct.new(records: [med_with_nil_dates, med_with_dispenses], metadata: {})
        end

        it 'sorts without error when one date is nil and the other is a Date' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end
      end
    end

    describe 'sorting prescriptions built from raw adapter input' do
      include FhirResourceBuilder

      let(:vista_adapter) { UnifiedHealthData::Adapters::VistaPrescriptionAdapter.new }
      # VistA prescription with refill dispenses — adapter sets sorted_dispensed_date from rfRecord dates.
      # The resulting object has dispenses: [{dispensed_date: Date, ...}] and sorted_dispensed_date: "2025-07-20".
      let(:vista_med_with_dispenses) do
        vista_adapter.parse({
                              'prescriptionId' => '111',
                              'prescriptionName' => 'METFORMIN HCL 500MG TAB',
                              'refillStatus' => 'active',
                              'facilityName' => 'Salt Lake City VAMC',
                              'isRefillable' => true,
                              'isTrackable' => false,
                              'prescriptionNumber' => 'RX111',
                              'stationNumber' => '660',
                              'dispStatus' => 'Active',
                              'rxRFRecords' => {
                                'rfRecord' => [
                                  { 'dispensedDate' => 'Thu, 10 Jul 2025 00:00:00 EDT' },
                                  { 'dispensedDate' => 'Sun, 20 Jul 2025 00:00:00 EDT' }
                                ]
                              }
                            })
      end
      # VistA prescription with NO dispenses but a top-level dispensedDate.
      # Adapter sets sorted_dispensed_date from dispensedDate fallback, dispenses is [].
      let(:vista_med_no_dispenses) do
        vista_adapter.parse({
                              'prescriptionId' => '222',
                              'prescriptionName' => 'METFORMIN HCL 500MG TAB',
                              'refillStatus' => 'active',
                              'facilityName' => 'Salt Lake City VAMC',
                              'isRefillable' => true,
                              'isTrackable' => false,
                              'prescriptionNumber' => 'RX222',
                              'stationNumber' => '660',
                              'dispStatus' => 'Active',
                              'dispensedDate' => 'Wed, 01 Jun 2025 00:00:00 EDT'
                            })
      end
      # Oracle Health prescription with a dispense — adapter sets sorted_dispensed_date from whenHandedOver.
      let(:oh_med_with_dispense) do
        oh_adapter.parse(fhir_resource(
          status: 'active',
          source: 'VA',
          dispense_status: 'completed',
          dispense_date: '2025-08-01T10:00:00Z'
        ).merge('id' => '333', 'medicationCodeableConcept' => { 'text' => 'METFORMIN HCL 500MG TAB' }))
      end
      # Oracle Health prescription with NO dispense — sorted_dispensed_date will be nil.
      let(:oh_med_no_dispense) do
        oh_adapter.parse(fhir_resource(
          status: 'active',
          source: 'VA',
          dispense_status: nil
        ).merge(
          'id' => '444',
          'medicationCodeableConcept' => { 'text' => 'METFORMIN HCL 500MG TAB' },
          'contained' => []
        ))
      end
      let(:oh_adapter) { UnifiedHealthData::Adapters::OracleHealthPrescriptionAdapter.new }

      before do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_medications_renewal_request,
                                                  nil).and_return(false)
        facility = instance_double(HealthFacility, name: 'Portland VA Medical Center')
        allow(HealthFacility).to receive(:find_by).and_return(facility)
      end

      context 'when mixing VistA (with dispenses) and VistA (no dispenses, string sorted_dispensed_date)' do
        let(:resource) do
          OpenStruct.new(records: [vista_med_no_dispenses, vista_med_with_dispenses], metadata: {})
        end

        it 'sorts via default sort without error' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end

        it 'sorts via last-fill-date without error' do
          expect { helper.apply_sorting(resource, 'last-fill-date') }.not_to raise_error
        end

        it 'sorts via alphabetical-rx-name without error' do
          expect { helper.apply_sorting(resource, 'alphabetical-rx-name') }.not_to raise_error
        end
      end

      context 'when mixing Oracle Health (with dispense) and VistA (no dispenses)' do
        let(:resource) do
          OpenStruct.new(records: [oh_med_with_dispense, vista_med_no_dispenses], metadata: {})
        end

        it 'sorts via default sort without error' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end

        it 'sorts via last-fill-date without error' do
          expect { helper.apply_sorting(resource, 'last-fill-date') }.not_to raise_error
        end
      end

      context 'when mixing all four variants together' do
        let(:resource) do
          records = [vista_med_with_dispenses, vista_med_no_dispenses,
                     oh_med_with_dispense, oh_med_no_dispense]
          OpenStruct.new(records: records.compact, metadata: {})
        end

        it 'sorts the full mixed collection via default sort without error' do
          expect { helper.apply_sorting(resource, nil) }.not_to raise_error
        end

        it 'sorts the full mixed collection via last-fill-date without error' do
          expect { helper.apply_sorting(resource, 'last-fill-date') }.not_to raise_error
        end

        it 'sorts the full mixed collection via alphabetical-rx-name without error' do
          expect { helper.apply_sorting(resource, 'alphabetical-rx-name') }.not_to raise_error
        end
      end
    end

    describe 'sort ordering verification' do
      # Shared test data covering all sort-relevant dimensions:
      # - Multiple disp_status values (for default sort grouping)
      # - Multiple names (for alphabetical + secondary sorts)
      # - Mix of dated / nil-dated / non-VA (for last-fill-date partitioning)
      # - Same-name meds with different dates (for within-group date sort)
      let(:active_zoloft_june) do
        build_prescription(
          prescription_name: 'Zoloft', disp_status: 'Active',
          dispensed_date: Date.new(2024, 6, 1), prescription_source: 'VA'
        )
      end
      let(:active_aspirin_jan) do
        build_prescription(
          prescription_name: 'Aspirin', disp_status: 'Active',
          dispensed_date: Date.new(2024, 1, 15), prescription_source: 'VA'
        )
      end
      let(:active_aspirin_mar) do
        build_prescription(
          prescription_name: 'Aspirin', disp_status: 'Active',
          dispensed_date: Date.new(2024, 3, 10), prescription_source: 'VA'
        )
      end
      let(:active_lisinopril_no_date) do
        build_prescription(
          prescription_name: 'Lisinopril', disp_status: 'Active',
          dispensed_date: nil, prescription_source: 'VA'
        )
      end
      let(:discontinued_metformin_feb) do
        build_prescription(
          prescription_name: 'Metformin', disp_status: 'Discontinued',
          dispensed_date: Date.new(2024, 2, 20), prescription_source: 'VA'
        )
      end
      let(:non_va_fish_oil) do
        build_prescription(
          prescription_name: 'Fish Oil', disp_status: 'Active: Non-VA',
          dispensed_date: nil, prescription_source: 'NV'
        )
      end
      let(:non_va_vitamin_d) do
        build_prescription(
          prescription_name: 'Vitamin D', disp_status: 'Active: Non-VA',
          dispensed_date: nil, prescription_source: 'NV'
        )
      end

      let(:all_meds) do
        [non_va_vitamin_d, active_lisinopril_no_date, active_aspirin_jan,
         discontinued_metformin_feb, non_va_fish_oil, active_zoloft_june, active_aspirin_mar]
      end

      describe '#default_sort ordering' do
        it 'sorts by disp_status ASC, then name ASC (case-insensitive), then date DESC' do
          resource = build_resource(all_meds.shuffle)
          result = helper.apply_sorting(resource, nil)
          tuples = result.records.map { |m| [m.disp_status, m.prescription_name, m.dispensed_date] }

          # Active < Active: Non-VA < Discontinued (string ASC)
          # Within Active: Aspirin(Mar) Aspirin(Jan) Lisinopril(nil) Zoloft(Jun)
          #   - Aspirin x2: same name, so date DESC → Mar before Jan
          #   - Lisinopril follows the Aspirin entries because name ASC is applied before fill date
          # Within Active: Non-VA: Fish Oil < Vitamin D
          # Within Discontinued: Metformin
          expect(tuples).to eq([
                                 ['Active', 'Aspirin', Date.new(2024, 3, 10)],
                                 ['Active', 'Aspirin', Date.new(2024, 1, 15)],
                                 ['Active', 'Lisinopril', nil],
                                 ['Active', 'Zoloft', Date.new(2024, 6, 1)],
                                 ['Active: Non-VA', 'Fish Oil', nil],
                                 ['Active: Non-VA', 'Vitamin D', nil],
                                 ['Discontinued', 'Metformin', Date.new(2024, 2, 20)]
                               ])
        end

        it 'sorts same-name meds by date descending (newest first)' do
          resource = build_resource([active_aspirin_jan, active_aspirin_mar])
          result = helper.apply_sorting(resource, nil)
          dates = result.records.map(&:dispensed_date)

          expect(dates).to eq([Date.new(2024, 3, 10), Date.new(2024, 1, 15)])
        end

        it 'places nil-date meds before dated meds with the same name and status' do
          aspirin_no_date = build_prescription(
            prescription_name: 'Aspirin', disp_status: 'Active',
            dispensed_date: nil, prescription_source: 'VA'
          )
          resource = build_resource([aspirin_no_date, active_aspirin_mar])
          result = helper.apply_sorting(resource, nil)
          dates = result.records.map(&:dispensed_date)

          # compare_by_fill_date maps nil to -1, so nil sorts before dated entries
          expect(dates).to eq([nil, Date.new(2024, 3, 10)])
        end
      end

      describe '#last_fill_date_sort ordering' do
        it 'places filled meds first, VA no-date meds second, non-VA no-date meds last' do
          resource = build_resource(all_meds.shuffle)
          result = helper.apply_sorting(resource, 'last-fill-date')
          tuples = result.records.map { |m| [m.prescription_name, m.dispensed_date] }

          # Filled (date DESC, name ASC): Zoloft(Jun) > Aspirin(Mar) > Metformin(Feb) > Aspirin(Jan)
          # VA no-date (name ASC): Lisinopril
          # Non-VA no-date (name ASC): Fish Oil, Vitamin D
          expect(tuples).to eq([
                                 ['Zoloft', Date.new(2024, 6, 1)],
                                 ['Aspirin', Date.new(2024, 3, 10)],
                                 ['Metformin', Date.new(2024, 2, 20)],
                                 ['Aspirin', Date.new(2024, 1, 15)],
                                 ['Lisinopril', nil],
                                 ['Fish Oil', nil],
                                 ['Vitamin D', nil]
                               ])
        end

        it 'sorts filled meds by date descending with name as tiebreaker' do
          med_a = build_prescription(
            prescription_name: 'Atorvastatin', disp_status: 'Active',
            dispensed_date: Date.new(2024, 5, 1), prescription_source: 'VA'
          )
          med_b = build_prescription(
            prescription_name: 'Buspirone', disp_status: 'Active',
            dispensed_date: Date.new(2024, 5, 1), prescription_source: 'VA'
          )
          resource = build_resource([med_b, med_a])
          result = helper.apply_sorting(resource, 'last-fill-date')
          names = result.records.map(&:prescription_name)

          expect(names).to eq(%w[Atorvastatin Buspirone])
        end

        it 'sorts VA no-date meds alphabetically' do
          va_z = build_prescription(prescription_name: 'Zolpidem', dispensed_date: nil, prescription_source: 'VA')
          va_a = build_prescription(prescription_name: 'Amlodipine', dispensed_date: nil, prescription_source: 'VA')
          resource = build_resource([va_z, va_a])
          result = helper.apply_sorting(resource, 'last-fill-date')

          expect(result.records.map(&:prescription_name)).to eq(%w[Amlodipine Zolpidem])
        end

        it 'sorts non-VA no-date meds alphabetically' do
          nv_z = build_prescription(
            prescription_name: 'Zinc', dispensed_date: nil,
            prescription_source: 'NV', disp_status: 'Active: Non-VA'
          )
          nv_a = build_prescription(
            prescription_name: 'Alpha-lipoic acid', dispensed_date: nil,
            prescription_source: 'NV', disp_status: 'Active: Non-VA'
          )
          resource = build_resource([nv_z, nv_a])
          result = helper.apply_sorting(resource, 'last-fill-date')

          expect(result.records.map(&:prescription_name)).to eq(['Alpha-lipoic acid', 'Zinc'])
        end

        it 'uses dispenses refill_date over dispensed_date when present' do
          med_with_dispenses = build_prescription(
            prescription_name: 'Metoprolol', disp_status: 'Active',
            dispensed_date: Date.new(2024, 1, 1), prescription_source: 'VA',
            dispenses: [{ refill_date: Date.new(2024, 7, 15) }]
          )
          resource = build_resource([active_zoloft_june, med_with_dispenses])
          result = helper.apply_sorting(resource, 'last-fill-date')

          # Metoprolol's refill_date (Jul 15) > Zoloft's dispensed_date (Jun 1)
          expect(result.records.map(&:prescription_name)).to eq(%w[Metoprolol Zoloft])
        end
      end

      describe '#alphabetical_sort ordering' do
        it 'sorts by name ASC (case-insensitive) with date DESC within same name' do
          resource = build_resource(all_meds.shuffle)
          result = helper.apply_sorting(resource, 'alphabetical-rx-name')
          tuples = result.records.map { |m| [m.prescription_name, m.dispensed_date] }

          # Alphabetical (case-insensitive): Aspirin x2, Fish Oil, Lisinopril, Metformin, Vitamin D, Zoloft
          # Within Aspirin group: date DESC → Mar before Jan
          expect(tuples).to eq([
                                 ['Aspirin', Date.new(2024, 3, 10)],
                                 ['Aspirin', Date.new(2024, 1, 15)],
                                 ['Fish Oil', nil],
                                 ['Lisinopril', nil],
                                 ['Metformin', Date.new(2024, 2, 20)],
                                 ['Vitamin D', nil],
                                 ['Zoloft', Date.new(2024, 6, 1)]
                               ])
        end

        it 'sorts same-name meds by date descending within group' do
          resource = build_resource([active_aspirin_jan, active_aspirin_mar])
          result = helper.apply_sorting(resource, 'alphabetical-rx-name')
          dates = result.records.map(&:dispensed_date)

          expect(dates).to eq([Date.new(2024, 3, 10), Date.new(2024, 1, 15)])
        end

        it 'places nil-date meds before dated meds within the same name group' do
          aspirin_no_date = build_prescription(
            prescription_name: 'Aspirin', disp_status: 'Active',
            dispensed_date: nil, prescription_source: 'VA'
          )
          resource = build_resource([active_aspirin_mar, aspirin_no_date, active_aspirin_jan])
          result = helper.apply_sorting(resource, 'alphabetical-rx-name')
          dates = result.records.map(&:dispensed_date)

          # sort_meds_by_date_within_group: empty_dates first, then with_dates (date DESC)
          expect(dates).to eq([nil, Date.new(2024, 3, 10), Date.new(2024, 1, 15)])
        end

        it 'uses orderable_item for Non-VA meds with nil prescription_name' do
          nv_doc = build_prescription(
            prescription_name: nil, disp_status: 'Active: Non-VA',
            dispensed_date: nil, prescription_source: 'NV', orderable_item: 'DOCUSATE'
          )
          nv_asp = build_prescription(
            prescription_name: nil, disp_status: 'Active: Non-VA',
            dispensed_date: nil, prescription_source: 'NV', orderable_item: 'aspirin'
          )
          va_med = build_prescription(
            prescription_name: 'Buspirone', disp_status: 'Active',
            dispensed_date: Date.new(2024, 1, 1), prescription_source: 'VA'
          )
          resource = build_resource([nv_doc, va_med, nv_asp])
          result = helper.apply_sorting(resource, 'alphabetical-rx-name')

          # aspirin (orderable_item) < Buspirone (prescription_name) < DOCUSATE (orderable_item)
          expect(result.records.map { |m| m.prescription_name || m.orderable_item })
            .to eq(%w[aspirin Buspirone DOCUSATE])
        end
      end
    end
  end
end
