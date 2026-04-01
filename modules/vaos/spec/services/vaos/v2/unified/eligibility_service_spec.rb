# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EligibilityService do
  let(:user) { build(:user, :vaos) }
  let(:service) { described_class.new(user) }

  let(:patients_service) { instance_double(VAOS::V2::PatientsService) }

  before do
    allow(VAOS::V2::PatientsService).to receive(:new).and_return(patients_service)
  end

  def build_va_provider(location_id:)
    VAOS::V2::Unified::VAProvider.new(
      id: location_id,
      location_id:,
      name: "Test Facility #{location_id}"
    )
  end

  def eligibility_result(eligible:)
    OpenStruct.new(eligible:)
  end

  describe '#check_eligibility' do
    let(:va_provider) { build_va_provider(location_id: '983') }

    context 'when the patient is eligible for direct scheduling' do
      before do
        allow(patients_service).to receive(:get_patient_appointment_metadata)
          .with('primaryCare', '983', 'direct').and_return(eligibility_result(eligible: true))
      end

      it 'returns eligible with the mapped VAOS service type' do
        result = service.check_eligibility(va_provider, 'primaryCare')

        expect(result[:facility_id]).to eq('983')
        expect(result[:vaos_service_type]).to eq('primaryCare')
        expect(result[:direct_eligible]).to be true
      end

      it 'checks direct eligibility' do
        service.check_eligibility(va_provider, 'primaryCare')

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
        result = service.check_eligibility(va_provider, 'primaryCare')

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
        result = service.check_eligibility(va_provider, 'primaryCare')

        expect(result[:direct_eligible]).to be false
      end
    end

    context 'when the category of care is unmappable' do
      it 'returns nil for vaos_service_type and false for direct_eligible' do
        result = service.check_eligibility(va_provider, 'unknownServiceType')

        expect(result[:facility_id]).to eq('983')
        expect(result[:vaos_service_type]).to be_nil
        expect(result[:direct_eligible]).to be false
      end
    end
  end
end
