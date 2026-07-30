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

  describe '.sign_out' do
    let!(:record) { create(:session_record) }

    context 'with a handle matching an active record' do
      it 'stamps signed_out_at' do
        expect { described_class.sign_out(record.handle) }
          .to change { record.reload.signed_out_at }.from(nil)
      end

      it 'does not delete the record' do
        expect { described_class.sign_out(record.handle) }
          .not_to change(described_class, :count)
      end

      it 'returns the number of records stamped' do
        expect(described_class.sign_out(record.handle)).to eq(1)
      end
    end

    context 'when the record is already signed out' do
      let!(:record) { create(:session_record, signed_out_at: 3.days.ago) }

      it 'does not overwrite the original timestamp' do
        expect { described_class.sign_out(record.handle) }
          .not_to change { record.reload.signed_out_at }
      end

      it 'returns zero' do
        expect(described_class.sign_out(record.handle)).to eq(0)
      end
    end

    context 'when no record matches the handle' do
      it 'does not raise' do
        expect { described_class.sign_out(SecureRandom.uuid) }.not_to raise_error
      end

      it 'returns zero' do
        expect(described_class.sign_out(SecureRandom.uuid)).to eq(0)
      end

      it 'leaves existing records untouched' do
        expect { described_class.sign_out(SecureRandom.uuid) }
          .not_to change { record.reload.signed_out_at }
      end
    end

    context 'with an empty array' do
      it 'returns zero without stamping anything' do
        expect(described_class.sign_out([])).to eq(0)
        expect(record.reload.signed_out_at).to be_nil
      end
    end

    context 'with a nil handle' do
      it 'returns zero without stamping anything' do
        expect(described_class.sign_out(nil)).to eq(0)
        expect(record.reload.signed_out_at).to be_nil
      end
    end

    context 'with multiple handles' do
      let!(:other) { create(:session_record) }
      let!(:untouched) { create(:session_record) }

      it 'stamps every matching record' do
        described_class.sign_out([record.handle, other.handle])

        expect(record.reload.signed_out_at).to be_present
        expect(other.reload.signed_out_at).to be_present
      end

      it 'returns the number stamped' do
        expect(described_class.sign_out([record.handle, other.handle])).to eq(2)
      end

      it 'leaves non-matching records alone' do
        expect { described_class.sign_out([record.handle, other.handle]) }
          .not_to change { untouched.reload.signed_out_at }
      end

      it 'updates each row once when a handle repeats' do
        expect(described_class.sign_out([record.handle, record.handle])).to eq(1)
      end

      it 'stamps in a single query' do
        expect(described_class).to receive(:where).once.and_call_original
        described_class.sign_out([record.handle, other.handle])
      end
    end
  end
end
