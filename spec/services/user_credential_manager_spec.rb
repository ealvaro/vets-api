# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserCredentialManager do
  describe '.perform_account_action' do
    subject(:perform_account_action) { described_class.perform_account_action(action:, icn:) }

    let(:user_account) { create(:user_account) }
    let(:icn) { user_account.icn }
    let(:action) { :lock }

    context 'when action is missing' do
      let(:action) { nil }

      it 'raises a ParameterMissing error' do
        expect { perform_account_action }.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when action is invalid' do
      let(:action) { :invalid_action }

      it 'raises a BadRequest error' do
        expect { perform_account_action }.to raise_error(Common::Exceptions::BadRequest)
      end
    end

    context 'when icn is missing' do
      let(:icn) { nil }

      it 'raises a ParameterMissing error' do
        expect { perform_account_action }.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when user account does not exist for the icn' do
      let(:icn) { 'some-icn' }

      it 'raises a RecordNotFound error' do
        expect { perform_account_action }.to raise_error(Common::Exceptions::RecordNotFound)
      end
    end

    context 'when user account exists for the icn' do
      it 'does not raise an error' do
        expect { perform_account_action }.not_to raise_error
      end

      context 'and action is lock' do
        let(:action) { :lock }
        let(:expected_log_context) { { action:, user_account_id: user_account.id, locked: true } }
        let(:expected_log_message) do
          "[UserCredentialManager] UserAccount lock success, context: #{expected_log_context.to_json}"
        end

        it 'locks the user_account and returns context' do
          user_account.unlock!
          expect(Rails.logger).to receive(:info).with(expected_log_message)
          response = perform_account_action

          expect(user_account.reload.locked).to be(true)
          expect(response).to include(expected_log_context)
        end
      end

      context 'and action is unlock' do
        let(:action) { :unlock }
        let(:expected_log_context) { { action:, user_account_id: user_account.id, locked: false } }
        let(:expected_log_message) do
          "[UserCredentialManager] UserAccount unlock success, context: #{expected_log_context.to_json}"
        end

        it 'unlocks the user_account and returns context' do
          user_account.lock!
          expect(Rails.logger).to receive(:info).with(expected_log_message)
          response = perform_account_action

          expect(user_account.reload.locked).to be(false)
          expect(response).to include(expected_log_context)
        end
      end
    end
  end

  describe '.perform_verification_action' do
    subject(:perform_verification_action) do
      described_class.perform_verification_action(action:, type:, credential_id:)
    end

    let(:user_verification) { create(:idme_user_verification) }
    let(:type) { user_verification.credential_type }
    let(:credential_id) { user_verification.idme_uuid }
    let(:action) { :lock }

    context 'when action is missing' do
      let(:action) { nil }

      it 'raises a ParameterMissing error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when action is invalid' do
      let(:action) { :invalid_action }

      it 'raises a BadRequest error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::BadRequest)
      end
    end

    context 'when type is missing' do
      let(:type) { nil }

      it 'raises a ParameterMissing error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when credential_id is missing' do
      let(:credential_id) { nil }

      it 'raises a ParameterMissing error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when type is invalid' do
      let(:type) { 'some-type' }

      it 'raises a BadRequest error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::BadRequest)
      end
    end

    context 'when credential_id does not exist' do
      let(:credential_id) { 'some-credential-id' }

      it 'raises a RecordNotFound error' do
        expect { perform_verification_action }.to raise_error(Common::Exceptions::RecordNotFound)
      end
    end

    context 'when type and credential_id are valid' do
      it 'does not raise an error' do
        expect { perform_verification_action }.not_to raise_error
      end

      context 'and action is lock' do
        let(:action) { :lock }
        let(:expected_log_context) { { action:, type:, credential_id:, locked: true } }
        let(:expected_log_message) do
          "[UserCredentialManager] UserVerification lock success, context: #{expected_log_context.to_json}"
        end

        before { user_verification.unlock! }

        it 'locks the user_verification and returns context' do
          expect(Rails.logger).to receive(:info).with(expected_log_message)
          response = perform_verification_action

          expect(user_verification.reload.locked).to be(true)
          expect(response).to include(expected_log_context)
        end
      end

      context 'and action is unlock' do
        let(:action) { :unlock }
        let(:expected_log_context) { { action:, type:, credential_id:, locked: false } }
        let(:expected_log_message) do
          "[UserCredentialManager] UserVerification unlock success, context: #{expected_log_context.to_json}"
        end

        before { user_verification.lock! }

        it 'unlocks the user_verification and returns context' do
          expect(Rails.logger).to receive(:info).with(expected_log_message)
          response = perform_verification_action

          expect(user_verification.reload.locked).to be(false)
          expect(response).to include(expected_log_context)
        end
      end
    end
  end
end
