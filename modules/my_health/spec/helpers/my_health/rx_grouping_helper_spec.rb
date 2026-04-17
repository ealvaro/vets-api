# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MyHealth::RxGroupingHelper do
  let(:test_class) do
    Class.new do
      include MyHealth::RxGroupingHelper

      public :group_prescriptions
    end
  end

  let(:helper) { test_class.new }

  def build_rx(attrs = {})
    defaults = {
      prescription_id: 1,
      prescription_number: '1234567',
      prescription_name: 'Medication A',
      station_number: '989',
      grouped_medications: nil
    }
    OpenStruct.new(defaults.merge(attrs))
  end

  describe '#count_grouped_prescriptions' do
    context 'when prescriptions is nil' do
      it 'returns 0' do
        expect(helper.count_grouped_prescriptions(nil)).to eq(0)
      end
    end

    context 'when prescriptions is empty' do
      it 'returns 0' do
        expect(helper.count_grouped_prescriptions([])).to eq(0)
      end
    end

    context 'when prescriptions have no related prescriptions' do
      it 'counts each prescription individually' do
        prescriptions = [
          build_rx(prescription_number: '1234567', station_number: '989'),
          build_rx(prescription_number: '7654321', station_number: '989'),
          build_rx(prescription_number: '9999999', station_number: '989')
        ]
        expect(helper.count_grouped_prescriptions(prescriptions)).to eq(3)
      end
    end

    context 'when prescriptions have related prescriptions (letter suffixes)' do
      it 'counts grouped prescriptions as one' do
        prescriptions = [
          build_rx(prescription_number: '1234567', station_number: '989'),
          build_rx(prescription_number: '1234567A', station_number: '989'),
          build_rx(prescription_number: '1234567B', station_number: '989'),
          build_rx(prescription_number: '7654321', station_number: '989')
        ]
        expect(helper.count_grouped_prescriptions(prescriptions)).to eq(2)
      end
    end

    context 'when prescriptions have same base number but different stations' do
      it 'counts them as separate groups' do
        prescriptions = [
          build_rx(prescription_number: '1234567', station_number: '989'),
          build_rx(prescription_number: '1234567A', station_number: '456')
        ]
        expect(helper.count_grouped_prescriptions(prescriptions)).to eq(2)
      end
    end

    context 'with multiple prescription families' do
      it 'counts multiple groups correctly' do
        prescriptions = [
          build_rx(prescription_number: '1000000', station_number: '989'),
          build_rx(prescription_number: '1000000A', station_number: '989'),
          build_rx(prescription_number: '2000000', station_number: '989'),
          build_rx(prescription_number: '2000000A', station_number: '989'),
          build_rx(prescription_number: '3000000', station_number: '989')
        ]
        expect(helper.count_grouped_prescriptions(prescriptions)).to eq(3)
      end
    end

    context 'when input is not modified' do
      it 'does not modify the original array' do
        prescriptions = [
          build_rx(prescription_number: '1234567', station_number: '989'),
          build_rx(prescription_number: '1234567A', station_number: '989')
        ]
        original_length = prescriptions.length
        helper.count_grouped_prescriptions(prescriptions)
        expect(prescriptions.length).to eq(original_length)
      end
    end
  end

  describe '#select_related_rxs' do
    context 'when prescriptions share the same base number and station' do
      it 'returns all related prescriptions' do
        rx_base = build_rx(prescription_number: '1234567', station_number: '989')
        rx_a = build_rx(prescription_number: '1234567A', station_number: '989')
        rx_b = build_rx(prescription_number: '1234567B', station_number: '989')
        prescriptions = [rx_base, rx_a, rx_b]

        result = helper.send(:select_related_rxs, prescriptions, rx_base)
        expect(result).to contain_exactly(rx_base, rx_a, rx_b)
      end
    end

    context 'when a suffix prescription is the anchor' do
      it 'matches prescriptions with the same base number' do
        rx_base = build_rx(prescription_number: '1234567', station_number: '989')
        rx_a = build_rx(prescription_number: '1234567A', station_number: '989')
        prescriptions = [rx_base, rx_a]

        result = helper.send(:select_related_rxs, prescriptions, rx_a)
        expect(result).to contain_exactly(rx_base, rx_a)
      end
    end

    context 'when prescriptions have different base numbers' do
      it 'returns only the matching prescription' do
        rx1 = build_rx(prescription_number: '1234567', station_number: '989')
        rx2 = build_rx(prescription_number: '7654321', station_number: '989')
        prescriptions = [rx1, rx2]

        result = helper.send(:select_related_rxs, prescriptions, rx1)
        expect(result).to contain_exactly(rx1)
      end
    end

    context 'when prescriptions share a base number but have different stations' do
      it 'does not group them together' do
        rx1 = build_rx(prescription_number: '1234567', station_number: '989')
        rx2 = build_rx(prescription_number: '1234567A', station_number: '456')
        prescriptions = [rx1, rx2]

        result = helper.send(:select_related_rxs, prescriptions, rx1)
        expect(result).to contain_exactly(rx1)
      end
    end

    context 'when the list is empty' do
      it 'returns an empty array' do
        rx = build_rx(prescription_number: '1234567', station_number: '989')
        result = helper.send(:select_related_rxs, [], rx)
        expect(result).to be_empty
      end
    end
  end
end
