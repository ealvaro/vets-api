# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/medication_dispense_helpers'

describe UnifiedHealthData::Adapters::MedicationDispenseHelpers do
  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::MedicationDispenseHelpers
    end
  end

  describe '#extract_ndc_number' do
    it 'extracts NDC code from dispense medicationCodeableConcept' do
      dispense = {
        'medicationCodeableConcept' => {
          'coding' => [
            { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '12345-6789-01' }
          ]
        }
      }
      result = subject.extract_ndc_number(dispense)
      expect(result).to eq('12345-6789-01')
    end

    it 'returns nil when NDC coding not present' do
      dispense = {
        'medicationCodeableConcept' => {
          'coding' => [
            { 'system' => 'http://snomed.info/sct', 'code' => '123456' }
          ]
        }
      }
      result = subject.extract_ndc_number(dispense)
      expect(result).to be_nil
    end

    it 'returns nil when coding array is empty' do
      dispense = { 'medicationCodeableConcept' => { 'coding' => [] } }
      result = subject.extract_ndc_number(dispense)
      expect(result).to be_nil
    end

    it 'returns nil when medicationCodeableConcept is missing' do
      dispense = {}
      result = subject.extract_ndc_number(dispense)
      expect(result).to be_nil
    end
  end

  describe '#medication_dispenses' do
    it 'extracts MedicationDispense resources from contained array' do
      resource = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'id' => '1' },
          { 'resourceType' => 'Task', 'id' => '2' },
          { 'resourceType' => 'MedicationDispense', 'id' => '3' }
        ]
      }
      result = subject.medication_dispenses(resource)
      expect(result.length).to eq(2)
      expect(result.map { |d| d['id'] }).to contain_exactly('1', '3')
    end

    it 'returns empty array when no MedicationDispense resources exist' do
      resource = {
        'contained' => [
          { 'resourceType' => 'Task', 'id' => '1' },
          { 'resourceType' => 'Medication', 'id' => '2' }
        ]
      }
      result = subject.medication_dispenses(resource)
      expect(result).to eq([])
    end

    it 'returns empty array when contained is nil' do
      resource = {}
      result = subject.medication_dispenses(resource)
      expect(result).to eq([])
    end

    it 'returns empty array when contained is empty' do
      resource = { 'contained' => [] }
      result = subject.medication_dispenses(resource)
      expect(result).to eq([])
    end

    it 'handles resource with no contained key' do
      resource = { 'id' => '123' }
      result = subject.medication_dispenses(resource)
      expect(result).to eq([])
    end
  end

  describe '#find_most_recent_medication_dispense' do
    it 'returns the most recent dispense by whenHandedOver date' do
      medication_request = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => '2025-01-15T10:00:00Z', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => '2025-06-20T10:00:00Z', 'id' => '2' },
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => '2025-03-10T10:00:00Z', 'id' => '3' }
        ]
      }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result['id']).to eq('2')
    end

    it 'falls back to whenPrepared if whenHandedOver is missing' do
      medication_request = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'whenPrepared' => '2025-01-15T10:00:00Z', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'whenPrepared' => '2025-06-20T10:00:00Z', 'id' => '2' }
        ]
      }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result['id']).to eq('2')
    end

    it 'returns nil when no MedicationDispense resources exist' do
      medication_request = {
        'contained' => [
          { 'resourceType' => 'Task', 'id' => '1' }
        ]
      }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result).to be_nil
    end

    it 'returns nil when medication_request is nil' do
      result = subject.find_most_recent_medication_dispense(nil)
      expect(result).to be_nil
    end

    it 'returns nil when contained is empty array' do
      medication_request = { 'contained' => [] }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result).to be_nil
    end

    it 'handles dispenses without whenHandedOver or whenPrepared (uses epoch)' do
      medication_request = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => '2025-01-15T10:00:00Z', 'id' => '2' }
        ]
      }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result['id']).to eq('2')
    end

    it 'handles invalid date formats gracefully' do
      medication_request = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => 'invalid-date', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'whenHandedOver' => '2025-01-15T10:00:00Z', 'id' => '2' }
        ]
      }
      result = subject.find_most_recent_medication_dispense(medication_request)
      expect(result['id']).to eq('2')
    end
  end

  describe '#completed_dispense_exists?' do
    it 'returns true when a contained MedicationDispense has status completed' do
      resource = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'status' => 'in-progress', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'status' => 'completed', 'id' => '2' }
        ]
      }
      expect(subject.completed_dispense_exists?(resource)).to be true
    end

    it 'returns false when all dispenses have non-completed statuses' do
      resource = {
        'contained' => [
          { 'resourceType' => 'MedicationDispense', 'status' => 'entered-in-error', 'id' => '1' },
          { 'resourceType' => 'MedicationDispense', 'status' => 'in-progress', 'id' => '2' }
        ]
      }
      expect(subject.completed_dispense_exists?(resource)).to be false
    end

    it 'returns false when there are no MedicationDispense resources' do
      resource = { 'contained' => [{ 'resourceType' => 'Task', 'id' => '1' }] }
      expect(subject.completed_dispense_exists?(resource)).to be false
    end

    it 'returns false when contained is empty' do
      resource = { 'contained' => [] }
      expect(subject.completed_dispense_exists?(resource)).to be false
    end

    it 'returns false when resource has no contained key' do
      resource = {}
      expect(subject.completed_dispense_exists?(resource)).to be false
    end
  end

  describe '#build_instruction_text' do
    it 'builds instruction from timing, route, and dose' do
      instruction = {
        'timing' => { 'code' => { 'text' => 'Once daily' } },
        'route' => { 'text' => 'Oral' },
        'doseAndRate' => [
          { 'doseQuantity' => { 'value' => 10, 'unit' => 'mg' } }
        ]
      }
      result = subject.build_instruction_text(instruction)
      expect(result).to eq('Once daily Oral 10 mg')
    end

    it 'handles missing timing' do
      instruction = {
        'route' => { 'text' => 'Oral' },
        'doseAndRate' => [
          { 'doseQuantity' => { 'value' => 10, 'unit' => 'mg' } }
        ]
      }
      result = subject.build_instruction_text(instruction)
      expect(result).to eq('Oral 10 mg')
    end

    it 'handles missing route' do
      instruction = {
        'timing' => { 'code' => { 'text' => 'Once daily' } },
        'doseAndRate' => [
          { 'doseQuantity' => { 'value' => 10, 'unit' => 'mg' } }
        ]
      }
      result = subject.build_instruction_text(instruction)
      expect(result).to eq('Once daily 10 mg')
    end

    it 'handles missing doseAndRate' do
      instruction = {
        'timing' => { 'code' => { 'text' => 'Once daily' } },
        'route' => { 'text' => 'Oral' }
      }
      result = subject.build_instruction_text(instruction)
      expect(result).to eq('Once daily Oral')
    end

    it 'returns empty string for empty instruction' do
      instruction = {}
      result = subject.build_instruction_text(instruction)
      expect(result).to eq('')
    end
  end

  describe '#extract_sig_from_dispense' do
    it 'extracts and concatenates dosage instruction texts' do
      dispense = {
        'dosageInstruction' => [
          { 'text' => 'Take 1 tablet' },
          { 'text' => 'with food' }
        ]
      }
      result = subject.extract_sig_from_dispense(dispense)
      expect(result).to eq('Take 1 tablet with food')
    end

    it 'returns nil when dosageInstruction is empty' do
      dispense = { 'dosageInstruction' => [] }
      result = subject.extract_sig_from_dispense(dispense)
      expect(result).to be_nil
    end

    it 'returns nil when dosageInstruction is missing' do
      dispense = {}
      result = subject.extract_sig_from_dispense(dispense)
      expect(result).to be_nil
    end

    it 'filters out non-hash instructions' do
      dispense = {
        'dosageInstruction' => [
          { 'text' => 'Take 1 tablet' },
          'invalid instruction',
          { 'text' => 'twice daily' }
        ]
      }
      result = subject.extract_sig_from_dispense(dispense)
      expect(result).to eq('Take 1 tablet twice daily')
    end

    it 'filters out instructions without text' do
      dispense = {
        'dosageInstruction' => [
          { 'text' => 'Take 1 tablet' },
          { 'timing' => { 'code' => 'BID' } },
          { 'text' => 'twice daily' }
        ]
      }
      result = subject.extract_sig_from_dispense(dispense)
      expect(result).to eq('Take 1 tablet twice daily')
    end
  end

  describe '#parse_expiration_date_utc' do
    it 'parses valid ISO8601 date string to UTC time' do
      resource = {
        'dispenseRequest' => {
          'validityPeriod' => { 'end' => '2026-06-15T23:59:59Z' }
        }
      }
      result = subject.parse_expiration_date_utc(resource)
      expect(result).to be_a(Time)
      expect(result.utc?).to be true
      expect(result.year).to eq(2026)
      expect(result.month).to eq(6)
      expect(result.day).to eq(15)
    end

    it 'returns nil when validityPeriod end is missing' do
      resource = { 'dispenseRequest' => {} }
      result = subject.parse_expiration_date_utc(resource)
      expect(result).to be_nil
    end

    it 'returns nil when dispenseRequest is missing' do
      resource = {}
      result = subject.parse_expiration_date_utc(resource)
      expect(result).to be_nil
    end

    it 'returns nil and logs warning for invalid date format' do
      resource = {
        'id' => '12345',
        'dispenseRequest' => {
          'validityPeriod' => { 'end' => 'invalid-date' }
        }
      }
      expect(Rails.logger).to receive(:warn).with(/Invalid expiration date/)
      result = subject.parse_expiration_date_utc(resource)
      expect(result).to be_nil
    end
  end

  describe '#prescription_expired?' do
    it 'returns true when expiration date is in the past' do
      resource = {
        'dispenseRequest' => {
          'validityPeriod' => { 'end' => 30.days.ago.utc.iso8601 }
        }
      }
      expect(subject.prescription_expired?(resource)).to be true
    end

    it 'returns false when expiration date is in the future' do
      resource = {
        'dispenseRequest' => {
          'validityPeriod' => { 'end' => 30.days.from_now.utc.iso8601 }
        }
      }
      expect(subject.prescription_expired?(resource)).to be false
    end

    it 'returns false when expiration date is nil' do
      resource = { 'dispenseRequest' => {} }
      expect(subject.prescription_expired?(resource)).to be false
    end

    it 'returns false when expiration date is invalid' do
      resource = {
        'id' => '12345',
        'dispenseRequest' => {
          'validityPeriod' => { 'end' => 'invalid-date' }
        }
      }
      allow(Rails.logger).to receive(:warn)
      expect(subject.prescription_expired?(resource)).to be false
    end
  end
end
