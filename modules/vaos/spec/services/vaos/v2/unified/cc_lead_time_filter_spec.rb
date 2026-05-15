# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::CCLeadTimeFilter do
  let(:slot_class) { Struct.new(:start) }

  def slot(iso) = slot_class.new(iso)

  describe '.filter' do
    let(:reference_time) { Time.zone.parse('2026-05-11T10:00:00-04:00') } # Mon 10 AM ET

    it "matches Kay's example: Monday ref keeps Thursday slot, drops Wednesday" do
      wed = slot('2026-05-13T09:00:00-04:00') # 2 business days
      thu = slot('2026-05-14T09:00:00-04:00') # 3 business days
      fri = slot('2026-05-15T09:00:00-04:00') # 4 business days

      result = described_class.filter([wed, thu, fri], reference_time:)
      expect(result.map(&:start)).to contain_exactly(thu.start, fri.start)
    end

    it 'skips a weekend: Thursday ref keeps next Tuesday' do
      thursday = Time.zone.parse('2026-05-14T10:00:00-04:00')
      monday   = slot('2026-05-18T09:00:00-04:00') # 2 bd (Fri, Mon)
      tuesday  = slot('2026-05-19T09:00:00-04:00') # 3 bd (Fri, Mon, Tue)

      result = described_class.filter([monday, tuesday], reference_time: thursday)
      expect(result.map(&:start)).to eq([tuesday.start])
    end

    it 'skips US federal holidays: Friday before Memorial Day -> Thursday after' do
      # 2026-05-25 Mon is Memorial Day. From Fri 2026-05-22:
      # Tue (1), Wed (2), Thu (3) -- Mon doesn't count.
      friday_before = Time.zone.parse('2026-05-22T10:00:00-04:00')
      wed_after = slot('2026-05-27T09:00:00-04:00') # 2 bd, drop
      thu_after = slot('2026-05-28T09:00:00-04:00') # 3 bd, keep

      result = described_class.filter([wed_after, thu_after], reference_time: friday_before)
      expect(result.map(&:start)).to eq([thu_after.start])
    end

    it 'evaluates each slot in its own offset (Hawaii late-evening edge case)' do
      # 9 PM Mon Hawaii (-10:00) = 7 AM Tue UTC. A naive server-UTC cutoff
      # would treat "today" as Tuesday and require a Friday Hawaii slot;
      # the correct answer honors Hawaii-local Monday and lets Thursday pass.
      hawaii_late_mon = Time.zone.parse('2026-05-12T07:00:00Z') # Tue 7 AM UTC
      thu_hawaii = slot('2026-05-14T09:00:00-10:00') # Thu 9 AM Hawaii

      expect(described_class.filter([thu_hawaii], reference_time: hawaii_late_mon))
        .to eq([thu_hawaii])
    end

    it 'evaluates each slot in its own offset (East Coast just-past-midnight UTC)' do
      # 11 PM Mon ET = 3 AM Tue UTC. Naive UTC cutoff would push to Friday;
      # ET-local Monday lets Thursday ET pass.
      east_late_mon = Time.zone.parse('2026-05-12T03:00:00Z')
      thu_et = slot('2026-05-14T09:00:00-04:00')

      expect(described_class.filter([thu_et], reference_time: east_late_mon))
        .to eq([thu_et])
    end

    it 'drops slots with blank start' do
      result = described_class.filter([slot(nil), slot(''), slot('2026-05-14T09:00:00-04:00')],
                                      reference_time:)
      expect(result.size).to eq(1)
    end

    it 'drops slots with an unparseable start (no raise)' do
      result = described_class.filter([slot('not-a-date'), slot('2026-05-14T09:00:00-04:00')],
                                      reference_time:)
      expect(result.size).to eq(1)
    end

    it 'returns an empty array for blank input' do
      expect(described_class.filter(nil, reference_time:)).to eq([])
      expect(described_class.filter([], reference_time:)).to eq([])
    end

    it 'honors a non-default lead_business_days override' do
      monday = Time.zone.parse('2026-05-11T10:00:00-04:00')
      tuesday = slot('2026-05-12T09:00:00-04:00')
      expect(described_class.filter([tuesday], reference_time: monday, lead_business_days: 1))
        .to eq([tuesday])
    end
  end

  describe '.business_day?' do
    it 'is false on Saturday' do
      expect(described_class.business_day?(Date.new(2026, 5, 16))).to be(false)
    end

    it 'is false on Sunday' do
      expect(described_class.business_day?(Date.new(2026, 5, 17))).to be(false)
    end

    it 'is true on a regular weekday' do
      expect(described_class.business_day?(Date.new(2026, 5, 13))).to be(true) # Wed
    end

    it 'is false on Memorial Day 2026 (observed federal holiday)' do
      expect(described_class.business_day?(Date.new(2026, 5, 25))).to be(false)
    end

    # The `holidays` gem's :us region tags calendar-date holidays but does
    # NOT shift weekend holidays to the federally-observed weekday. Accepted
    # launch limitation; documented in the filter.
    it 'is true on the federally-observed Independence Day weekday when July 4 falls on a weekend' do
      expect(described_class.business_day?(Date.new(2026, 7, 3))).to be(true)
    end
  end
end
