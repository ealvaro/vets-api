# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Login::AfterLoginActions do
  subject(:after_login_actions) { described_class.new(user) }

  describe '#perform' do
    before do
      allow(Identity::LogUserVeteranStatusJob).to receive(:perform_async)
    end

    context 'creating credential email' do
      let(:user) { create(:user, email:) }
      let(:email) { 'some-email' }

      it 'creates a user credential email with expected attributes' do
        expect { after_login_actions.perform }.to change(UserCredentialEmail, :count)
        user_credential_email = user.user_verification.user_credential_email
        expect(user_credential_email.credential_email).to eq(email)
      end

      it 'enqueues user veteran status logging job' do
        after_login_actions.perform

        expect(Identity::LogUserVeteranStatusJob).to have_received(:perform_async).with(user.uuid)
      end
    end

    context 'in a non-staging environment' do
      let(:user) { create(:user) }

      around do |example|
        with_settings(Settings.test_user_dashboard, env: 'production') do
          example.run
        end
      end

      it 'does not call TUD account checkout' do
        expect_any_instance_of(TestUserDashboard::UpdateUser).not_to receive(:call)
        after_login_actions.perform
      end
    end

    context 'in a staging environment' do
      let(:user) { create(:user) }

      around do |example|
        with_settings(Settings.test_user_dashboard, env: 'staging') do
          example.run
        end
      end

      it 'calls TUD account checkout' do
        expect_any_instance_of(TestUserDashboard::UpdateUser).to receive(:call)
        after_login_actions.perform
      end
    end

    context 'UserIdentity & MPI ID validations' do
      let(:mpi_profile) { build(:mpi_profile) }
      let(:loa3_user) { build(:user, :loa3, mpi_profile:) }
      let(:expected_error_data) do
        { identity_value: expected_identity_value, mpi_value: expected_mpi_value, icn: loa3_user.icn,
          safe_keys: [:icn] }
      end
      let(:expected_error_message) do
        "[SessionsController version:v1] User Identity & MPI #{validation_id} values conflict"
      end

      before do
        allow(Rails.logger).to receive(:warn)
      end

      shared_examples 'identity-mpi id validation' do
        it 'logs a warning when Identity & MPI values conflict' do
          expect(Rails.logger).to receive(:warn).at_least(:once).with(expected_error_message, expected_error_data)
          described_class.new(loa3_user).perform
        end
      end

      context 'ssn validation' do
        let(:mpi_profile) { build(:mpi_profile, { ssn: Faker::Number.number(digits: 9) }) }
        let(:expected_identity_value) { loa3_user.identity.ssn }
        let(:expected_mpi_value) { loa3_user.ssn_mpi }
        let(:validation_id) { 'SSN' }
        let(:expected_error_data) { { icn: loa3_user.icn, safe_keys: [:icn] } }

        it_behaves_like 'identity-mpi id validation'
      end

      context 'edipi validation' do
        let(:mpi_profile) { build(:mpi_profile, { edipi: Faker::Number.number(digits: 10) }) }
        let(:expected_identity_value) { loa3_user.identity.edipi }
        let(:expected_mpi_value) { loa3_user.edipi_mpi }
        let(:validation_id) { 'EDIPI' }

        it_behaves_like 'identity-mpi id validation'
      end

      context 'icn validation' do
        let(:mpi_profile) { build(:mpi_profile, { icn: '1234567V01112538' }) }
        let(:expected_identity_value) { loa3_user.identity.icn }
        let(:expected_mpi_value) { loa3_user.mpi_icn }
        let(:validation_id) { 'ICN' }

        it_behaves_like 'identity-mpi id validation'
      end
    end

    context 'when the user can provision Cerner' do
      let(:user) { create(:user, :loa3, cerner_id: 'some-cerner-id', cerner_facility_ids:) }
      let(:stub_cerner_facility_ids) { '123, 456' }

      before do
        allow(Identity::CernerProvisionerJob).to receive(:perform_async)
        allow(Settings.mhv.oh_facility_checks)
          .to receive(:pretransitioned_oh_facilities)
          .and_return(stub_cerner_facility_ids)
      end

      context 'fully eligible user' do
        let(:live_facility_id) { stub_cerner_facility_ids.split(', ').first }

        let(:cerner_facility_ids) { [live_facility_id] }

        it 'enqueues CernerProvisionerJob with messaging_only: false' do
          after_login_actions.perform

          expect(Identity::CernerProvisionerJob).to have_received(:perform_async)
            .with(user.icn, false, :ssoe)
        end
      end

      context 'messaging-only user' do
        let(:cerner_facility_ids) { ['some-non-pretransitioned-facility'] }

        it 'enqueues CernerProvisionerJob with messaging_only: true' do
          after_login_actions.perform

          expect(Identity::CernerProvisionerJob).to have_received(:perform_async)
            .with(user.icn, true, :ssoe)
        end
      end
    end
  end
end
