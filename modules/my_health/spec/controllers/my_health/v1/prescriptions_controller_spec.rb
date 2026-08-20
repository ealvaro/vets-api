# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MyHealth::V1::PrescriptionsController, type: :controller do
  let(:controller_instance) { described_class.new }

  def build_rx(attrs = {})
    defaults = {
      prescription_id: 1,
      prescription_number: '1234567',
      prescription_name: 'Medication A',
      station_number: '989',
      disp_status: 'Active',
      prescription_source: 'VA'
    }
    OpenStruct.new(defaults.merge(attrs))
  end

  describe '#count_recently_requested' do
    it 'counts prescriptions with Refill in Process status' do
      list = [
        build_rx(disp_status: 'Active: Refill in Process'),
        build_rx(disp_status: 'Active')
      ]
      expect(controller_instance.send(:count_recently_requested, list)).to eq(1)
    end

    it 'counts prescriptions with Submitted status' do
      list = [
        build_rx(disp_status: 'Active: Submitted'),
        build_rx(disp_status: 'Active')
      ]
      expect(controller_instance.send(:count_recently_requested, list)).to eq(1)
    end

    it 'counts both statuses' do
      list = [
        build_rx(disp_status: 'Active: Refill in Process'),
        build_rx(disp_status: 'Active: Submitted'),
        build_rx(disp_status: 'Active')
      ]
      expect(controller_instance.send(:count_recently_requested, list)).to eq(2)
    end

    it 'returns 0 when no matches' do
      list = [
        build_rx(disp_status: 'Active'),
        build_rx(disp_status: 'Expired')
      ]
      expect(controller_instance.send(:count_recently_requested, list)).to eq(0)
    end

    it 'returns 0 for empty list' do
      expect(controller_instance.send(:count_recently_requested, [])).to eq(0)
    end
  end

  describe '#count_active_medications' do
    it 'counts all active statuses' do
      list = [
        build_rx(disp_status: 'Active'),
        build_rx(disp_status: 'Active: Refill in Process'),
        build_rx(disp_status: 'Active: Non-VA'),
        build_rx(disp_status: 'Active: On Hold'),
        build_rx(disp_status: 'Active: Parked'),
        build_rx(disp_status: 'Active: Submitted'),
        build_rx(disp_status: 'Expired'),
        build_rx(disp_status: 'Discontinued')
      ]
      expect(controller_instance.send(:count_active_medications, list)).to eq(6)
    end

    it 'returns 0 when no active prescriptions' do
      list = [
        build_rx(disp_status: 'Expired'),
        build_rx(disp_status: 'Discontinued')
      ]
      expect(controller_instance.send(:count_active_medications, list)).to eq(0)
    end
  end

  describe '#count_non_active_medications' do
    it 'counts all non-active statuses' do
      list = [
        build_rx(disp_status: 'Discontinued'),
        build_rx(disp_status: 'Expired'),
        build_rx(disp_status: 'Transferred'),
        build_rx(disp_status: 'Unknown'),
        build_rx(disp_status: 'Active')
      ]
      expect(controller_instance.send(:count_non_active_medications, list)).to eq(4)
    end

    it 'returns 0 when no non-active prescriptions' do
      list = [build_rx(disp_status: 'Active')]
      expect(controller_instance.send(:count_non_active_medications, list)).to eq(0)
    end
  end

  describe '#sort_prescriptions_with_pd_at_top' do
    it 'places PD prescriptions before others' do
      prescriptions = [
        build_rx(prescription_source: 'VA', prescription_name: 'Med A'),
        build_rx(prescription_source: 'PD', prescription_name: 'Med B'),
        build_rx(prescription_source: 'NV', prescription_name: 'Med C'),
        build_rx(prescription_source: 'PD', prescription_name: 'Med D')
      ]
      result = controller_instance.send(:sort_prescriptions_with_pd_at_top, prescriptions)

      expect(result[0].prescription_source).to eq('PD')
      expect(result[1].prescription_source).to eq('PD')
      expect(result[2..].map(&:prescription_source)).not_to include('PD')
    end

    it 'returns a new array without modifying the original' do
      prescriptions = [
        build_rx(prescription_source: 'VA'),
        build_rx(prescription_source: 'PD')
      ]
      result = controller_instance.send(:sort_prescriptions_with_pd_at_top, prescriptions)
      expect(result.object_id).not_to eq(prescriptions.object_id)
      expect(prescriptions[0].prescription_source).to eq('VA')
    end

    it 'preserves relative order within PD and non-PD groups' do
      prescriptions = [
        build_rx(prescription_source: 'VA', prescription_name: 'A'),
        build_rx(prescription_source: 'PD', prescription_name: 'B'),
        build_rx(prescription_source: 'NV', prescription_name: 'C'),
        build_rx(prescription_source: 'PD', prescription_name: 'D'),
        build_rx(prescription_source: 'VA', prescription_name: 'E')
      ]
      result = controller_instance.send(:sort_prescriptions_with_pd_at_top, prescriptions)
      expect(result.map(&:prescription_name)).to eq(%w[B D A C E])
    end

    it 'handles empty array' do
      result = controller_instance.send(:sort_prescriptions_with_pd_at_top, [])
      expect(result).to be_empty
    end

    it 'handles array with no PD prescriptions' do
      prescriptions = [
        build_rx(prescription_source: 'VA'),
        build_rx(prescription_source: 'NV')
      ]
      result = controller_instance.send(:sort_prescriptions_with_pd_at_top, prescriptions)
      expect(result.map(&:prescription_source)).to eq(%w[VA NV])
    end
  end
end
