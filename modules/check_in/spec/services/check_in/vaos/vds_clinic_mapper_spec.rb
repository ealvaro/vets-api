# frozen_string_literal: true

require 'rails_helper'

describe CheckIn::VAOS::VdsClinicMapper do
  let(:vds_clinics) do
    [
      {
        clinicIen: '1081',
        name: 'CHS NEUROSURGERY VARMA',
        friendlyName: 'CHS NEUROSURGERY VARMA',
        physicalLocation: '1ST FL SPECIALTY MODULE 2'
      },
      {
        clinicIen: '6',
        name: 'OTHER CLINIC',
        friendlyName: 'OTHER CLINIC',
        physicalLocation: '2ND FL'
      }
    ]
  end

  describe '.find_by_clinic_ien' do
    it 'finds clinic by string IEN' do
      clinic = described_class.find_by_clinic_ien(vds_clinics, '1081')
      expect(clinic[:clinicIen]).to eq('1081')
    end

    it 'finds clinic when IEN is passed as integer' do
      clinic = described_class.find_by_clinic_ien(vds_clinics, 1081)
      expect(clinic[:clinicIen]).to eq('1081')
    end

    it 'returns nil when clinic is missing' do
      expect(described_class.find_by_clinic_ien(vds_clinics, '9999')).to be_nil
    end

    it 'returns nil when list is blank' do
      expect(described_class.find_by_clinic_ien([], '1081')).to be_nil
    end
  end

  describe '.to_clinic_info' do
    it 'maps VDS fields to MFS data shape' do
      clinic = vds_clinics.first
      result = described_class.to_clinic_info(clinic)

      expect(result).to eq(
        {
          data: {
            clinicId: '1081',
            serviceName: 'CHS NEUROSURGERY VARMA',
            friendlyName: 'CHS NEUROSURGERY VARMA',
            physicalLocation: '1ST FL SPECIALTY MODULE 2'
          }
        }.with_indifferent_access
      )
    end

    it 'does not use internal name for friendlyName when friendlyName is absent' do
      clinic = {
        clinicIen: '1081',
        name: 'INTERNAL NAME',
        physicalLocation: '1ST FL'
      }
      result = described_class.to_clinic_info(clinic)

      expect(result[:data][:friendlyName]).to be_nil
      expect(result[:data][:serviceName]).to eq('INTERNAL NAME')
    end

    it 'maps patientFriendlyName when friendlyName is absent' do
      clinic = {
        clinicIen: '1081',
        name: 'FTC AMPUTATION',
        patientFriendlyName: 'Friendly Name FTC Amputation'
      }
      result = described_class.to_clinic_info(clinic)

      expect(result[:data][:friendlyName]).to eq('Friendly Name FTC Amputation')
      expect(result[:data][:serviceName]).to eq('FTC AMPUTATION')
    end

    it 'prefers friendlyName over patientFriendlyName when both are present' do
      clinic = {
        clinicIen: '1081',
        name: 'FTC AMPUTATION',
        friendlyName: 'Migration guide name',
        patientFriendlyName: 'Legacy patient name'
      }
      result = described_class.to_clinic_info(clinic)

      expect(result[:data][:friendlyName]).to eq('Migration guide name')
    end
  end
end
