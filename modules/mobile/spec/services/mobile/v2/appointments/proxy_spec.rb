# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::V2::Appointments::Proxy do
  subject { described_class.new(user) }

  let(:user) { build(:user, :loa3) }
  let(:start_date) { 2.days.ago.utc }
  let(:end_date) { 395.days.from_now.utc }
  let(:vaos_service) { instance_double(VAOS::V2::AppointmentsService) }
  let(:vaos_response) { { data: [], meta: { failures: [] } } }

  before do
    allow(VAOS::V2::AppointmentsService).to receive(:new).with(user).and_return(vaos_service)
    allow(vaos_service).to receive(:get_appointments).and_return(vaos_response)
    allow(Flipper).to receive(:enabled?).with(:appointments_consolidation, user).and_return(true)
  end

  describe 'VAOS_STATUSES' do
    it 'includes checked-in' do
      expect(described_class::VAOS_STATUSES).to include('checked-in')
    end
  end

  describe '#get_appointments' do
    context 'when include_pending is true' do
      it 'requests all statuses including checked-in' do
        subject.get_appointments(start_date:, end_date:, include_pending: true)

        expect(vaos_service).to have_received(:get_appointments).with(
          start_date,
          end_date,
          'proposed,cancelled,booked,fulfilled,arrived,checked-in',
          {},
          hash_including(clinics: true, facilities: true),
          'mobile'
        )
      end
    end

    context 'when include_pending is false' do
      it 'requests all statuses except proposed, still including checked-in' do
        subject.get_appointments(start_date:, end_date:, include_pending: false)

        expect(vaos_service).to have_received(:get_appointments).with(
          start_date,
          end_date,
          'cancelled,booked,fulfilled,arrived,checked-in',
          {},
          hash_including(clinics: true, facilities: true),
          'mobile'
        )
      end
    end

    context 'avs include param' do
      context 'when start_date is more than 3 days in the past' do
        let(:start_date) { 4.days.ago.utc }

        it 'sets avs to true' do
          subject.get_appointments(start_date:, end_date:, include_pending: true)

          expect(vaos_service).to have_received(:get_appointments).with(
            start_date, end_date, anything, anything, hash_including(avs: true), anything
          )
        end
      end

      context 'when start_date is less than 3 days in the past' do
        let(:start_date) { 1.day.ago.utc }

        it 'sets avs to false' do
          subject.get_appointments(start_date:, end_date:, include_pending: true)

          expect(vaos_service).to have_received(:get_appointments).with(
            start_date, end_date, anything, anything, hash_including(avs: false), anything
          )
        end
      end
    end
  end
end
