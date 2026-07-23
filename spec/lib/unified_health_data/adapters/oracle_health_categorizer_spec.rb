# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/oracle_health_categorizer'

describe UnifiedHealthData::Adapters::OracleHealthCategorizer do
  include FhirResourceBuilder

  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::OracleHealthCategorizer
    end
  end

  describe '#categorize_medication' do
    context 'with VA Prescription' do
      it 'returns :va_prescription for valid VA prescription' do
        resource = fhir_resource(source: 'VA')
        expect(subject.categorize_medication(resource)).to eq(:va_prescription)
      end

      it 'handles case-insensitive category codes' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'COMMUNITY' }] },
            { 'coding' => [{ 'code' => 'Discharge' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:va_prescription)
      end

      it 'returns :uncategorized when reportedBoolean is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => true,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'discharge' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized when intent is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'plan',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'discharge' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized with extra category codes' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'discharge' }] },
            { 'coding' => [{ 'code' => 'extra' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized with missing category codes' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end
    end

    context 'with Documented/Non-VA Medication' do
      it 'returns :documented_non_va for valid non-VA medication' do
        resource = fhir_resource(source: 'NV')
        expect(subject.categorize_medication(resource)).to eq(:documented_non_va)
      end

      it 'returns :uncategorized when reportedBoolean is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'plan',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'patientspecified' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized when intent is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => true,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'patientspecified' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end
    end

    context 'with Clinic Administered Medication' do
      it 'returns :clinic_administered for valid clinic administered medication' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'outpatient' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:clinic_administered)
      end

      it 'returns :uncategorized when reportedBoolean is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => true,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'outpatient' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized when intent is wrong' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'plan',
          'category' => [
            { 'coding' => [{ 'code' => 'outpatient' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end
    end

    context 'with Pharmacy Charges' do
      it 'returns :pharmacy_charges for charge-only category' do
        resource = base_fhir_resource.merge(
          'category' => [
            { 'coding' => [{ 'code' => 'charge-only' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:pharmacy_charges)
      end

      it 'ignores reportedBoolean and intent for charge-only' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => true,
          'intent' => 'plan',
          'category' => [
            { 'coding' => [{ 'code' => 'charge-only' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:pharmacy_charges)
      end
    end

    context 'with Inpatient Medication' do
      it 'returns :inpatient for inpatient category' do
        resource = base_fhir_resource.merge(
          'category' => [
            { 'coding' => [{ 'code' => 'inpatient' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:inpatient)
      end

      it 'ignores reportedBoolean and intent for inpatient' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'inpatient' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:inpatient)
      end
    end

    context 'with Uncategorized medications' do
      it 'returns :uncategorized for missing category' do
        expect(subject.categorize_medication(base_fhir_resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized for empty category array' do
        resource = base_fhir_resource.merge('category' => [])
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized for category with no coding' do
        resource = base_fhir_resource.merge(
          'category' => [
            { 'text' => 'Inpatient' }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end

      it 'returns :uncategorized for nil resource' do
        expect(subject.categorize_medication(nil)).to eq(:uncategorized)
      end

      it 'returns :uncategorized for unknown category code' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'unknown-category' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:uncategorized)
      end
    end

    context 'with multiple category codes' do
      it 'handles normalized (lowercase, sorted) category codes' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'Discharge' }] },
            { 'coding' => [{ 'code' => 'COMMUNITY' }] }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:va_prescription)
      end

      it 'extracts codes from multiple codings within one category' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            {
              'coding' => [
                { 'code' => 'community' },
                { 'code' => 'discharge' }
              ]
            }
          ]
        )
        expect(subject.categorize_medication(resource)).to eq(:va_prescription)
      end
    end
  end

  describe '#non_va_med?' do
    context 'when medication is VA prescription' do
      it 'returns false' do
        resource = fhir_resource(source: 'VA')
        expect(subject.non_va_med?(resource)).to be false
      end
    end

    context 'when medication is documented/non-VA' do
      it 'returns true' do
        resource = fhir_resource(source: 'NV')
        expect(subject.non_va_med?(resource)).to be true
      end
    end

    context 'when medication is clinic administered' do
      it 'returns true' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'outpatient' }] }
          ]
        )
        expect(subject.non_va_med?(resource)).to be true
      end
    end

    context 'when medication is pharmacy charges' do
      it 'returns true' do
        resource = base_fhir_resource.merge(
          'category' => [
            { 'coding' => [{ 'code' => 'charge-only' }] }
          ]
        )
        expect(subject.non_va_med?(resource)).to be true
      end
    end

    context 'when medication is inpatient' do
      it 'returns true' do
        resource = base_fhir_resource.merge(
          'category' => [
            { 'coding' => [{ 'code' => 'inpatient' }] }
          ]
        )
        expect(subject.non_va_med?(resource)).to be true
      end
    end

    context 'when medication is uncategorized' do
      it 'returns true for resource with no category' do
        expect(subject.non_va_med?(base_fhir_resource)).to be true
      end

      it 'returns true for partial match missing required fields' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => true,
          'intent' => 'order',
          'category' => [
            { 'coding' => [{ 'code' => 'community' }] },
            { 'coding' => [{ 'code' => 'patientspecified' }] }
          ]
        )
        expect(subject.non_va_med?(resource)).to be true
      end

      it 'returns true for nil resource' do
        expect(subject.non_va_med?(nil)).to be true
      end
    end
  end
end
