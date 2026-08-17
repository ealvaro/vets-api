# frozen_string_literal: true

require 'rails_helper'
require 'mhv/prescriptions/refill_request_tracker'
require 'unified_health_data/models/prescription'

# Filter-count breadth unit specs for the v2 prescriptions controller. Drives the private
# count_* helpers directly (mirrors prescriptions_refill_claim_release_spec's approach) so the
# counts are asserted against FIXED expected values, not derived from the controller constants.
RSpec.describe MyHealth::V2::PrescriptionsController, type: :controller do
  let(:controller_instance) { described_class.new }

  def rx(**attrs)
    UnifiedHealthData::Prescription.new(**attrs)
  end

  # Parked feeds the active bucket.
  describe '#count_active_medications (Parked)' do
    let(:list) do
      [rx(disp_status: 'Active: Parked'), rx(disp_status: 'Active'), rx(disp_status: 'Expired')]
    end

    it 'counts "Active: Parked" as active (2 of 3)' do
      expect(controller_instance.send(:count_active_medications, list)).to eq(2)
    end
  end

  describe 'filter-count breadth (exact counts, not >= 0)' do
    let(:list) do
      [
        rx(disp_status: 'Active: Submitted'),                    # in_progress
        rx(disp_status: 'Active: Refill in Process'),            # in_progress
        rx(disp_status: 'Active', is_trackable: true),           # shipped (Active + trackable)
        rx(disp_status: 'Active', is_trackable: false),          # NOT shipped
        rx(disp_status: 'Transferred'),                          # transferred
        rx(disp_status: 'Unknown')                               # status_not_available
      ]
    end

    it 'counts in_progress exactly (Active: Submitted + Refill in Process = 2)' do
      expect(controller_instance.send(:count_in_progress_medications, list)).to eq(2)
    end

    it 'counts shipped exactly (Active + is_trackable only = 1)' do
      expect(controller_instance.send(:count_shipped_medications, list)).to eq(1)
    end

    it 'counts transferred exactly (1)' do
      expect(controller_instance.send(:count_transferred_medications, list)).to eq(1)
    end

    it 'counts status_not_available exactly (Unknown = 1)' do
      expect(controller_instance.send(:count_unknown_status_medications, list)).to eq(1)
    end
  end

  # Confirm the emit boundary injects the real optimistic badge string (not a made-up value).
  describe 'optimistic recent-submission override string' do
    it 'passes "Active: Submitted" into the tracker' do
      tracker = instance_double(MHV::Prescriptions::RefillRequestTracker)
      allow(controller_instance).to receive(:refill_request_tracker).and_return(tracker)

      expect(tracker).to receive(:apply_submitted_state!)
        .with(anything, in_progress_status: 'Active: Submitted')

      controller_instance.send(:apply_recent_submission_overrides, [])
    end
  end
end
