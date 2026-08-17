# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::SessionSerializer do
  let(:session_serializer) do
    SignIn::SessionSerializer.new(session_records:, current_session_handle:)
  end

  describe '#perform' do
    subject { session_serializer.perform }

    context 'when session records are present' do
      let(:user) { create(:user) }
      let(:user_account) { user.user_account }
      let(:client_config) { create(:client_config) }
      let(:client_id) { client_config.client_id }
      let(:oauth_session) { create(:oauth_session, user_account:) }
      let(:current_session_handle) { oauth_session.handle }
      let!(:session_record) do
        create(:session_record, handle: current_session_handle, user_account:, client_id:,
                                browser: 'Chrome', device_description: 'Mac')
      end
      let(:session_records) { SignIn::SessionRecord.where(user_account:) }
      let(:status) { 'current' }

      let(:expected_serialized_session) do
        {
          handle: session_record.handle,
          client_id: session_record.client_id,
          browser: 'Chrome',
          device_description: 'Mac',
          location: session_record.location,
          created_at: session_record.created_at,
          last_activity_at: session_record.last_activity_at,
          signed_out_at: session_record.signed_out_at,
          expiration: oauth_session.refresh_expiration,
          status:
        }
      end

      it 'returns serialized session records' do
        expect(subject.first).to eq(expected_serialized_session)
      end

      context 'and session records have 3 status values' do
        let!(:session_record2) { create(:session_record, user_account:) }
        let!(:session_record3) { create(:session_record, user_account:, signed_out_at: 10.minutes.ago) }

        it 'returns session records with correct status values' do
          expect(subject.map { |session| session[:status] }).to include('current', 'active', 'signed_out')
        end
      end
    end

    context 'when session records are empty' do
      let(:session_records) { [] }
      let(:current_session_handle) { nil }

      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end
  end
end
