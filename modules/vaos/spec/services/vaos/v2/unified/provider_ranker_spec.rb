# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::ProviderRanker do
  # Lightweight stand-in for a BaseProvider: only the fields the ranker reads/writes.
  let(:provider_class) do
    Struct.new(:distance_from_user, :next_available_date, :seen_before,
               :match_score, :rationale, keyword_init: true)
  end
  let(:today) { Date.new(2026, 7, 9) }
  # Equal proximity/availability weights, zero continuity so phase-1 cases isolate the two live signals.
  let(:weights) { { proximity: 0.5, availability: 0.5, continuity: 0.0 } }
  let(:caps) { { distance_miles: 60, wait_days: 30 } }
  let(:ranker) { described_class.new(weights:, caps:, today:) }

  def provider(distance: nil, next_available: nil, seen_before: nil)
    provider_class.new(distance_from_user: distance, next_available_date: next_available,
                       seen_before:)
  end

  describe '#rank' do
    it 'orders providers best-first by weighted score' do
      near_soon = provider(distance: 5,  next_available: '2026-07-12') # close + soon  -> best
      near_late = provider(distance: 5,  next_available: '2026-08-01')
      far_soon  = provider(distance: 55, next_available: '2026-07-12')

      result = ranker.rank([far_soon, near_late, near_soon])

      expect(result).to eq([near_soon, near_late, far_soon])
      expect(result.map(&:match_score)).to eq(result.map(&:match_score).sort.reverse)
    end

    it 'annotates each provider with a match_score in 0..100' do
      ranked = ranker.rank([provider(distance: 10, next_available: '2026-07-14')]).first

      expect(ranked.match_score).to be_between(0, 100)
    end

    it 'breaks score ties by proximity (closer wins)' do
      # Same availability, so scores tie on the availability factor; distance decides.
      closer  = provider(distance: 10, next_available: nil)
      farther = provider(distance: 40, next_available: nil)

      expect(ranker.rank([farther, closer])).to eq([closer, farther])
    end

    it 'preserves input order when score and distance are identical' do
      first  = provider(distance: 10, next_available: '2026-07-12')
      second = provider(distance: 10, next_available: '2026-07-12')
      third  = provider(distance: 10, next_available: '2026-07-12')

      expect(ranker.rank([first, second, third])).to eq([first, second, third])
      expect(ranker.rank([third, first, second])).to eq([third, first, second])
    end

    it 'returns an empty array for no providers' do
      expect(ranker.rank([])).to eq([])
    end
  end

  describe 'absent signals are treated as unknown (drop-and-renormalize)' do
    it 'scores a provider on proximity alone when availability is missing, at full weight' do
      only_distance = ranker.rank([provider(distance: 30)]).first # 30/60 -> proximity 50

      # Renormalized over the single present factor => the proximity score itself, not halved.
      expect(only_distance.match_score).to eq(50.0)
    end

    it 'does not let a missing availability demote a much nearer provider' do
      near_unknown = provider(distance: 3,  next_available: nil) # only proximity known
      far_soon     = provider(distance: 55, next_available: '2026-07-11') # both known, but far

      # If nil availability were scored as 0, far_soon would leapfrog. It must not.
      expect(ranker.rank([far_soon, near_unknown])).to eq([near_unknown, far_soon])
    end

    it 'gives a provider with no usable signals a score of 0' do
      scored = ranker.rank([provider]).first

      expect(scored.match_score).to eq(0.0)
      expect(scored.rationale).to eq('')
    end
  end

  describe 'continuity factor (phase 2)' do
    let(:weights) { { proximity: 0.4, availability: 0.4, continuity: 0.2 } }

    it 'boosts a provider seen before over an otherwise-identical one' do
      seen   = provider(distance: 20, next_available: '2026-07-20', seen_before: true)
      unseen = provider(distance: 20, next_available: '2026-07-20', seen_before: false)

      expect(ranker.rank([unseen, seen])).to eq([seen, unseen])
    end

    it 'ignores continuity entirely when the flag is unknown (nil)' do
      # seen_before nil => factor dropped => scored identically to a two-signal provider.
      unknown = provider(distance: 20, next_available: '2026-07-20', seen_before: nil)

      expect(unknown.seen_before).to be_nil
      expect { ranker.rank([unknown]) }.not_to raise_error
      expect(ranker.rank([unknown]).first.rationale).not_to include('seen here before')
    end
  end

  describe 'rationale text' do
    it 'is templated from only the signals that are present' do
      ranked = ranker.rank([provider(distance: 14, next_available: '2026-07-12')]).first

      expect(ranked.rationale).to eq('14 mi away · opens in 3 days')
    end

    it 'phrases same-day and next-day availability specially' do
      today_slot = ranker.rank([provider(distance: 5, next_available: '2026-07-09')]).first
      tomorrow   = ranker.rank([provider(distance: 5, next_available: '2026-07-10')]).first

      expect(today_slot.rationale).to include('available today')
      expect(tomorrow.rationale).to include('opens tomorrow')
    end

    it 'includes the continuity phrase only when seen before' do
      weights = { proximity: 0.4, availability: 0.4, continuity: 0.2 }
      ranker = described_class.new(weights:, caps:, today:)

      seen = ranker.rank([provider(distance: 5, next_available: '2026-07-12', seen_before: true)]).first
      expect(seen.rationale).to include('seen here before')
    end
  end

  describe 'normalization caps' do
    it 'clamps distance beyond the cap so a runaway value cannot drive the score negative' do
      beyond_cap = ranker.rank([provider(distance: 500)]).first # cap is 60

      expect(beyond_cap.match_score).to eq(0.0)
    end

    it 'clamps a past next-available date to "today" rather than a negative wait' do
      past = ranker.rank([provider(distance: 60, next_available: '2026-01-01')]).first

      # distance 60 -> proximity 0; past date clamps to 0 days -> availability 100; avg = 50.
      expect(past.match_score).to eq(50.0)
      expect(past.rationale).to include('available today')
    end

    it 'weight sensitivity: shifting weight toward availability reorders results' do
      near_late = provider(distance: 5,  next_available: '2026-08-08') # ~30 days
      far_soon  = provider(distance: 50, next_available: '2026-07-11') # 2 days

      proximity_heavy = described_class.new(
        weights: { proximity: 0.9, availability: 0.1, continuity: 0.0 }, caps:, today:
      )
      availability_heavy = described_class.new(
        weights: { proximity: 0.1, availability: 0.9, continuity: 0.0 }, caps:, today:
      )

      expect(proximity_heavy.rank([near_late, far_soon]).first).to eq(near_late)
      expect(availability_heavy.rank([near_late, far_soon]).first).to eq(far_soon)
    end
  end

  describe 'defaults' do
    it 'falls back to DEFAULT_WEIGHTS/DEFAULT_CAPS when constructed with none' do
      ranker = described_class.new(today:)
      scored = ranker.rank([provider(distance: 30, next_available: '2026-07-24')])

      expect(scored.first.match_score).to be_between(0, 100)
    end

    it 'coerces numeric strings and ignores nil/invalid values so defaults remain intact' do
      string_ranker = described_class.new(
        weights: { 'proximity' => '1', availability: '0', continuity: '0' },
        caps: { 'distance_miles' => '60', wait_days: '30' },
        today:
      )
      float_ranker = described_class.new(
        weights: { proximity: 1, availability: 0, continuity: 0 },
        caps: { distance_miles: 60, wait_days: 30 },
        today:
      )
      candidate = provider(distance: 0)

      expect(string_ranker.rank([candidate]).first.match_score)
        .to eq(float_ranker.rank([candidate]).first.match_score)

      # nil / garbage must not overwrite defaults (30 mi under a 60 mi cap => proximity 50).
      nil_ranker = described_class.new(
        weights: { proximity: nil, availability: 'nope' },
        caps: { distance_miles: nil },
        today:
      )

      expect(nil_ranker.rank([provider(distance: 30)]).first.match_score).to eq(50.0)
    end
  end
end
