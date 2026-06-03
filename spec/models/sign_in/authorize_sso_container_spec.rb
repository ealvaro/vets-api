# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::AuthorizeSSOContainer, type: :model do
  let(:authorize_sso_container) do
    create(:authorize_sso_container,
           uuid:,
           client_id:,
           code_challenge:,
           code_challenge_method:,
           client_state:,
           app_name:,
           nonce:)
  end

  let(:uuid) { SecureRandom.uuid }
  let(:client_config) { create(:client_config) }
  let(:client_id) { client_config.client_id }
  let(:code_challenge) { Base64.urlsafe_encode64(SecureRandom.hex) }
  let(:code_challenge_method) { 'S256' }
  let(:client_state) { SecureRandom.hex }
  let(:app_name) { 'some-app' }
  let(:nonce) { SecureRandom.hex }

  describe 'validations' do
    describe '#uuid' do
      subject { authorize_sso_container.uuid }

      context 'when uuid is nil' do
        let(:uuid) { nil }
        let(:expected_error) { Common::Exceptions::ValidationErrors }
        let(:expected_error_message) { 'Validation error' }

        it 'raises validation error' do
          expect { subject }.to raise_error(expected_error, expected_error_message)
        end
      end

      context 'when uuid is not a valid UUID format' do
        let(:uuid) { 'not-a-uuid' }
        let(:expected_error) { Common::Exceptions::ValidationErrors }
        let(:expected_error_message) { 'Validation error' }

        it 'raises validation error' do
          expect { subject }.to raise_error(expected_error, expected_error_message)
        end
      end
    end

    describe '#client_id' do
      subject { authorize_sso_container.client_id }

      context 'when client_id is nil' do
        let(:client_id) { nil }
        let(:expected_error) { Common::Exceptions::ValidationErrors }
        let(:expected_error_message) { 'Validation error' }

        it 'raises validation error' do
          expect { subject }.to raise_error(expected_error, expected_error_message)
        end
      end
    end
  end

  describe 'persistence' do
    subject { described_class.find(uuid) }

    before { authorize_sso_container }

    it 'persists all attributes and is retrievable by uuid' do
      expect(subject).to have_attributes(
        uuid:,
        client_id:,
        code_challenge:,
        code_challenge_method:,
        client_state:,
        app_name:,
        nonce:
      )
    end
  end
end
