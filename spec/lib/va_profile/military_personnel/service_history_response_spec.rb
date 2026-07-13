# frozen_string_literal: true

require 'rails_helper'
require 'va_profile/military_personnel/service_history_response'

describe VAProfile::MilitaryPersonnel::ServiceHistoryResponse do
  describe '.sort_by_begin_date' do
    let(:with_begin_date) { VAProfile::Models::ServiceHistory.new(begin_date: '2010-01-01') }
    let(:blank_begin_date) { VAProfile::Models::ServiceHistory.new(begin_date: nil) }
    let(:invalid_begin_date) { VAProfile::Models::ServiceHistory.new(begin_date: 'not-a-date') }

    it 'does not raise when episodes mix String begin_dates and a blank begin_date' do
      expect do
        described_class.sort_by_begin_date([blank_begin_date, with_begin_date])
      end.not_to raise_error
    end

    it 'sorts episodes with a begin_date before ones without' do
      result = described_class.sort_by_begin_date([blank_begin_date, with_begin_date])

      expect(result).to eq([with_begin_date, blank_begin_date])
    end

    it 'treats an unparseable begin_date like a blank one instead of raising' do
      expect do
        described_class.sort_by_begin_date([invalid_begin_date, with_begin_date])
      end.not_to raise_error
    end

    it 'returns Date objects without attempting to parse them again' do
      parsed_begin_date = Date.new(2010, 1, 1)
      episode = VAProfile::Models::ServiceHistory.new(begin_date: parsed_begin_date)

      expect(described_class.parse_begin_date(parsed_begin_date)).to eq(parsed_begin_date)
      expect(described_class.sort_by_begin_date([episode])).to eq([episode])
    end

    it 'logs a debug message when begin_date is unparseable' do
      expect(Rails.logger).to receive(:debug)
        .with('VAProfile service history unparseable begin_date', begin_date: 'not-a-date')

      described_class.sort_by_begin_date([invalid_begin_date, with_begin_date])
    end

    it 'does not log a warning for a blank begin_date' do
      expect(Rails.logger).not_to receive(:warn)

      described_class.sort_by_begin_date([blank_begin_date, with_begin_date])
    end
  end
end
