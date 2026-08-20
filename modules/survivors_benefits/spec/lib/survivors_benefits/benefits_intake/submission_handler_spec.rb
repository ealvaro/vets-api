# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/benefits_intake/submission_handler'
require 'survivors_benefits/monitor'
require 'survivors_benefits/notification_email'
require 'bpds/sidekiq/submit_to_bpds_job'
require 'bpds/monitor'

RSpec.describe SurvivorsBenefits::BenefitsIntake::SubmissionHandler do
  let(:handler) { SurvivorsBenefits::BenefitsIntake::SubmissionHandler }
  let(:claim) { double(form_id: 'TEST', id: 23) }
  let(:monitor) { double(SurvivorsBenefits::Monitor) }
  let(:notification) { double(SurvivorsBenefits::NotificationEmail) }
  let(:instance) { handler.new('fake-claim-id') }

  before do
    allow(SurvivorsBenefits::SavedClaim).to receive(:find).and_return claim
    allow(SurvivorsBenefits::Monitor).to receive(:new).and_return monitor
    allow(SurvivorsBenefits::NotificationEmail).to receive(:new).with(claim.id).and_return notification
  end

  describe '.pending_attempts' do
    let(:submission_attempt) { double('Lighthouse::SubmissionAttempt') }
    let(:submission) { double('Lighthouse::Submission', form_id: '21P-534EZ') }

    before do
      allow(Lighthouse::SubmissionAttempt).to receive(:joins).with(:submission)
                                                             .and_return(Lighthouse::SubmissionAttempt)
      allow(Lighthouse::SubmissionAttempt).to receive(:where).with(status: 'pending',
                                                                   'lighthouse_submissions.form_id' => '21P-534EZ')
                                                             .and_return([submission_attempt])
    end

    it 'returns pending submission attempts with the correct form_id' do
      result = handler.pending_attempts
      expect(result).to eq([submission_attempt])
    end

    it 'queries with the correct status and form_id' do
      expect(Lighthouse::SubmissionAttempt).to receive(:joins).with(:submission)
      expect(Lighthouse::SubmissionAttempt).to receive(:where).with(status: 'pending',
                                                                    'lighthouse_submissions.form_id' => '21P-534EZ')
      handler.pending_attempts
    end
  end

  describe '#on_failure' do
    it 'logs silent failure avoided' do
      expect(notification).to receive(:deliver).with(:error).and_return true
      expect(monitor).to receive(:log_silent_failure_avoided).with(hash_including(claim_id: claim.id),
                                                                   call_location: nil)
      instance.handle(:failure)
    end

    it 'logs silent failure' do
      expect(notification).to receive(:deliver).with(:error).and_return false
      message = "#{handler}: on_failure silent failure not avoided"
      expect(monitor).to receive(:log_silent_failure).with(hash_including(message:), call_location: nil)
      expect { instance.handle(:failure) }.to raise_error message
    end
  end

  describe '#on_success' do
    it 'sends a received email' do
      # Keep this example focused on email delivery; the after-VBMS BPDS path is
      # exercised separately below, so gate it off here.
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:survivors_benefits_bpds_submit_after_vbms).and_return(false)
      expect(notification).to receive(:deliver).with(:received)
      expect(instance.handle(:success)).to be true
    end

    context 'after-VBMS BPDS submission' do
      let(:bpds_monitor) { instance_double(BPDS::Monitor) }
      let(:mpi_profile) do
        double('MPI::Models::MviProfile', participant_id: '600061742', ssn: '111223333', edipi: '1005079124')
      end
      let(:mpi_response) { double('MPI::Responses::FindProfileResponse', profile: mpi_profile) }
      let(:user_account) { double('UserAccount', icn: '1012667122V019349') }

      before do
        allow(BPDS::Monitor).to receive(:new).and_return(bpds_monitor)
        allow(bpds_monitor).to receive(:track_service_begun)
        allow(bpds_monitor).to receive(:track_submit_begun)
        allow(bpds_monitor).to receive(:track_get_user_identifier)
        allow(bpds_monitor).to receive(:track_get_user_identifier_result)
        allow(bpds_monitor).to receive(:track_get_user_identifier_file_number_result)
        allow(bpds_monitor).to receive(:track_skip_bpds_job)
        allow(notification).to receive(:deliver).with(:received)
        allow(BPDS::Sidekiq::SubmitToBPDSJob).to receive(:perform_async)

        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:bpds_service_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_bpds_service_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_bpds_submit_after_vbms).and_return(true)
      end

      context 'when the after-VBMS flag is off' do
        before do
          allow(Flipper).to receive(:enabled?).with(:survivors_benefits_bpds_submit_after_vbms).and_return(false)
        end

        it 'does not enqueue a BPDS submission' do
          expect(BPDS::Sidekiq::SubmitToBPDSJob).not_to receive(:perform_async)
          expect(notification).to receive(:deliver).with(:received)
          expect(instance.handle(:success)).to be true
        end
      end

      context 'when the claim has a user_account with an ICN' do
        before do
          allow(claim).to receive_messages(user_account:, parsed_form: { 'vaFileNumber' => '111223333' })
        end

        it 'resolves identifiers via MPI and enqueues the BPDS job' do
          expect_any_instance_of(MPI::Service).to receive(:find_profile_by_identifier)
            .with(identifier: user_account.icn, identifier_type: MPI::Constants::ICN)
            .and_return(mpi_response)
          expect(bpds_monitor).to receive(:track_get_user_identifier).with('loa3').once
          expect(bpds_monitor).to receive(:track_get_user_identifier_result).with('mpi', true, true).once
          expect(bpds_monitor).to receive(:track_get_user_identifier_file_number_result).with(true).once
          expect(bpds_monitor).to receive(:track_submit_begun)
            .with(claim.id, claim.form_id, hash_including(participant_id_present: true, icn_present: true,
                                                          ssn_present: true)).once
          expect(BPDS::Sidekiq::SubmitToBPDSJob).to receive(:perform_async).once

          expect(instance.handle(:success)).to be true
        end
      end

      context 'when the claim has no user_account but vaFileNumber is on the form' do
        before do
          allow(claim).to receive_messages(user_account: nil, parsed_form: { 'vaFileNumber' => '111223333' })
        end

        it 'falls back to the form file_number and enqueues the BPDS job' do
          expect_any_instance_of(MPI::Service).not_to receive(:find_profile_by_identifier)
          expect(bpds_monitor).to receive(:track_get_user_identifier_file_number_result).with(true).once
          expect(bpds_monitor).to receive(:track_submit_begun)
            .with(claim.id, claim.form_id, hash_including(file_number_present: true)).once
          expect(BPDS::Sidekiq::SubmitToBPDSJob).to receive(:perform_async).once

          expect(instance.handle(:success)).to be true
        end
      end

      context 'when only veteranSocialSecurityNumber is on the form' do
        before do
          allow(claim).to receive_messages(
            user_account: nil,
            parsed_form: { 'veteranSocialSecurityNumber' => '987654321' }
          )
        end

        it 'uses SSN as the file_number fallback' do
          expect(bpds_monitor).to receive(:track_get_user_identifier_file_number_result).with(true).once
          expect(BPDS::Sidekiq::SubmitToBPDSJob).to receive(:perform_async).once

          expect(instance.handle(:success)).to be true
        end
      end

      context 'when the claim has no user_account and no identifiers on the form' do
        before do
          allow(claim).to receive_messages(user_account: nil, parsed_form: {})
        end

        it 'tracks the skip and does not enqueue' do
          expect(bpds_monitor).to receive(:track_get_user_identifier_file_number_result).with(false).once
          expect(bpds_monitor).to receive(:track_skip_bpds_job).with(claim.id, claim.form_id, nil).once
          expect(BPDS::Sidekiq::SubmitToBPDSJob).not_to receive(:perform_async)

          expect(instance.handle(:success)).to be true
        end
      end

      context 'when the BPDS submission raises (BPDS is experimental and must not disrupt the flow)' do
        before do
          allow(bpds_monitor).to receive(:track_submit_failure)
          allow(claim).to receive_messages(user_account:, parsed_form: { 'vaFileNumber' => '111223333' })
          allow_any_instance_of(MPI::Service).to receive(:find_profile_by_identifier)
            .and_raise(StandardError.new('MPI boom'))
        end

        it 'swallows the error, tracks the failure, and still completes on_success' do
          expect(notification).to receive(:deliver).with(:received)
          expect(bpds_monitor).to receive(:track_submit_failure).with(claim.id, claim.form_id,
                                                                      instance_of(StandardError)).once
          expect(BPDS::Sidekiq::SubmitToBPDSJob).not_to receive(:perform_async)

          expect(instance.handle(:success)).to be true
        end
      end
    end
  end

  describe '#on_stale' do
    it 'does nothing' do
      # pass thru for coverage
      expect(instance.handle(:stale)).to be true
    end
  end
end
