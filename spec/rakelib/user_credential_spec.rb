# frozen_string_literal: true

require 'rails_helper'
require 'rake'

describe 'user_credential rake tasks' do # rubocop:disable RSpec/DescribeClass
  let(:user_account) { create(:user_account) }
  let(:icn) { user_account.icn }
  let(:user_verification) { create(:logingov_user_verification, user_account:) }
  let(:type) { user_verification.credential_type }
  let(:credential_id) { user_verification.credential_identifier }
  let(:linked_user_verification) { create(:idme_user_verification, user_account:) }
  let(:linked_type) { linked_user_verification.credential_type }
  let(:linked_credential_id) { linked_user_verification.credential_identifier }
  let(:requested_by) { 'some-name' }

  before :all do
    Rake.application.rake_require '../rakelib/prod/user_credential'
    Rake::Task.define_task(:environment)
  end

  context 'argument validations' do
    let(:task) { Rake::Task['user_credential:lock_verification'] }

    before { task.reenable }

    context 'when a required argument is missing' do
      it 'raises an error' do
        expect do
          task.invoke
        end.to output(/\[UserCredential::UserVerification lock\] failed - Missing parameter/).to_stdout
      end
    end

    context 'when type argument is invalid' do
      let(:task) { Rake::Task['user_credential:lock_verification'] }
      let(:start_context) do
        {
          type: 'invalid',
          credential_id:,
          requested_by:
        }
      end

      it 'raises an error' do
        expect do
          task.invoke('invalid', credential_id,
                      requested_by)
        end.to output(/\[UserCredential::UserVerification lock\] rake task start[\s\S]*failed - Bad request/).to_stdout
      end
    end
  end

  context 'single credential changes' do
    let(:start_context) do
      {
        type:,
        credential_id:,
        requested_by:
      }
    end
    let(:complete_context) do
      {
        action: action.to_sym,
        type:,
        credential_id:,
        locked:,
        requested_by:
      }
    end
    let(:expected_output) do
      "#{namespace} rake task start, context: #{start_context.to_json}\n" \
        "#{namespace} rake task complete, context: #{complete_context.to_json}\n"
    end

    describe 'user_credential:lock_verification' do
      let(:task) { Rake::Task['user_credential:lock_verification'] }
      let(:namespace) { '[UserCredential::UserVerification lock]' }
      let(:action) { 'lock' }
      let(:locked) { true }

      before do
        user_verification.unlock!
        task.reenable
      end

      it 'locks the credential & return the credential type & uuid when successful' do
        expect(user_verification.locked).to be_falsey
        expect { task.invoke(type, credential_id, requested_by) }.to output(expected_output).to_stdout
        expect(user_verification.reload.locked).to be_truthy
      end
    end

    describe 'user_credential:unlock_verification' do
      let(:task) { Rake::Task['user_credential:unlock_verification'] }
      let(:namespace) { '[UserCredential::UserVerification unlock]' }
      let(:action) { 'unlock' }
      let(:locked) { false }

      before { user_verification.lock! }

      it 'unlocks the credential & return the credential type & uuid when successful' do
        expect(user_verification.locked).to be_truthy
        expect { task.invoke(type, credential_id, requested_by) }.to output(expected_output).to_stdout
        expect(user_verification.reload.locked).to be_falsey
      end
    end

    describe 'user credential not found' do
      let(:task) { Rake::Task['user_credential:lock_verification'] }
      let(:namespace) { '[UserCredential::UserVerification lock]' }
      let(:start_context) do
        {
          type:,
          credential_id: 'invalid',
          requested_by:
        }
      end
      let(:expected_output) do
        "#{namespace} rake task start, context: #{start_context.to_json}\n" \
          "#{namespace} failed - Record not found\n"
      end

      before { task.reenable }

      it 'logs an error message when UserVerification is not found' do
        expect { task.invoke(type, 'invalid', requested_by) }.to output(expected_output).to_stdout
      end
    end
  end

  context 'toggle lock on user account' do
    let(:start_context) do
      {
        icn:,
        requested_by:
      }
    end
    let(:complete_context) do
      {
        action: action.to_sym,
        user_account_id: user_account.id,
        locked:,
        requested_by:
      }
    end
    let(:expected_output) do
      [
        "#{namespace} rake task start, context: #{start_context.to_json}",
        "#{namespace} rake task complete, context: #{complete_context.to_json}"
      ].sort
    end

    describe 'user_credential:lock_account' do
      let(:task) { Rake::Task['user_credential:lock_account'] }
      let(:namespace) { '[UserCredential::UserAccount lock]' }
      let(:action) { 'lock' }
      let(:locked) { true }

      before do
        user_account.unlock!
        task.reenable
      end

      it 'locks user account & return the ICN when successful' do
        sorted_output = []

        expect do
          task.invoke(icn, requested_by)
          sorted_output = $stdout.string.split("\n").map(&:strip).sort
        end.to output.to_stdout

        expect(sorted_output).to eq(expected_output)
        expect(user_account.reload.locked).to be_truthy
      end
    end

    describe 'user_credential:unlock_account' do
      let(:task) { Rake::Task['user_credential:unlock_account'] }
      let(:namespace) { '[UserCredential::UserAccount unlock]' }
      let(:action) { 'unlock' }
      let(:locked) { false }

      before do
        user_account.lock!
        task.reenable
      end

      it 'unlocks user account & return the ICN when successful' do
        sorted_output = []

        expect do
          task.invoke(icn, requested_by)
          sorted_output = $stdout.string.split("\n").map(&:strip).sort
        end.to output.to_stdout

        expect(sorted_output).to eq(expected_output)
        expect(user_account.reload.locked).to be_falsey
      end
    end

    describe 'user account not found' do
      let(:task) { Rake::Task['user_credential:lock_account'] }
      let(:namespace) { '[UserCredential::UserAccount lock]' }
      let(:expected_output) do
        "#{namespace} rake task start, context: {\"icn\":\"invalid\",\"requested_by\":\"#{requested_by}\"}\n" \
          "#{namespace} failed - Record not found\n"
      end

      before { task.reenable }

      it 'logs an error message when UserAccount is not found' do
        expect { task.invoke('invalid', requested_by) }.to output(expected_output).to_stdout
      end
    end
  end
end
