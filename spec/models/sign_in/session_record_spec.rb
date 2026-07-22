# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::SessionRecord, type: :model do
  subject { session_record }

  let(:session_record) do
    create(:session_record,
           user_account:,
           handle:,
           client_id:,
           sign_in_ip:,
           user_agent:,
           last_activity_at:,
           signed_out_at:,
           device_description:,
           location:)
  end

  let(:handle) { SecureRandom.uuid }
  let(:user_account) { create(:user_account) }
  let(:client_config) { create(:client_config) }
  let(:client_id) { client_config.client_id }
  let(:sign_in_ip) { Faker::Internet.ip_v4_address }
  let(:user_agent) { Faker::Internet.user_agent }
  let(:last_activity_at) { Time.zone.now }
  let(:signed_out_at) { Time.zone.now }
  let(:device_description) { 'some-device-description' }
  let(:location) { 'some-location' }

  describe 'validations' do
    context 'when all the attributes are valid' do
      it 'creates a new SessionRecord' do
        expect { subject }.to change(SignIn::SessionRecord, :count).by(1)
      end
    end

    describe '#client_id' do
      context 'when client_id is nil' do
        let(:client_id) { nil }
        let(:expected_error_message) { 'Validation failed: Client id must map to a configuration' }

        it 'raises validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end

      context 'when client_id is arbitrary' do
        let(:client_id) { 'some-client-id' }
        let(:expected_error_message) { 'Validation failed: Client id must map to a configuration' }

        it 'raises validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end
    end

    describe '#handle' do
      context 'when handle is nil' do
        let(:handle) { nil }
        let(:expected_error_message) { "Validation failed: Handle can't be blank" }

        it 'raises validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end

      context 'when handle is duplicate' do
        let!(:session_record_dup) { create(:session_record, handle:) }
        let(:expected_error_message) { 'Validation failed: Handle has already been taken' }

        it 'raises validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end
    end

    describe '#user_account' do
      context 'when user_account is nil' do
        let(:user_account) { nil }
        let(:expected_error_message) { 'Validation failed: User account must exist' }

        it 'raises validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end
    end
  end

  describe 'encrypted attributes' do
    describe '#sign_in_ip' do
      it 'returns the correct sign_in_ip' do
        expect(subject.sign_in_ip).to eq(sign_in_ip)
        expect(subject.sign_in_ip_ciphertext).to be_present
        expect(subject.sign_in_ip_ciphertext).not_to include(sign_in_ip)
      end
    end

    describe '#user_agent' do
      it 'returns the correct user_agent' do
        expect(subject.user_agent).to eq(user_agent)
        expect(subject.user_agent_ciphertext).to be_present
        expect(subject.user_agent_ciphertext).not_to include(user_agent)
      end
    end

    describe '#location' do
      it 'returns the correct location' do
        expect(subject.location).to eq(location)
        expect(subject.location_ciphertext).to be_present
        expect(subject.location_ciphertext).not_to include(location)
      end
    end
  end

  describe 'attributes' do
    describe '#last_activity_at' do
      it 'returns the correct last_activity_at' do
        expect(subject.last_activity_at).to be_within(1.second).of(last_activity_at)
      end
    end

    describe '#signed_out_at' do
      it 'returns the correct signed_out_at' do
        expect(subject.signed_out_at).to be_within(1.second).of(signed_out_at)
      end
    end

    describe '#device_description' do
      it 'returns the correct device_description' do
        expect(subject.device_description).to eq(device_description)
      end
    end
  end
end
