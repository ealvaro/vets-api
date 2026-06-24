# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form210779SubmissionEmailJob, type: :job do
  subject(:perform_job) { described_class.new.perform(claim.id) }

  let(:claim) { create(:va210779) }
  let(:notify_client) { instance_double(VaNotify::Service) }
  let(:mpi_service) { instance_double(MPI::Service) }
  let(:mpi_profile) { double('MPIProfile', icn: '123456789V123456') }
  let(:mpi_response) { double('MPIResponse', ok?: true, profile: mpi_profile) }

  before do
    allow(MPI::Service).to receive(:new).and_return(mpi_service)
    allow(mpi_service).to receive(:find_profile_by_attributes).and_return(mpi_response)

    allow(VaNotify::Service).to receive(:new).and_return(notify_client)
    allow(notify_client).to receive(:send_email)

    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#perform' do
    context 'when successful' do
      it 'looks up MPI profile and sends VA Notify email to veteran ICN' do
        perform_job

        expect(mpi_service).to have_received(:find_profile_by_attributes).with(
          first_name: 'John',
          last_name: 'Doe',
          birth_date: '1990-01-01',
          ssn: '123456789'
        )

        expect(VaNotify::Service).to have_received(:new).with(
          Settings.vanotify.services.bio_aquia.api_key
        )

        expect(notify_client).to have_received(:send_email).with(
          recipient_identifier: { id_value: '123456789V123456', id_type: 'ICN' },
          template_id: Settings.vanotify.services.bio_aquia.template_id.form_0779_submission_email,
          personalisation: {
            'first_name' => 'John',
            'date_submitted' => kind_of(String),
            'form_name' => '21-0779'
          }
        )

        expect(StatsD).to have_received(:increment).with('api.form210779.email.sent')
        expect(Rails.logger).to have_received(:info).with(
          'Form210779SubmissionEmailJob confirmation email sent',
          hash_including(saved_claim_id: claim.id, claim_guid: claim.guid)
        )
      end
    end

    context 'when claim not found' do
      it 'logs warning, tracks metric, and does not retry' do
        expect do
          described_class.new.perform(999_999)
        end.not_to raise_error

        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.claim_not_found')
        expect(Rails.logger).to have_received(:warn).with(
          'Form210779SubmissionEmailJob claim not found',
          hash_including(saved_claim_id: 999_999, error: 'ActiveRecord::RecordNotFound')
        )
      end
    end

    context 'when template ID is missing' do
      before do
        allow(Settings.vanotify.services.bio_aquia.template_id).to receive(:form_0779_submission_email)
          .and_return(nil)
      end

      it 'does not send email and tracks missing template metric' do
        perform_job

        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.missing_template_id')
        expect(Rails.logger).to have_received(:error).with(
          'Form210779SubmissionEmailJob missing template_id for form_0779_submission_email'
        )
      end
    end

    context 'when API key is missing' do
      before do
        allow(Settings.vanotify.services.bio_aquia).to receive(:api_key).and_return(nil)
      end

      it 'does not send email and tracks missing_api_key metric' do
        perform_job

        expect(VaNotify::Service).not_to have_received(:new)
        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.missing_api_key')
        expect(Rails.logger).to have_received(:error).with(
          'Form210779SubmissionEmailJob missing vanotify api_key'
        )
      end
    end

    context 'when MPI lookup fails' do
      before do
        allow(mpi_service).to receive(:find_profile_by_attributes).and_return(
          double('MPIResponse', ok?: false, profile: nil)
        )
      end

      it 'does not send email and tracks mpi_lookup_failure metric' do
        perform_job

        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.mpi_lookup_failure')
        expect(Rails.logger).to have_received(:error).with(
          'Form210779SubmissionEmailJob MPI lookup failed',
          hash_including(saved_claim_id: claim.id, claim_guid: claim.guid)
        )
      end
    end

    context 'when MPI lookup raises an exception' do
      let(:mpi_error) { StandardError.new('MPI service unavailable') }

      before do
        allow(mpi_service).to receive(:find_profile_by_attributes).and_raise(mpi_error)
      end

      it 'does not send email and tracks mpi_lookup_error metric' do
        perform_job

        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.mpi_lookup_error')
        expect(Rails.logger).to have_received(:error).with(
          'Form210779SubmissionEmailJob MPI lookup error',
          {
            error: 'StandardError',
            saved_claim_id: claim.id
          }
        )
        expect(StatsD).not_to have_received(:increment).with('api.form210779.email.mpi_lookup_failure')
      end
    end

    context 'when feature flag is disabled at perform time' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form_0779_submission_email_notification).and_return(false)
      end

      it 'exits early without calling MPI or VA Notify' do
        perform_job

        expect(mpi_service).not_to have_received(:find_profile_by_attributes)
        expect(notify_client).not_to have_received(:send_email)
        expect(StatsD).to have_received(:increment).with('api.form210779.email.skipped_feature_flag')
      end
    end

    context 'when VA Notify send_email fails' do
      let(:notify_error) { Common::Exceptions::BackendServiceException.new('VANotify error') }

      before do
        allow(notify_client).to receive(:send_email).and_raise(notify_error)
      end

      it 'tracks failure, logs error, and re-raises for Sidekiq retry' do
        expect do
          perform_job
        end.to raise_error(Common::Exceptions::BackendServiceException)

        expect(StatsD).to have_received(:increment).with('api.form210779.email.send_failure')
        expect(Rails.logger).to have_received(:error).with(
          'Form210779SubmissionEmailJob failed to send confirmation email',
          hash_including(
            error: 'Common::Exceptions::BackendServiceException',
            saved_claim_id: claim.id
          )
        )
      end
    end
  end

  describe 'retry configuration' do
    it 'retries up to 14 times' do
      expect(described_class.sidekiq_options_hash['retry']).to eq(14)
    end

    it 'uses low queue' do
      expect(described_class.sidekiq_options_hash['queue']).to eq('low')
    end
  end
end
