# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EligibilityService do
  let(:user) { build(:user, :vaos) }
  let(:service) { described_class.new(user) }

  let(:patients_service) { instance_double(VAOS::V2::PatientsService) }

  before do
    allow(VAOS::V2::PatientsService).to receive(:new).and_return(patients_service)
  end

  def eligibility_result(eligible:)
    OpenStruct.new(eligible:)
  end

  describe '#check_eligibility' do
    let(:facility_id) { '983' }

    context 'when the patient is eligible for direct scheduling' do
      before do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('primaryCare', '983', 'direct').and_return(eligibility_result(eligible: true))
      end

      it 'returns eligible with the passed-through VAOS service type' do
        result = service.check_eligibility(facility_id:, vaos_service_type: 'primaryCare')

        expect(result[:facility_id]).to eq('983')
        expect(result[:vaos_service_type]).to eq('primaryCare')
        expect(result[:direct_eligible]).to be true
      end

      it 'checks direct eligibility' do
        service.check_eligibility(facility_id:, vaos_service_type: 'primaryCare')

        expect(patients_service).to have_received(:get_patient_appointment_metadata)
          .with('primaryCare', '983', 'direct')
      end
    end

    context 'when the patient is ineligible for direct scheduling' do
      before do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('primaryCare', '983', 'direct').and_return(eligibility_result(eligible: false))
      end

      it 'returns direct as ineligible' do
        result = service.check_eligibility(facility_id:, vaos_service_type: 'primaryCare')

        expect(result[:direct_eligible]).to be false
      end
    end

    context 'when the direct eligibility check fails' do
      before do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('primaryCare', '983', 'direct')
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, detail: 'timeout'))
      end

      it 'marks direct as ineligible' do
        result = service.check_eligibility(facility_id:, vaos_service_type: 'primaryCare')

        expect(result[:direct_eligible]).to be false
      end
    end

    context 'when vaos_service_type is blank' do
      before do
        allow(StatsD).to receive(:increment)
        allow(patients_service).to receive(:get_patient_appointment_metadata)
      end

      it 'returns nil for vaos_service_type and false for direct_eligible' do
        result = service.check_eligibility(facility_id:, vaos_service_type: nil)

        expect(result[:facility_id]).to eq('983')
        expect(result[:vaos_service_type]).to be_nil
        expect(result[:direct_eligible]).to be false
      end

      it 'increments the unmappable_service_type counter' do
        service.check_eligibility(facility_id:, vaos_service_type: '')

        expect(StatsD).to have_received(:increment)
          .with('api.vaos.unified_eligibility.unmappable_service_type')
      end

      it 'does not call the upstream PatientsService' do
        service.check_eligibility(facility_id:, vaos_service_type: nil)

        expect(patients_service).not_to have_received(:get_patient_appointment_metadata)
      end
    end

    # Regression guard for the bug Copilot flagged: ProviderSearchService passes
    # an already-mapped VAOS service type (from CcraCategoryMapper) into here.
    # Mapping a SECOND time via ServiceTypeMapper.to_vaos would have returned
    # nil for VAOS-only identifiers like 'foodAndNutrition' or
    # 'clinicalPharmacyPrimaryCare', silently marking every facility ineligible.
    context 'with VAOS-only service types that are not Lighthouse keys' do
      it "passes 'foodAndNutrition' through to PatientsService unchanged" do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('foodAndNutrition', '983', 'direct').and_return(eligibility_result(eligible: true))

        result = service.check_eligibility(facility_id:, vaos_service_type: 'foodAndNutrition')

        expect(result[:vaos_service_type]).to eq('foodAndNutrition')
        expect(result[:direct_eligible]).to be true
        expect(patients_service).to have_received(:get_patient_appointment_metadata)
          .with('foodAndNutrition', '983', 'direct')
      end

      it "passes 'clinicalPharmacyPrimaryCare' through to PatientsService unchanged" do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('clinicalPharmacyPrimaryCare', '983', 'direct').and_return(eligibility_result(eligible: true))

        result = service.check_eligibility(facility_id:, vaos_service_type: 'clinicalPharmacyPrimaryCare')

        expect(result[:direct_eligible]).to be true
      end

      it "passes 'outpatientMentalHealth' through unchanged" do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('outpatientMentalHealth', '983', 'direct').and_return(eligibility_result(eligible: false))

        result = service.check_eligibility(facility_id:, vaos_service_type: 'outpatientMentalHealth')

        expect(result[:vaos_service_type]).to eq('outpatientMentalHealth')
        expect(result[:direct_eligible]).to be false
      end
    end
  end
end
