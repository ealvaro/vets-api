# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/prescription_service'
require 'unified_health_data/models/prescription'

# Measurement-only stuck-status metrics. These specs prove the
# post-adapter list scan emits the expected stuck and status-total counters and
# PII/PHI-safe logs, restricts VistA refill-in-process to CMOP/mail fills, and
# still counts (but tags) Oracle Health refill-in-process.
RSpec.describe UnifiedHealthData::Concerns::PrescriptionStuckStatusLogging, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { UnifiedHealthData::PrescriptionService.new(user) }
  let(:now) { Time.zone.parse('2025-06-26T00:00:00Z') }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:mhv_medications_stuck_status_logging, anything).and_return(true)
  end

  def prescription(**attrs)
    UnifiedHealthData::Prescription.new(**attrs)
  end

  def emit(prescriptions)
    travel_to(now) { service.send(:log_stuck_status_metrics, prescriptions) }
  end

  describe 'submitted stuck > 3 days' do
    it 'emits the stuck counter for a VistA submitted rx aged past the window with no dispense' do
      emit([prescription(id: '1', source_ehr: 'vista',
                         refill_status: 'submitted', refill_submit_date: '2025-06-10T00:00:00Z')])

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.submitted',
        tags: array_including('source_ehr:vista', 'days_bucket:15-30')
      )
    end

    it 'does not count a submitted rx that has already been dispensed' do
      emit([prescription(id: '1', source_ehr: 'vista', refill_status: 'submitted',
                         refill_submit_date: '2025-06-10T00:00:00Z',
                         sorted_dispensed_date: '2025-06-12')])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', anything)
    end

    it 'does not count a submitted rx still within the 3-day window' do
      emit([prescription(id: '1', source_ehr: 'vista', refill_status: 'submitted',
                         refill_submit_date: '2025-06-24T00:00:00Z')])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', anything)
    end

    it 'does not double-count an OH submitted-stuck rx (OH drops refill_submit_date; the adapter emits instead)' do
      emit([prescription(id: '1', source_ehr: 'OH', refill_status: 'submitted', refill_submit_date: nil)])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', any_args)
    end

    it 'tags source_ehr:unknown when the source is blank' do
      emit([prescription(id: '1', source_ehr: nil,
                         refill_status: 'submitted', refill_submit_date: '2025-06-10T00:00:00Z')])

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.submitted',
        tags: array_including('source_ehr:unknown', 'days_bucket:15-30')
      )
    end
  end

  describe 'refill in process stuck > 5 days' do
    it 'counts a VistA CMOP/mail fill aged past the window' do
      emit([prescription(id: '1', source_ehr: 'vista',
                         refill_status: 'refillinprocess', sorted_dispensed_date: '2025-06-18',
                         cmop_ndc_number: '00113002240')])

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.refill_in_process',
        tags: array_including('source_ehr:vista', 'days_bucket:8-14')
      )
    end

    it 'excludes a VistA fill with no CMOP signal (in-person counter pickup)' do
      emit([prescription(id: '1', source_ehr: 'vista', refill_status: 'refillinprocess',
                         sorted_dispensed_date: '2025-06-18')])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.refill_in_process', anything)
    end

    it 'counts an Oracle Health fill (no CMOP signal available) and tags it source_ehr:OH' do
      emit([prescription(id: '1', source_ehr: 'OH', refill_status: 'refillinprocess',
                         sorted_dispensed_date: '2025-06-18')])

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.refill_in_process',
        tags: array_including('source_ehr:OH')
      )
    end

    it 'does not count a fill still within the 5-day window' do
      emit([prescription(id: '1', source_ehr: 'OH', refill_status: 'refillinprocess',
                         sorted_dispensed_date: '2025-06-24')])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.refill_in_process', anything)
    end
  end

  describe 'per-source status totals' do
    it 'emits per-source status totals' do
      emit([
             prescription(id: '1', source_ehr: 'vista', refill_status: 'submitted',
                          refill_submit_date: '2025-06-24T00:00:00Z'),
             prescription(id: '2', source_ehr: 'vista', refill_status: 'refillinprocess',
                          sorted_dispensed_date: '2025-06-25')
           ])

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.submitted_total', 1, tags: array_including('source_ehr:vista')
      )
      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.refill_in_process_total', 1, tags: array_including('source_ehr:vista')
      )
    end

    it 'does not emit status totals when no prescriptions match the status' do
      emit([prescription(id: '1', source_ehr: 'vista', refill_status: 'active')])

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted_total', any_args)
      expect(StatsD).not_to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.refill_in_process_total', any_args
      )
    end
  end

  describe 'privacy' do
    it 'logs a one-way hashed rx id and never the raw id or drug name' do
      captured = nil
      allow(Rails.logger).to receive(:info) do |arg|
        captured = arg if arg.is_a?(Hash) && arg[:message] == 'UHD prescription stuck status'
      end

      emit([prescription(id: '1', source_ehr: 'vista', station_number: '648',
                         refill_status: 'submitted', refill_submit_date: '2025-06-10T00:00:00Z')])

      expect(captured).to include(source_ehr: 'vista', station_number: '648', metric: 'submitted')
      expect(captured[:rx_id_hash]).to eq(Digest::SHA256.hexdigest('1'))
      expect(captured).not_to have_key(:prescription_name)
    end
  end

  describe 'day bucketing' do
    let(:formatter) do
      Class.new { include UnifiedHealthData::Concerns::PrescriptionStuckStatusFormatters }.new
    end

    it 'buckets days into low-cardinality ranges' do
      expect(formatter.stuck_days_bucket(3)).to eq('0-3')
      expect(formatter.stuck_days_bucket(4)).to eq('4-7')
      expect(formatter.stuck_days_bucket(8)).to eq('8-14')
      expect(formatter.stuck_days_bucket(15)).to eq('15-30')
      expect(formatter.stuck_days_bucket(31)).to eq('30+')
      expect(formatter.stuck_days_bucket(nil)).to eq('unknown')
    end
  end

  describe 'when the flag is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_stuck_status_logging, anything).and_return(false)
    end

    it 'emits nothing' do
      emit([prescription(id: '1', source_ehr: 'vista',
                         refill_status: 'submitted', refill_submit_date: '2025-06-10T00:00:00Z')])

      expect(StatsD).not_to have_received(:increment)
    end
  end

  describe 'resilience' do
    it 'fails open when a prescription raises during evaluation' do
      allow(service).to receive(:emit_stuck_submitted_totals).and_raise(StandardError, 'boom')

      expect { emit([prescription(id: '1', source_ehr: 'vista', refill_status: 'submitted')]) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(
        'UHD prescription stuck status logging failed', hash_including(error_message: 'boom')
      )
    end
  end
end
