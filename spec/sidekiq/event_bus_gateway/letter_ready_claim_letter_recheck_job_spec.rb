# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/sidekiq/event_bus_gateway/constants'

# Deprecated no-op drain shim (see the job file). These specs pin the shim's
# only contracts: it must not retry and must never do BD work or raise, so stale
# enqueued measurement jobs drain harmlessly. Safe to delete with the shim.
RSpec.describe EventBusGateway::LetterReadyClaimLetterRecheckJob, type: :job do
  before { allow(StatsD).to receive(:increment) }

  it 'does not retry' do
    expect(described_class.get_sidekiq_options['retry']).to be(false)
  end

  it 'no-ops for any args, records a drain metric, and never raises' do
    expect(StatsD).to receive(:increment)
      .with('event_bus_gateway.letter_ready_claim_letter_recheck.drained', tags: EventBusGateway::Constants::DD_TAGS)

    expect do
      described_class.new.perform('1234', 1.hour.ago.utc.iso8601, '1h', { 'decision_letter_count' => 1 })
    end.not_to raise_error
  end
end
