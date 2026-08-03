# frozen_string_literal: true

require 'rails_helper'
require 'mhv/prescriptions/refill_request_tracker'

# RC6 CHARACTERIZATION / VALIDATION SPEC
#
# The multi-repo coordination spec lists RC6 as a suspected bug: when a refill
# batch has a partial success, the concern is that ALL claimed orders (including
# successful ones) would have their "requested" badge dropped/released.
#
# This spec validates the CURRENT behavior of the v2 claim-release logic by
# exercising the private helper methods directly against a stubbed tracker.
# It documents whether the RC6 bug reproduces. (It does NOT — current code
# already releases only the failed subset.)
RSpec.describe MyHealth::V2::PrescriptionsController, type: :controller do
  # Instantiate the controller directly (rather than overriding rspec-rails' built-in
  # `controller` helper) so we can unit-test the private claim-release helper in isolation.
  let(:controller_instance) { described_class.new }
  let(:tracker) { instance_double(MHV::Prescriptions::RefillRequestTracker) }

  before do
    allow(controller_instance).to receive(:refill_request_tracker).and_return(tracker)
  end

  describe '#release_failed_claims_for (RC6 claim-release logic)' do
    context 'when the batch is a partial success (some succeed, some fail)' do
      let(:claimed_orders) do
        [
          { 'id' => '1', 'stationNumber' => '570' },
          { 'id' => '2', 'stationNumber' => '570' }
        ]
      end
      let(:api_result) do
        { success: [{ id: '1' }], failed: [{ id: '2', error: 'some error', station_number: '570' }] }
      end

      it 'releases only the failed order claim, retaining the successful order badge (RC6 already handled)' do
        # RC6 VALIDATION: only the failed order's claim is released; the successful
        # order's badge is retained. The coordination-spec concern (all claims
        # dropped for successful orders) does NOT reproduce in current code.
        expect(tracker).to receive(:release_orders).with(api_result[:failed])

        controller_instance.send(:release_failed_claims_for, api_result, claimed_orders)
      end
    end

    context 'when the entire batch failed with service-unavailable (no successes)' do
      let(:claimed_orders) do
        [
          { 'id' => '1', 'stationNumber' => '570' },
          { 'id' => '2', 'stationNumber' => '570' }
        ]
      end
      let(:service_unavailable) { MHV::Prescriptions::RefillRequestTracker::SERVICE_UNAVAILABLE_ERROR }
      let(:api_result) do
        {
          success: [],
          failed: [
            { id: '1', error: service_unavailable, station_number: '570' },
            { id: '2', error: service_unavailable, station_number: '570' }
          ]
        }
      end

      it 'retains all claims and releases nothing (safe retry, cannot infer upstream acceptance)' do
        expect(tracker).not_to receive(:release_orders)

        controller_instance.send(:release_failed_claims_for, api_result, claimed_orders)
      end
    end

    context 'when the entire batch failed with a non-service-unavailable error (no successes)' do
      let(:claimed_orders) do
        [
          { 'id' => '1', 'stationNumber' => '570' },
          { 'id' => '2', 'stationNumber' => '570' }
        ]
      end
      let(:api_result) do
        {
          success: [],
          failed: [
            { id: '1', error: 'Some other error', station_number: '570' },
            { id: '2', error: 'Some other error', station_number: '570' }
          ]
        }
      end

      it 'releases the failed subset because the retain guard only applies to service-unavailable' do
        expect(tracker).to receive(:release_orders).with(api_result[:failed])

        controller_instance.send(:release_failed_claims_for, api_result, claimed_orders)
      end
    end
  end
end
