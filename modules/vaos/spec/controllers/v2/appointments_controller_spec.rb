# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe VAOS::V2::AppointmentsController, type: :request do
  include ActiveSupport::Testing::TimeHelpers
  describe '#start_date' do
    context 'with an invalid date' do
      it 'throws an InvalidFieldValue exception' do
        subject.params = { start: 'not a date', end: '2022-09-21T00:00:00+00:00' }

        expect do
          subject.send(:start_date)
        end.to raise_error(Common::Exceptions::InvalidFieldValue)
      end
    end
  end

  describe '#end_date' do
    context 'with an invalid date' do
      it 'throws an InvalidFieldValue exception' do
        subject.params = { end: 'not a date', start: '2022-09-21T00:00:00+00:00' }

        expect do
          subject.send(:end_date)
        end.to raise_error(Common::Exceptions::InvalidFieldValue)
      end
    end
  end

  describe '#appointment_error_status' do
    let(:controller) { described_class.new }

    it 'returns :conflict for conflict error' do
      expect(controller.send(:appointment_error_status, 'conflict')).to eq(:conflict)
    end

    it 'returns :bad_request for bad-request error' do
      expect(controller.send(:appointment_error_status, 'bad-request')).to eq(:bad_request)
    end

    it 'returns :bad_gateway for internal-error error' do
      expect(controller.send(:appointment_error_status, 'internal-error')).to eq(:bad_gateway)
    end

    it 'returns :unprocessable_content for other errors' do
      expect(controller.send(:appointment_error_status, 'too-far-in-the-future')).to eq(:unprocessable_content)
      expect(controller.send(:appointment_error_status, 'already-canceled')).to eq(:unprocessable_content)
      expect(controller.send(:appointment_error_status, 'too-late-to-cancel')).to eq(:unprocessable_content)
      expect(controller.send(:appointment_error_status, 'unknown-error')).to eq(:unprocessable_content)
    end
  end

  describe '#appointment_facility_ids' do
    let(:controller) { described_class.new }

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_unique_user_metrics_logging_appt).and_return(true)
    end

    context 'when mhv_oh_unique_user_metrics_logging_appt feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_unique_user_metrics_logging_appt).and_return(false)
      end

      it 'returns nil regardless of appointments' do
        appointments = [
          { location_id: '983', future: true, past: false, pending: false, status: 'booked' },
          { location_id: '984', future: false, past: true, pending: false, status: 'booked' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to be_nil
      end
    end

    context 'when appointments are visible (pending or non-cancelled with date flags)' do
      it 'returns unique facility IDs from visible appointments' do
        appointments = [
          { location_id: '983', future: true, past: false, pending: false, status: 'booked' },
          { location_id: '984', future: false, past: true, pending: false, status: 'booked' },
          { location_id: '757', future: false, past: false, pending: true, status: 'proposed' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to contain_exactly('983', '984', '757')
      end

      it 'extracts 3-character station ID from sta6aid format' do
        appointments = [
          { location_id: '983GC', future: true, past: false, pending: false, status: 'booked' },
          { location_id: '984HK', future: false, past: true, pending: false, status: 'booked' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to contain_exactly('983', '984')
      end

      it 'returns unique facility IDs when duplicates exist' do
        appointments = [
          { location_id: '983', future: true, past: false, pending: false, status: 'booked' },
          { location_id: '983GC', future: false, past: true, pending: false, status: 'booked' },
          { location_id: '983HK', future: false, past: false, pending: true, status: 'proposed' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to eq(['983'])
      end
    end

    context 'when appointments are cancelled' do
      it 'excludes cancelled appointments even if they have date flags' do
        appointments = [
          { location_id: '983', future: true, past: false, pending: false, status: 'cancelled' },
          { location_id: '984', future: false, past: true, pending: false, status: 'cancelled' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to be_nil
      end

      it 'includes pending appointments even if status is cancelled' do
        # Pending appointments are always visible regardless of status
        appointments = [
          { location_id: '983', future: false, past: false, pending: true, status: 'cancelled' },
          { location_id: '984', future: true, past: false, pending: false, status: 'cancelled' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to eq(['983'])
      end
    end

    context 'when appointments have no visibility flags set' do
      it 'returns nil when all appointments lack date flags' do
        appointments = [
          { location_id: '983', future: false, past: false, pending: false, status: 'booked' },
          { location_id: '984', future: false, past: false, pending: false, status: 'booked' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to be_nil
      end
    end

    context 'when appointments list is empty' do
      it 'returns nil' do
        result = controller.send(:appointment_facility_ids, [])
        expect(result).to be_nil
      end
    end

    context 'when appointments have nil location_id' do
      it 'filters out appointments with nil location_id' do
        appointments = [
          { location_id: nil, future: true, past: false, pending: false, status: 'booked' },
          { location_id: '984', future: true, past: false, pending: false, status: 'booked' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to eq(['984'])
      end

      it 'returns nil when all visible appointments have nil location_id' do
        appointments = [
          { location_id: nil, future: true, past: false, pending: false, status: 'booked' },
          { location_id: nil, future: false, past: true, pending: false, status: 'booked' }
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to be_nil
      end
    end

    context 'with mixed visible and cancelled appointments' do
      it 'only includes facility IDs from visible non-cancelled appointments' do
        appointments = [
          { location_id: '983', future: true, past: false, pending: false, status: 'booked' }, # visible
          { location_id: '984', future: true, past: false, pending: false, status: 'cancelled' }, # cancelled
          { location_id: '757', future: false, past: false, pending: true, status: 'proposed' }   # visible (pending)
        ]

        result = controller.send(:appointment_facility_ids, appointments)
        expect(result).to contain_exactly('983', '757')
      end
    end
  end
end
