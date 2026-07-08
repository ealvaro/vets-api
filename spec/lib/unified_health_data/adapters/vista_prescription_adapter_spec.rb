# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/prescriptions_adapter'

describe UnifiedHealthData::Adapters::VistaPrescriptionAdapter do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class.new }

  let(:base_vista_medication) do
    {
      'prescriptionId' => '12345',
      'prescriptionName' => 'Test Medication',
      'refillStatus' => 'active',
      'facilityName' => 'Test Facility',
      'isRefillable' => true,
      'isTrackable' => false,
      'prescriptionNumber' => 'RX123',
      'stationNumber' => '660',
      'sig' => 'Take as directed',
      'cmopDivisionPhone' => '555-1234',
      'dialCmopDivisionPhone' => '555-DIAL-TEST',
      'cmopNdcNumber' => nil
    }
  end

  let(:vista_medication_with_tracking) do
    {
      'prescriptionId' => '28148666',
      'refillStatus' => 'active',
      'refillSubmitDate' => nil,
      'refillDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
      'refillRemaining' => 5,
      'facilityName' => 'Salt Lake City VAMC',
      'isRefillable' => true,
      'isTrackable' => true,
      'sig' => 'Take one tablet by mouth twice daily',
      'orderedDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
      'quantity' => 60,
      'expirationDate' => 'Wed, 15 Jul 2026 00:00:00 EDT',
      'prescriptionNumber' => '3636486',
      'prescriptionName' => 'METFORMIN HCL 500MG TAB',
      'dispensedDate' => 'Tue, 15 Jul 2025 00:00:00 EDT',
      'stationNumber' => '660',
      'cmopDivisionPhone' => '555-9876',
      'ndc' => '00093-1058-01',
      'dataSourceSystem' => 'VISTA',
      'trackingList' => {
        'tracking' => [
          {
            'trackingNumber' => '1Z999AA1012345675',
            'completeDateTime' => 'Wed, 16 Jul 2025 10:30:00 EDT',
            'carrier' => 'UPS',
            'ndc' => '00093-1058-01',
            'othersInSamePackage' => true
          },
          {
            'trackingNumber' => '1Z999AA1012345676',
            'completeDateTime' => 'Thu, 17 Jul 2025 14:15:00 EDT',
            'carrier' => 'UPS',
            'othersInSamePackage' => false
          }
        ]
      }
    }
  end

  describe '#parse' do
    context 'with valid Vista medication' do
      it 'returns a UnifiedHealthData::Prescription object' do
        result = subject.parse(base_vista_medication)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        expect(result.id).to eq('12345')
        expect(result.prescription_name).to eq('Test Medication')
        expect(result.source_ehr).to eq('vista')
      end

      it 'maps cmopDivisionPhone to cmop_division_phone' do
        result = subject.parse(base_vista_medication)

        expect(result.cmop_division_phone).to eq('555-1234')
      end

      it 'maps dialCmopDivisionPhone field correctly' do
        result = subject.parse(base_vista_medication)

        expect(result.dial_cmop_division_phone).to eq('555-DIAL-TEST')
      end

      it 'uses facilityName when facilityApiName is not present' do
        result = subject.parse(base_vista_medication)

        expect(result.facility_name).to eq('Test Facility')
      end
    end

    context 'with facilityApiName field' do
      let(:medication_with_api_name) do
        base_vista_medication.merge('facilityApiName' => 'API Facility Name')
      end

      it 'uses facilityApiName when present' do
        result = subject.parse(medication_with_api_name)

        expect(result.facility_name).to eq('API Facility Name')
      end

      it 'falls back to facilityName when facilityApiName is empty string' do
        medication_with_empty_api_name = base_vista_medication.merge('facilityApiName' => '')
        result = subject.parse(medication_with_empty_api_name)

        expect(result.facility_name).to eq('Test Facility')
      end

      it 'falls back to facilityName when facilityApiName is nil' do
        medication_with_nil_api_name = base_vista_medication.merge('facilityApiName' => nil)
        result = subject.parse(medication_with_nil_api_name)

        expect(result.facility_name).to eq('Test Facility')
      end
    end

    context 'with disclaimer field' do
      let(:medication_with_disclaimer) do
        base_vista_medication.merge('disclaimer' => 'Test disclaimer text')
      end

      it 'extracts the disclaimer field' do
        result = subject.parse(medication_with_disclaimer)

        expect(result.disclaimer).to eq('Test disclaimer text')
      end
    end

    context 'without disclaimer field' do
      it 'sets disclaimer to nil' do
        result = subject.parse(base_vista_medication)

        expect(result.disclaimer).to be_nil
      end
    end

    context 'with indication for use' do
      let(:vista_medication_with_indication) do
        base_vista_medication.merge('indicationForUse' => 'For blood pressure management')
      end

      it 'extracts the indication for use field' do
        result = subject.parse(vista_medication_with_indication)

        expect(result.indication_for_use).to eq('For blood pressure management')
      end
    end

    context 'without indication for use' do
      it 'sets indication_for_use to nil when not provided' do
        result = subject.parse(base_vista_medication)

        expect(result.indication_for_use).to be_nil
      end
    end

    context 'with disp_status field' do
      let(:vista_medication_with_disp_status) do
        base_vista_medication.merge('dispStatus' => 'Active: Refill in Process')
      end

      it 'extracts the disp_status field' do
        result = subject.parse(vista_medication_with_disp_status)

        expect(result.disp_status).to eq('Active: Refill in Process')
      end
    end

    context 'without disp_status field' do
      it 'sets disp_status to nil when not provided' do
        result = subject.parse(base_vista_medication)

        expect(result.disp_status).to be_nil
      end
    end

    context 'with isRenewable computation' do
      it 'returns true for Active status with zero refills remaining' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Active',
          'refillRemaining' => 0,
          'prescriptionSource' => 'RX',
          'isRenewable' => false
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be true
      end

      it 'returns false for Active status with refills remaining' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Active',
          'refillRemaining' => 3,
          'prescriptionSource' => 'RX',
          'isRenewable' => true
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end

      it 'returns false for Active status with nil refillRemaining' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Active',
          'refillRemaining' => nil,
          'prescriptionSource' => 'RX'
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end

      it 'returns true for Expired status within 120-day window' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Expired',
          'expirationDate' => 90.days.ago.utc.strftime('%a, %d %b %Y %H:%M:%S %Z'),
          'prescriptionSource' => 'RX'
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be true
      end

      it 'returns false for Expired status beyond 120-day window' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Expired',
          'expirationDate' => 121.days.ago.utc.strftime('%a, %d %b %Y %H:%M:%S %Z'),
          'prescriptionSource' => 'RX'
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end

      it 'returns true for Expired status at exactly 120-day boundary' do
        travel_to Time.zone.parse('2026-01-15T12:00:00Z') do
          medication = base_vista_medication.merge(
            'dispStatus' => 'Expired',
            'expirationDate' => 'Wed, 17 Sep 2025 12:00:00 UTC',
            'prescriptionSource' => 'RX'
          )
          result = subject.parse(medication)
          expect(result.is_renewable).to be true
        end
      end

      it 'returns false for Discontinued status regardless of upstream isRenewable' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Discontinued',
          'refillRemaining' => 0,
          'prescriptionSource' => 'RX',
          'isRenewable' => true
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end

      %w[Hold Suspended].each do |status|
        it "returns false for #{status} status" do
          medication = base_vista_medication.merge(
            'dispStatus' => status,
            'refillRemaining' => 0,
            'prescriptionSource' => 'RX'
          )
          result = subject.parse(medication)
          expect(result.is_renewable).to be false
        end
      end

      it 'returns false for Non-VA prescriptions' do
        medication = base_vista_medication.merge(
          'dispStatus' => 'Active',
          'refillRemaining' => 0,
          'prescriptionSource' => 'NV'
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end

      it 'returns false when dispStatus is nil' do
        medication = base_vista_medication.merge(
          'dispStatus' => nil,
          'refillRemaining' => 0,
          'prescriptionSource' => 'RX'
        )
        result = subject.parse(medication)
        expect(result.is_renewable).to be false
      end
    end

    context 'when medication includes RFC1123 date fields' do
      it 'converts non-expiration dates to ISO 8601 strings' do
        result = subject.parse(vista_medication_with_tracking)

        expect(result.refill_submit_date).to be_nil
        expect(result.refill_date).to eq('2025-07-14T04:00:00.000Z')
        expect(result.ordered_date).to eq('2025-07-14T04:00:00.000Z')
        expect(result.dispensed_date).to eq('2025-07-15T04:00:00.000Z')
      end

      it 'normalizes expiration_date to noon UTC of the Eastern calendar date' do
        result = subject.parse(vista_medication_with_tracking)

        # 'Wed, 15 Jul 2026 00:00:00 EDT' → Jul 15 in Eastern → noon UTC Jul 15
        expect(result.expiration_date).to eq('2026-07-15T12:00:00.000Z')
      end
    end

    context 'with nil medication' do
      it 'returns nil' do
        expect(subject.parse(nil)).to be_nil
      end
    end

    context 'with medication missing prescriptionId' do
      let(:medication_without_id) { base_vista_medication.except('prescriptionId') }

      it 'returns nil' do
        expect(subject.parse(medication_without_id)).to be_nil
      end
    end

    context 'when parsing raises an error' do
      let(:adapter_with_error) do
        adapter = described_class.new
        allow(adapter).to receive(:build_core_attributes).and_raise(StandardError, 'Test error')
        adapter
      end

      before do
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and returns nil' do
        result = adapter_with_error.parse(base_vista_medication)

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with('Error parsing VistA prescription: Test error')
      end
    end

    context 'with cmopNdcNumber field' do
      it 'sets cmop_ndc_number to nil when not present in Vista data' do
        result = subject.parse(base_vista_medication)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        expect(result.cmop_ndc_number).to be_nil
      end

      it 'maps cmopNdcNumber from Vista data when present' do
        medication_with_ndc = base_vista_medication.merge('cmopNdcNumber' => '00093721410')
        result = subject.parse(medication_with_ndc)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        expect(result.cmop_ndc_number).to eq('00093721410')
      end
    end

    context 'with sorted_dispensed_date extraction' do
      it 'returns the most recent dispensed_date from dispenses' do
        medication = base_vista_medication.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              { 'dispensedDate' => 'Thu, 10 Jul 2025 00:00:00 EDT' },
              { 'dispensedDate' => 'Sun, 20 Jul 2025 00:00:00 EDT' },
              { 'dispensedDate' => 'Tue, 15 Jul 2025 00:00:00 EDT' }
            ]
          }
        )
        result = subject.parse(medication)
        expect(result.sorted_dispensed_date).to eq('2025-07-20')
      end

      it 'falls back to top-level dispensedDate when no dispenses exist' do
        medication = base_vista_medication.merge(
          'dispensedDate' => 'Wed, 01 Jun 2025 00:00:00 EDT'
        )
        result = subject.parse(medication)
        expect(result.sorted_dispensed_date).to eq('2025-06-01')
      end

      it 'returns nil when no dispenses and no dispensedDate' do
        result = subject.parse(base_vista_medication)
        expect(result.sorted_dispensed_date).to be_nil
      end

      it 'ignores invalid dispensedDate strings and returns the max valid date' do
        medication = base_vista_medication.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              { 'dispensedDate' => 'Thu, 10 Jul 2025 00:00:00 EDT' },
              { 'dispensedDate' => 'not-a-valid-date' },
              { 'dispensedDate' => 'Sun, 20 Jul 2025 00:00:00 EDT' }
            ]
          }
        )
        result = subject.parse(medication)
        expect(result.sorted_dispensed_date).to eq('2025-07-20')
      end

      it 'returns nil when all dispensedDate strings are invalid' do
        medication = base_vista_medication.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              { 'dispensedDate' => 'not-a-valid-date' },
              { 'dispensedDate' => 'also-not-a-valid-date' }
            ]
          },
          'dispensedDate' => 'still-not-a-valid-date'
        )
        result = subject.parse(medication)
        expect(result.sorted_dispensed_date).to be_nil
      end
    end
  end

  describe '#build_tracking_information' do
    context 'with trackingList (current format)' do
      let(:medication_with_tracking) do
        base_vista_medication.merge(
          'isTrackable' => true,
          'ndc' => '12345-678-90',
          'trackingList' => {
            'tracking' => [
              {
                'trackingNumber' => '1Z999AA1012345675',
                'completeDateTime' => 'Wed, 07 Sep 2016 00:00:00 EDT',
                'carrier' => 'UPS',
                'ndc' => '99999-111-22',
                'othersInSamePackage' => true
              }
            ]
          }
        )
      end

      it 'returns tracking information with all fields' do
        result = subject.send(:build_tracking_information, medication_with_tracking)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        tracking = result.first
        expect(tracking).to include(
          prescription_name: 'Test Medication',
          prescription_number: 'RX123',
          ndc_number: '99999-111-22',
          prescription_id: '12345',
          tracking_number: '1Z999AA1012345675',
          complete_date_time: '2016-09-07T04:00:00.000Z',
          carrier: 'UPS',
          others_in_same_package: true
        )
      end

      it 'sets is_trackable to true when tracking data exists' do
        result = subject.parse(medication_with_tracking)
        expect(result.is_trackable).to be(true)
        expect(result.tracking.length).to eq(1)
      end
    end

    context 'with multiple tracking entries' do
      let(:medication_multiple_tracking) do
        base_vista_medication.merge(
          'isTrackable' => true,
          'trackingList' => {
            'tracking' => [
              {
                'trackingNumber' => 'TRACK001',
                'completeDateTime' => 'Mon, 05 Sep 2016 08:00:00 EDT',
                'carrier' => 'USPS',
                'othersInSamePackage' => false
              },
              {
                'trackingNumber' => 'TRACK002',
                'completeDateTime' => 'Tue, 06 Sep 2016 10:30:00 EDT',
                'carrier' => 'FedEx',
                'othersInSamePackage' => true
              }
            ]
          }
        )
      end

      it 'returns tracking information for all entries' do
        result = subject.send(:build_tracking_information, medication_multiple_tracking)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        expect(result.map { |t| t[:tracking_number] }).to contain_exactly('TRACK001', 'TRACK002')
        expect(result.map { |t| t[:carrier] }).to contain_exactly('USPS', 'FedEx')
      end
    end

    context 'with no tracking data' do
      it 'returns empty array when trackingList is not present' do
        result = subject.send(:build_tracking_information, base_vista_medication)
        expect(result).to eq([])
      end

      it 'returns empty array when trackingList has empty tracking array' do
        medication_empty_tracking = base_vista_medication.merge('trackingList' => { 'tracking' => [] })
        result = subject.send(:build_tracking_information, medication_empty_tracking)
        expect(result).to eq([])
      end

      it 'sets is_trackable to false when no tracking data exists' do
        result = subject.parse(base_vista_medication)
        expect(result.is_trackable).to be(false)
        expect(result.tracking).to eq([])
      end
    end

    context 'with invalid tracking format' do
      it 'returns empty array when trackingList is not a hash' do
        medication = base_vista_medication.merge('trackingList' => 'not-a-hash')
        result = subject.send(:build_tracking_information, medication)
        expect(result).to eq([])
      end

      it 'returns empty array when trackingList.tracking is not an array' do
        medication = base_vista_medication.merge('trackingList' => { 'tracking' => 'bad' })
        result = subject.send(:build_tracking_information, medication)
        expect(result).to eq([])
      end
    end

    context 'with isTrackable field' do
      it 'uses isTrackable field from Vista data when true' do
        medication_trackable_no_data = base_vista_medication.merge('isTrackable' => true)
        result = subject.parse(medication_trackable_no_data)
        expect(result.is_trackable).to be(true)
        expect(result.tracking).to eq([])
      end

      it 'uses isTrackable field from Vista data when false' do
        medication_not_trackable_with_data = base_vista_medication.merge(
          'isTrackable' => false,
          'trackingList' => {
            'tracking' => [
              {
                'trackingNumber' => '1Z999AA1012345675',
                'completeDateTime' => 'Wed, 07 Sep 2016 00:00:00 EDT',
                'carrier' => 'UPS'
              }
            ]
          }
        )
        result = subject.parse(medication_not_trackable_with_data)
        expect(result.is_trackable).to be(false)
        expect(result.tracking.length).to eq(1)
      end

      it 'defaults to false when isTrackable is nil' do
        medication_nil_trackable = base_vista_medication.except('isTrackable')
        result = subject.parse(medication_nil_trackable)
        expect(result.is_trackable).to be(false)
      end
    end
  end

  describe '#format_shipped_date' do
    context 'with valid Vista date format' do
      it 'converts Vista date to ISO 8601 UTC format' do
        date_string = 'Wed, 07 Sep 2016 00:00:00 EDT'
        result = subject.send(:format_shipped_date, date_string)
        expect(result).to eq('2016-09-07T04:00:00.000Z')
      end
    end

    context 'with different timezone' do
      it 'converts PST date to ISO 8601 UTC format' do
        date_string = 'Mon, 15 Jan 2024 15:30:00 PST'
        result = subject.send(:format_shipped_date, date_string)
        expect(result).to eq('2024-01-15T23:30:00.000Z')
      end
    end

    context 'with blank date string' do
      it 'returns nil for nil date' do
        result = subject.send(:format_shipped_date, nil)
        expect(result).to be_nil
      end

      it 'returns nil for empty date' do
        result = subject.send(:format_shipped_date, '')
        expect(result).to be_nil
      end

      it 'returns nil for whitespace-only date' do
        result = subject.send(:format_shipped_date, '   ')
        expect(result).to be_nil
      end
    end

    context 'with invalid date format' do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs warning and returns original string for invalid format' do
        invalid_date = 'invalid-date-format'
        result = subject.send(:format_shipped_date, invalid_date)

        expect(result).to eq(invalid_date)
        expect(Rails.logger).to have_received(:warn).with(
          "Failed to parse shipped_date 'invalid-date-format': no time information in \"invalid-date-format\""
        )
      end
    end
  end

  describe '#build_dispenses_information' do
    context 'with rxRFRecords present' do
      let(:medication_with_dispenses) do
        base_vista_medication.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              {
                'id' => 'dispense-1',
                'refillStatus' => 'dispensed',
                'dispensedDate' => 'Sat, 12 Jul 2025 00:00:00 EDT',
                'refillDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
                'refillSubmitDate' => 'Sun, 13 Jul 2025 00:00:00 EDT',
                'facilityName' => 'Salt Lake City VAMC',
                'sig' => 'Take one tablet by mouth twice daily',
                'quantity' => 60,
                'prescriptionName' => 'METFORMIN HCL 500MG TAB',
                'prescriptionNumber' => 'RX123456',
                'cmopDivisionPhone' => '555-1234',
                'cmopNdcNumber' => '00093-1058-01',
                'remarks' => 'Test remarks',
                'dialCmopDivisionPhone' => '5551234',
                'disclaimer' => 'Test disclaimer'
              },
              {
                'id' => 'dispense-2',
                'refillStatus' => 'dispensed',
                'refillDate' => 'Tue, 15 Jul 2025 00:00:00 EDT',
                'facilityName' => 'Salt Lake City VAMC',
                'sig' => 'Take one tablet by mouth twice daily',
                'quantity' => 60,
                'prescriptionName' => 'METFORMIN HCL 500MG TAB'
              }
            ]
          }
        )
      end

      it 'returns dispenses information with all fields' do
        result = subject.send(:build_dispenses_information, medication_with_dispenses)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        first_dispense = result.first
        expect(first_dispense).to include(
          status: 'dispensed',
          dispensed_date: '2025-07-12T04:00:00.000Z',
          refill_date: '2025-07-14T04:00:00.000Z',
          refill_submit_date: '2025-07-13T04:00:00.000Z',
          facility_name: 'Salt Lake City VAMC',
          instructions: 'Take one tablet by mouth twice daily',
          quantity: 60,
          prescription_name: 'METFORMIN HCL 500MG TAB',
          id: 'dispense-1',
          prescription_number: 'RX123456',
          cmop_division_phone: '555-1234',
          cmop_ndc_number: '00093-1058-01',
          remarks: 'Test remarks',
          dial_cmop_division_phone: '5551234',
          disclaimer: 'Test disclaimer'
        )

        second_dispense = result.second
        expect(second_dispense).to include(
          status: 'dispensed',
          refill_date: '2025-07-15T04:00:00.000Z',
          facility_name: 'Salt Lake City VAMC',
          instructions: 'Take one tablet by mouth twice daily',
          quantity: 60,
          prescription_name: 'METFORMIN HCL 500MG TAB',
          id: 'dispense-2'
        )
        # Verify new fields default to nil when not present
        expect(second_dispense[:dispensed_date]).to be_nil
        expect(second_dispense[:refill_submit_date]).to be_nil
        expect(second_dispense[:prescription_number]).to be_nil
        expect(second_dispense[:cmop_division_phone]).to be_nil
        expect(second_dispense[:cmop_ndc_number]).to be_nil
        expect(second_dispense[:remarks]).to be_nil
        expect(second_dispense[:dial_cmop_division_phone]).to be_nil
        expect(second_dispense[:disclaimer]).to be_nil
      end

      it 'includes dispenses in parsed prescription' do
        result = subject.parse(medication_with_dispenses)
        expect(result.dispenses.length).to eq(2)
        expect(result.dispenses.first[:status]).to eq('dispensed')
      end
    end

    context 'with no rxRFRecords' do
      it 'returns empty array when rxRFRecords is nil' do
        result = subject.send(:build_dispenses_information, base_vista_medication)
        expect(result).to eq([])
      end

      it 'returns empty array when rxRFRecords.rfRecord is empty array' do
        medication_empty_dispenses = base_vista_medication.merge('rxRFRecords' => { 'rfRecord' => [] })
        result = subject.send(:build_dispenses_information, medication_empty_dispenses)
        expect(result).to eq([])
      end

      it 'includes empty dispenses array in parsed prescription' do
        result = subject.parse(base_vista_medication)
        expect(result.dispenses).to eq([])
      end
    end

    context 'with invalid rxRFRecords format' do
      let(:medication_invalid_dispenses) do
        base_vista_medication.merge('rxRFRecords' => { 'rfRecord' => 'not-an-array' })
      end

      it 'returns empty array when rfRecord is not an array' do
        result = subject.send(:build_dispenses_information, medication_invalid_dispenses)
        expect(result).to eq([])
      end
    end

    context 'with non-hash elements in rfRecord' do
      let(:medication_with_invalid_records) do
        base_vista_medication.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              {
                'id' => 'valid-1',
                'refillStatus' => 'dispensed',
                'refillDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
                'facilityName' => 'Test Facility',
                'sig' => 'Take as directed',
                'quantity' => 30,
                'prescriptionName' => 'Test Med'
              },
              'invalid-string-element',
              nil,
              123,
              {
                'id' => 'valid-2',
                'refillStatus' => 'dispensed',
                'refillDate' => 'Tue, 15 Jul 2025 00:00:00 EDT',
                'facilityName' => 'Test Facility',
                'sig' => 'Take as directed',
                'quantity' => 30,
                'prescriptionName' => 'Test Med'
              }
            ]
          }
        )
      end

      it 'filters out non-hash elements and only returns valid dispenses' do
        result = subject.send(:build_dispenses_information, medication_with_invalid_records)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result.first[:id]).to eq('valid-1')
        expect(result.second[:id]).to eq('valid-2')
      end
    end
  end

  describe 'Vista prescription with tracking integration' do
    let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
    let(:vista_trackable_response) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_medication_with_tracking]
          }
        },
        'oracle-health' => nil
      }
    end

    it 'parses Vista prescription with complete tracking information' do
      adapter = UnifiedHealthData::Adapters::PrescriptionsAdapter.new(user)
      result = adapter.parse(vista_trackable_response)
      prescriptions = result[:prescriptions]

      expect(prescriptions.size).to eq(1)
      prescription = prescriptions.first

      expect(prescription.prescription_id).to eq('28148666')
      expect(prescription.prescription_name).to eq('METFORMIN HCL 500MG TAB')
      expect(prescription.is_trackable).to be(true)
      expect(prescription.tracking.size).to eq(2)

      # Check first tracking entry
      first_tracking = prescription.tracking.first
      expect(first_tracking[:tracking_number]).to eq('1Z999AA1012345675')
      expect(first_tracking[:carrier]).to eq('UPS')
      expect(first_tracking[:complete_date_time]).to eq('2025-07-16T14:30:00.000Z')
      expect(first_tracking[:others_in_same_package]).to be(true)

      # Check second tracking entry
      second_tracking = prescription.tracking.second
      expect(second_tracking[:tracking_number]).to eq('1Z999AA1012345676')
      expect(second_tracking[:carrier]).to eq('UPS')
      expect(second_tracking[:complete_date_time]).to eq('2025-07-17T18:15:00.000Z')
      expect(second_tracking[:others_in_same_package]).to be(false)
    end
  end

  describe 'is_renewal_flow_enabled' do
    it 'is always false for VistA prescriptions' do
      medication = base_vista_medication.merge(
        'dispStatus' => 'Active',
        'refillRemaining' => 0,
        'prescriptionSource' => 'RX'
      )
      result = subject.parse(medication)
      expect(result.is_renewal_flow_enabled).to be false
    end

    it 'is false even when is_renewable is true' do
      medication = base_vista_medication.merge(
        'dispStatus' => 'Active',
        'refillRemaining' => 0,
        'prescriptionSource' => 'RX',
        'isRenewable' => false
      )
      result = subject.parse(medication)
      expect(result.is_renewable).to be true
      expect(result.is_renewal_flow_enabled).to be false
    end
  end
end
