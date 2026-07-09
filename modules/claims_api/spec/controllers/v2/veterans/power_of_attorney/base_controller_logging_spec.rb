# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController Logging', type: :controller do
  controller(ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController) do
    def index
      head :ok
    end
  end

  describe '#log_mpi_lookup_failure' do
    it 'logs with warn level and correct statsd key for claimant' do
      error = ArgumentError.new('Required values missing: [:edipi]')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        level: :warn,
        message: 'MPI lookup failed for claimant',
        statsd_key: 'claims_api.poa.mpi_claimant_lookup_failure',
        error_class: 'ArgumentError',
        error_message: 'Required values missing: [:edipi]'
      )

      controller.send(:log_mpi_lookup_failure, error, 'claimant')
    end

    it 'logs with warn level and correct statsd key for veteran' do
      error = MPI::Errors::ArgumentError.new('Invalid ICN format')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        level: :warn,
        message: 'MPI lookup failed for veteran',
        statsd_key: 'claims_api.poa.mpi_veteran_lookup_failure',
        error_class: 'MPI::Errors::ArgumentError',
        error_message: 'Invalid ICN format'
      )

      controller.send(:log_mpi_lookup_failure, error, 'veteran')
    end

    it 'includes error class and message as separate fields' do
      error = ArgumentError.new('Custom error message')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        hash_including(
          level: :warn,
          error_class: 'ArgumentError',
          error_message: 'Custom error message',
          statsd_key: include('mpi_claimant_lookup_failure')
        )
      )

      controller.send(:log_mpi_lookup_failure, error, 'claimant')
    end
  end

  describe '#log_mpi_lookup_error' do
    it 'logs with error level and correct statsd key for claimant' do
      error = StandardError.new('Unexpected MPI service error')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        level: :error,
        message: 'Unexpected error during MPI claimant lookup',
        statsd_key: 'claims_api.poa.mpi_claimant_lookup_error',
        error_class: 'StandardError',
        error_message: 'Unexpected MPI service error'
      )

      controller.send(:log_mpi_lookup_error, error, 'claimant')
    end

    it 'logs with error level and correct statsd key for veteran' do
      error = StandardError.new('Connection timeout')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        level: :error,
        message: 'Unexpected error during MPI veteran lookup',
        statsd_key: 'claims_api.poa.mpi_veteran_lookup_error',
        error_class: 'StandardError',
        error_message: 'Connection timeout'
      )

      controller.send(:log_mpi_lookup_error, error, 'veteran')
    end

    it 'includes error class and message as separate fields' do
      error = StandardError.new('Test error')

      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        hash_including(
          level: :error,
          statsd_key: include('mpi_veteran_lookup_error'),
          error_class: 'StandardError',
          error_message: 'Test error'
        )
      )

      controller.send(:log_mpi_lookup_error, error, 'veteran')
    end
  end

  describe '#fetch_claimant' do
    context 'when claimant_icn is blank' do
      it 'returns nil without calling MPI service' do
        allow(controller).to receive(:claimant_icn).and_return(nil)

        expect(controller).not_to receive(:mpi_service)

        result = controller.send(:fetch_claimant)
        expect(result).to be_nil
      end
    end

    context 'when MPI service raises ArgumentError' do
      it 'logs the failure and returns nil' do
        claimant_icn = '1013062086V794840'
        mpi_service = instance_double(MPI::Service)

        allow(controller).to receive_messages(claimant_icn:, mpi_service:)
        allow(mpi_service).to receive(:find_profile_by_identifier)
          .and_raise(ArgumentError.new('Required values missing: [:edipi]'))

        expect(ClaimsApi::Logger).to receive(:log).with(
          'POABaseController',
          hash_including(
            level: :warn,
            statsd_key: 'claims_api.poa.mpi_claimant_lookup_failure'
          )
        )

        result = controller.send(:fetch_claimant)
        expect(result).to be_nil
      end
    end

    context 'when MPI service raises MPI::Errors::ArgumentError' do
      it 'logs the failure and returns nil' do
        claimant_icn = '1013062086V794840'
        mpi_service = instance_double(MPI::Service)

        allow(controller).to receive_messages(claimant_icn:, mpi_service:)
        allow(mpi_service).to receive(:find_profile_by_identifier)
          .and_raise(MPI::Errors::ArgumentError.new('Invalid ICN'))

        expect(ClaimsApi::Logger).to receive(:log).with(
          'POABaseController',
          hash_including(
            level: :warn,
            statsd_key: 'claims_api.poa.mpi_claimant_lookup_failure'
          )
        )

        result = controller.send(:fetch_claimant)
        expect(result).to be_nil
      end
    end

    context 'when MPI service raises generic error' do
      it 'logs the error with error level and returns nil' do
        claimant_icn = '1013062086V794840'
        mpi_service = instance_double(MPI::Service)

        allow(controller).to receive_messages(claimant_icn:, mpi_service:)
        allow(mpi_service).to receive(:find_profile_by_identifier)
          .and_raise(StandardError.new('Connection timeout'))

        expect(ClaimsApi::Logger).to receive(:log).with(
          'POABaseController',
          hash_including(
            level: :error,
            statsd_key: 'claims_api.poa.mpi_claimant_lookup_error'
          )
        )

        result = controller.send(:fetch_claimant)
        expect(result).to be_nil
      end
    end

    context 'when MPI service returns successfully' do
      it 'returns the MPI profile' do
        claimant_icn = '1013062086V794840'
        mpi_profile = double('MPI::Responses::FindProfileResponse', status: :ok)
        mpi_service = instance_double(MPI::Service)

        allow(controller).to receive_messages(claimant_icn:, mpi_service:)
        allow(mpi_service).to receive(:find_profile_by_identifier)
          .and_return(mpi_profile)

        expect(ClaimsApi::Logger).not_to receive(:log)

        result = controller.send(:fetch_claimant)
        expect(result).to eq(mpi_profile)
      end
    end
  end

  describe '#handle_metadata_validation_failure' do
    let(:metadata_errors) { ['invalid at /veteran: schema violation'] }

    context 'when error is metadata validation for PowerOfAttorneyRequest' do
      let(:record) { ClaimsApi::PowerOfAttorneyRequest.new }
      let(:record_invalid_error) { ActiveRecord::RecordInvalid.new(record) }

      before do
        record.errors.add(:metadata, metadata_errors.first)
      end

      it 'logs details and raises a generic Lighthouse unprocessable entity error' do
        allow(Flipper).to receive(:enabled?)
          .with(:lighthouse_claims_api_v2_poa_request_internal_validation_alerting)
          .and_return(true)

        expect(controller).to receive(:claims_v2_logging).with(
          'power_of_attorney_request_metadata_validation_failed',
          level: :warn,
          message: { metadata_schema_errors: metadata_errors }.to_json
        )

        expect(controller).to receive(:request_slack_alert).with(
          'POA Create Request',
          'POA Internal Validation Error During Create Request with ' \
          'metadata_errors: invalid at /veteran: schema violation'
        )

        expect(controller).to receive(:render_error) do |error|
          expect(error).to be_a(ClaimsApi::Common::Exceptions::Lighthouse::UnprocessableEntity)
          expect(error.errors.first[:detail]).to eq(
            'Unable to process Power of Attorney request due to internal validation error.'
          )
        end

        controller.send(:handle_metadata_validation_failure, record_invalid_error)
      end

      it 'does not send Slack alert when flag is disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:lighthouse_claims_api_v2_poa_request_internal_validation_alerting)
          .and_return(false)

        expect(controller).to receive(:claims_v2_logging)
        expect(controller).not_to receive(:request_slack_alert)
        expect(controller).to receive(:render_error)

        controller.send(:handle_metadata_validation_failure, record_invalid_error)
      end
    end

    context 'when error is not a metadata schema validation failure' do
      let(:record) { ClaimsApi::PowerOfAttorneyRequest.new }
      let(:record_invalid_error) { ActiveRecord::RecordInvalid.new(record) }

      it 're-raises the original RecordInvalid error and does not log metadata validation failure' do
        expect(controller).not_to receive(:claims_v2_logging)

        expect do
          controller.send(:handle_metadata_validation_failure, record_invalid_error)
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
