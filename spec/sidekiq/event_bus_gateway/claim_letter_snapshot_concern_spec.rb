# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/sidekiq/event_bus_gateway/constants'
require_relative '../../../app/sidekiq/event_bus_gateway/claim_letter_snapshot_concern'

# Exercises the shared claim-letter signal helpers directly, decoupled from any
# one job. These signals (delta / recency / snapshot) back the gated send.
RSpec.describe EventBusGateway::ClaimLetterSnapshotConcern do
  subject(:helper) { Class.new { include EventBusGateway::ClaimLetterSnapshotConcern }.new }

  # Call the private helpers directly.
  def call(name, *) = helper.send(name, *)

  let(:old_date) { 30.days.ago }
  let(:recent_date) { 2.days.ago }

  describe '#decision_letter_snapshot' do
    let(:letters) do
      [
        { doc_type: '184', document_id: 'a', received_at: old_date },
        { doc_type: '184', document_id: 'b', received_at: recent_date },
        { doc_type: '702', document_id: 'c', received_at: recent_date }
      ]
    end

    it 'counts letters, isolates decision (184) letters, and lists their ids' do
      snapshot = call(:decision_letter_snapshot, letters)

      expect(snapshot).to include(
        letter_count: 3,
        decision_letter_count: 2,
        decision_letter_document_ids: %w[a b],
        most_recent_decision_document_id: 'b'
      )
    end

    it 'is empty-safe' do
      expect(call(:decision_letter_snapshot, nil)).to include(letter_count: 0, decision_letter_count: 0)
    end
  end

  describe '#recent_decision_letter?' do
    it 'is true when a decision letter falls within the recency window' do
      expect(call(:recent_decision_letter?, [{ doc_type: '184', received_at: recent_date }])).to be(true)
    end

    it 'is false when the only decision letter is older than the window' do
      expect(call(:recent_decision_letter?, [{ doc_type: '184', received_at: 1.year.ago }])).to be(false)
    end

    it 'ignores non-decision doc types' do
      expect(call(:recent_decision_letter?, [{ doc_type: '702', received_at: recent_date }])).to be(false)
    end
  end

  describe '#new_decision_letter?' do
    let(:snapshot) { { 'decision_letter_count' => 1, 'decision_letter_document_ids' => ['a'] } }

    it 'is true when a new document id appears vs. the snapshot' do
      current = { decision_letter_count: 2, decision_letter_document_ids: %w[a b] }
      expect(call(:new_decision_letter?, current, snapshot)).to be(true)
    end

    it 'is false when the decision-letter set is unchanged' do
      current = { decision_letter_count: 1, decision_letter_document_ids: ['a'] }
      expect(call(:new_decision_letter?, current, snapshot)).to be(false)
    end

    it 'falls back to a rise in count when ids are unavailable' do
      current = { decision_letter_count: 2, decision_letter_document_ids: [] }
      bare_snapshot = { 'decision_letter_count' => 1, 'decision_letter_document_ids' => [] }
      expect(call(:new_decision_letter?, current, bare_snapshot)).to be(true)
    end

    it 'falls back to plain presence when no snapshot was carried' do
      expect(call(:new_decision_letter?, { decision_letter_count: 1 }, nil)).to be(true)
      expect(call(:new_decision_letter?, { decision_letter_count: 0 }, {})).to be(false)
    end
  end

  describe '#decision_letter_available?' do
    context 'with no prior snapshot (send time)' do
      it 'uses the recency signal' do
        expect(call(:decision_letter_available?, [{ doc_type: '184', received_at: recent_date }], nil)).to be(true)
        expect(call(:decision_letter_available?, [{ doc_type: '184', received_at: 1.year.ago }], nil)).to be(false)
      end
    end

    context 'with a prior snapshot (re-check)' do
      let(:snapshot) { { 'decision_letter_count' => 1, 'decision_letter_document_ids' => ['a'] } }

      it 'uses the delta signal — even for a backdated new letter the recency check would miss' do
        letters = [
          { doc_type: '184', document_id: 'a', received_at: old_date },
          { doc_type: '184', document_id: 'b', received_at: old_date }
        ]
        expect(call(:decision_letter_available?, letters, snapshot)).to be(true)
      end

      it 'is false when the set has not changed' do
        letters = [{ doc_type: '184', document_id: 'a', received_at: old_date }]
        expect(call(:decision_letter_available?, letters, snapshot)).to be(false)
      end
    end
  end

  describe '#seconds_since' do
    it 'returns whole seconds elapsed' do
      expect(call(:seconds_since, 5.minutes.ago.utc.iso8601)).to be_within(2).of(300)
    end

    it 'returns nil for blank or unparseable input' do
      expect(call(:seconds_since, nil)).to be_nil
      expect(call(:seconds_since, 'not-a-date')).to be_nil
    end
  end
end
