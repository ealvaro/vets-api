# frozen_string_literal: true

require 'rails_helper'

describe VAOS::V2::AppointmentsPresentationFilter do
  let(:user) { nil }
  let(:filterer) { described_class.new(user:) }
  let(:upcoming) { mock_appointment(id: 'upcoming', start: 1.day.from_now) }
  let(:past) { mock_appointment(id: 'past', start: 1.day.ago) }
  let(:cancelled) { mock_appointment(id: 'past', status: 'cancelled', start: 30.days.ago) }
  let(:request) do
    requested_periods = [{ start: 20.days.ago }]
    mock_appointment(id: 'request', status: 'proposed', created: 30.days.ago, requested_periods:)
  end

  def mock_appointment(id: nil, created: nil, status: nil, start: nil, requested_periods: nil)
    OpenStruct.new(
      id:,
      created: created&.to_s,
      status:,
      start: start&.to_s,
      requested_periods:
    )
  end

  before do
    allow(Flipper).to receive(:enabled?)
      .with(:va_online_scheduling_mobile_presentation_filter_update, nil)
      .and_return(false)
    Timecop.freeze
  end

  after do
    Timecop.return
  end

  describe '#user_facing?' do
    it 'returns true for upcoming appointment' do
      expect(filterer.user_facing?(upcoming)).to be true
    end

    it 'returns true for past appointments' do
      expect(filterer.user_facing?(past)).to be true
    end

    it 'returns true for cancelled appointments' do
      expect(filterer.user_facing?(cancelled)).to be true
    end

    describe 'appointment requests' do
      it 'returns true for appointment requests created during the requested date range' do
        expect(filterer.user_facing?(request)).to be true
      end

      it 'returns false if it was created more than 120 days ago' do
        request[:created] = 121.days.ago.to_s
        expect(filterer.user_facing?(request)).to be false
      end

      it 'returns false if it was created more than a day from now' do
        request[:created] = 2.days.from_now.to_s
        expect(filterer.user_facing?(request)).to be false
      end

      it 'returns false if it does not have requested_periods' do
        request[:requested_periods] = []
        expect(filterer.user_facing?(request)).to be false
      end

      context 'when :va_online_scheduling_mobile_presentation_filter_update is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_mobile_presentation_filter_update, nil)
            .and_return(true)
        end

        it 'keeps requests regardless of their created date' do
          request[:created] = 200.days.ago.to_s
          expect(filterer.user_facing?(request)).to be true
        end

        it 'keeps requests with no created date (Cerner/OH)' do
          request[:created] = nil
          expect(filterer.user_facing?(request)).to be true
        end

        it 'still drops request-shaped records with a non-request status' do
          request[:status] = 'fulfilled'
          expect(filterer.user_facing?(request)).to be false
        end

        it 'still drops records with no requested_periods and no start' do
          malformed = mock_appointment(id: 'malformed', status: 'proposed')
          expect(filterer.user_facing?(malformed)).to be false
        end
      end

      describe 'date validations', :aggregate_errors do
        context 'for appointments' do
          it 'returns false but does not raise an error if start time is empty' do
            cancelled[:start] = nil
            expect(Rails.logger).not_to receive(:error)
            expect(filterer.user_facing?(cancelled)).to be false
          end
        end

        context 'for appointment requests' do
          it 'returns false but does not raise an error if created date is empty' do
            request[:created] = nil
            expect(Rails.logger).not_to receive(:error)
            expect(filterer.user_facing?(request)).to be false
          end
        end
      end
    end
  end
end
