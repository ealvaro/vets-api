# frozen_string_literal: true

require 'rails_helper'
require 'bpds/monitor'

RSpec.describe BPDS::Monitor do
  let(:monitor) { described_class.new }
  let(:claim_id) { 123 }
  let(:form_id) { 'Form-XYZ' }
  let(:bpds_uuid) { 'abc-123' }
  let(:error) { StandardError.new('Something went wrong') }
  let(:user_type) { 'loa3' }
  let(:lookup_service) { 'mpi' }
  let(:is_pid_present) { true }
  let(:is_ssn_present) { true }
  let(:is_file_number_present) { false }

  describe '#track_service_begun' do
    it 'tracks the service begun event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} begun for saved_claim ##{claim_id}",
        'api.bpds_service.service_json.begun',
        call_location: instance_of(Thread::Backtrace::Location),
        claim_id:,
        form_id:
      )
      monitor.track_service_begun(claim_id, form_id)
    end
  end

  describe '#track_submit_begun' do
    it 'tracks the submit begun event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} submit begun for saved_claim ##{claim_id}",
        'api.bpds_service.submit_json.begun',
        call_location: instance_of(Thread::Backtrace::Location),
        claim_id:,
        form_id:,
        edipi_present: true,
        file_number_present: true,
        icn_present: false,
        participant_id_present: true,
        ssn_present: false
      )

      monitor.track_submit_begun(claim_id, form_id, {
                                   participant_id_present: true,
                                   file_number_present: true,
                                   ssn_present: false,
                                   icn_present: false,
                                   edipi_present: true
                                 })
    end
  end

  describe '#track_submit_success' do
    it 'tracks the submit success event with bpds_uuid' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} submit succeeded for saved_claim ##{claim_id}",
        'api.bpds_service.submit_json.success',
        call_location: instance_of(Thread::Backtrace::Location),
        claim_id:,
        form_id:,
        bpds_uuid:
      )
      monitor.track_submit_success(claim_id, form_id, bpds_uuid)
    end

    it 'tracks the submit success event without bpds_uuid' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} submit succeeded for saved_claim ##{claim_id}",
        'api.bpds_service.submit_json.success',
        call_location: instance_of(Thread::Backtrace::Location),
        claim_id:,
        form_id:,
        bpds_uuid: nil
      )
      monitor.track_submit_success(claim_id, form_id)
    end
  end

  describe '#track_submit_failure' do
    it 'tracks the submit failure event' do
      expect(monitor).to receive(:track_request).with(
        :error,
        "#{BPDS::Monitor::SERVICE_NAME} submit failed for saved_claim ##{claim_id}",
        'api.bpds_service.submit_json.failure',
        call_location: instance_of(Thread::Backtrace::Location),
        claim_id:,
        form_id:,
        error: error.message,
        errors: nil
      )
      monitor.track_submit_failure(claim_id, form_id, error)
    end
  end

  describe '#track_get_json_begun' do
    it 'tracks the get_json begun event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} get_json begun for bpds_uuid ##{bpds_uuid}",
        'api.bpds_service.get_json_by_bpds_uuid.begun',
        call_location: instance_of(Thread::Backtrace::Location),
        bpds_uuid:
      )
      monitor.track_get_json_begun(bpds_uuid)
    end
  end

  describe '#track_get_json_success' do
    it 'tracks the get_json success event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} get_json succeeded for bpds_uuid ##{bpds_uuid}",
        'api.bpds_service.get_json_by_bpds_uuid.success',
        call_location: instance_of(Thread::Backtrace::Location),
        bpds_uuid:
      )
      monitor.track_get_json_success(bpds_uuid)
    end
  end

  describe '#track_get_json_failure' do
    it 'tracks the get_json failure event' do
      expect(monitor).to receive(:track_request).with(
        :error,
        "#{BPDS::Monitor::SERVICE_NAME} get_json failed for bpds_uuid ##{bpds_uuid}",
        'api.bpds_service.get_json_by_bpds_uuid.failure',
        call_location: instance_of(Thread::Backtrace::Location),
        bpds_uuid:,
        error: error.message,
        errors: nil
      )
      monitor.track_get_json_failure(bpds_uuid, error)
    end
  end

  describe '#track_get_user_identifier' do
    it 'tracks the get_user_identifier lookup event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} #{user_type} user identifier lookup for BPDS",
        'api.bpds_service.get_participant_id',
        call_location: instance_of(Thread::Backtrace::Location),
        tags: ["user_type:#{user_type}"]
      )
      monitor.track_get_user_identifier(user_type)
    end
  end

  describe '#track_get_user_identifier_result' do
    it 'tracks the get_user_identifier result event' do
      result_str = "#{is_pid_present}, #{is_ssn_present}"
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} #{lookup_service} service participant_id lookup result: #{result_str}",
        'api.bpds_service.get_participant_id.mpi.result',
        call_location: instance_of(Thread::Backtrace::Location),
        lookup_service:,
        tags: ["pid_present:#{is_pid_present}", "ssn_present:#{is_ssn_present}"],
        is_pid_present:,
        is_ssn_present:
      )
      monitor.track_get_user_identifier_result(lookup_service, is_pid_present, is_ssn_present)
    end
  end

  describe '#track_get_user_identifier_result_file_number' do
    it 'tracks the get_user_identifier file number result event' do
      expect(monitor).to receive(:track_request).with(
        :info,
        "#{BPDS::Monitor::SERVICE_NAME} BGS service file_number lookup result: #{is_file_number_present}",
        'api.bpds_service.get_file_number.bgs.result',
        call_location: instance_of(Thread::Backtrace::Location),
        tags: ["file_number_present:#{is_file_number_present}"]
      )
      monitor.track_get_user_identifier_file_number_result(is_file_number_present)
    end
  end

  describe '#track_skip_bpds_job' do
    context 'with a nil user' do
      it 'tracks the skip_bpds_job event' do
        expect(monitor).to receive(:track_request).with(
          :info,
          "#{BPDS::Monitor::SERVICE_NAME} No user identifier found, skipping BPDS job for saved_claim #{claim_id}",
          'api.bpds_service.job_skipped_missing_identifier',
          call_location: instance_of(Thread::Backtrace::Location),
          claim_id:,
          form_id:,
          user_is_present: false,
          user_is_nil: true,
          user_class: 'NilClass',
          user_has_icn: false,
          claim_has_user_account_id: false,
          claim_has_user_account: false
        )
        monitor.track_skip_bpds_job(claim_id, form_id, nil)
      end
    end

    context 'with a non-nil user' do
      let(:user) { build(:user) }

      it 'tracks the skip_bpds_job event' do
        # doing this "multi-line" string thing just to get around
        # rubocop line length rule
        expected_message = "#{BPDS::Monitor::SERVICE_NAME} No user identifier found but user is present,"
        expected_message += " skipping BPDS job for saved_claim #{claim_id}"

        expect(monitor).to receive(:track_request).with(
          :info,
          expected_message,
          'api.bpds_service.job_skipped_missing_identifier',
          call_location: instance_of(Thread::Backtrace::Location),
          claim_id:,
          form_id:,
          user_is_present: true,
          user_is_nil: false,
          user_class: 'User',
          user_has_icn: true,
          claim_has_user_account_id: false,
          claim_has_user_account: false
        )
        monitor.track_skip_bpds_job(claim_id, form_id, user)
      end
    end
  end
end
