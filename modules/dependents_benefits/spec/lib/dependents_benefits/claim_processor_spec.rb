# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/claim_processor'

RSpec.describe DependentsBenefits::ClaimProcessor, type: :model do
  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow(DependentsBenefits::Monitor).to receive(:new).and_return(mock_monitor)
    allow(mock_monitor).to receive(:track_info_event)
    allow(mock_monitor).to receive(:track_error_event)

    allow_any_instance_of(SavedClaim).to receive(:pdf_overflow_tracking)
    allow(processor).to receive(:collect_child_claims).and_return([form_686_claim, form_674_claim])
  end

  let(:component) { described_class.name }
  let(:parent_claim) { create(:dependents_claim) }
  let(:form_674_claim) { create(:student_claim) }
  let(:form_686_claim) { create(:add_remove_dependents_claim) }
  let(:parent_claim_id) { parent_claim.id }
  let(:proc_id) { 'proc-123-456' }
  let(:processor) { described_class.new(parent_claim_id) }
  let(:mock_monitor) { instance_double(DependentsBenefits::Monitor) }

  describe '.enqueue_submissions' do
    it 'creates processor instance and delegates to instance method' do
      expect(described_class).to receive(:new).with(parent_claim_id).and_return(processor)
      expect(processor).to receive(:enqueue_submissions)
      described_class.enqueue_submissions(parent_claim_id)
    end
  end

  describe '#enqueue_submissions' do
    let!(:parent_group) { create(:parent_claim_group, parent_claim:) }
    let(:parent_claim_user_uuid) { JSON.parse(parent_group.user_data).dig('veteran_information', 'uuid') }

    before do
      allow(DependentsBenefits::Sidekiq::BGSFormJob).to receive(:perform_async).and_return(true)
      allow(DependentsBenefits::Sidekiq::ClaimsApiJob).to receive(:perform_async).and_return(true)
      allow(DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob).to receive(:perform_async).and_return(
        true
      )
      allow(processor).to receive(:collect_child_claims).and_return([form_686_claim, form_674_claim])
    end

    context 'with enable_dependents_claims_api_job feature active' do
      before do
        allow(Flipper).to receive(:enabled?).with(:enable_dependents_claims_api_job).and_return(true)
      end

      it 'processes claims' do
        jobs = {
          DependentsBenefits::Sidekiq::ClaimsApiJob => [parent_claim_id],
          DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob => [parent_claim_id]
        }

        jobs.each do |job, args|
          expect(job).to receive(:perform_async).with(*args)
        end
        expect(DependentsBenefits::Sidekiq::BGSFormJob).not_to receive(:perform_async)

        processor.enqueue_submissions
      end

      it 'monitors submissions' do
        processor.enqueue_submissions
        expect(mock_monitor).to have_received(:track_info_event).with(
          'Starting claim submission processing',
          action: 'start',
          component:,
          parent_claim_id:
        )
        expect(mock_monitor).to have_received(:track_info_event).with(
          'Successfully enqueued all submission jobs',
          action: 'enqueue_success',
          component:,
          parent_claim_id:,
          jobs_count: 2,
          jobs_list: ['DependentsBenefits::Sidekiq::ClaimsApiJob', 'DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob']
        )
      end
    end

    context 'with enable_dependents_claims_api_job feature inactive' do
      before do
        allow(Flipper).to receive(:enabled?).with(:enable_dependents_claims_api_job).and_return(false)
      end

      it 'processes claims' do
        jobs = {
          DependentsBenefits::Sidekiq::BGSFormJob => [parent_claim_id],
          DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob => [parent_claim_id]
        }

        jobs.each do |job, args|
          expect(job).to receive(:perform_async).with(*args)
        end
        expect(DependentsBenefits::Sidekiq::ClaimsApiJob).not_to receive(:perform_async)

        processor.enqueue_submissions
      end

      it 'monitors submissions' do
        processor.enqueue_submissions
        expect(mock_monitor).to have_received(:track_info_event).with(
          'Starting claim submission processing',
          action: 'start',
          component:,
          parent_claim_id:
        )
        expect(mock_monitor).to have_received(:track_info_event).with(
          'Successfully enqueued all submission jobs',
          action: 'enqueue_success',
          component:,
          parent_claim_id:,
          jobs_count: 2,
          jobs_list: ['DependentsBenefits::Sidekiq::BGSFormJob', 'DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob']
        )
      end
    end

    it 'handles enqueue failures' do
      error = StandardError.new('Enqueue failed')
      allow(mock_monitor).to receive(:track_info_event).and_raise(error)

      expect(processor).to receive(:mark_parent_group_failed)
      expect { processor.enqueue_submissions }.to raise_error(StandardError, 'Enqueue failed')
    end

    it 'marks in-progress form as pending before enqueueing jobs' do
      in_progress_form = instance_double(InProgressForm, submission_pending!: true)
      allow(InProgressForm).to receive(:find_by).with(form_id: '686C-674-V2',
                                                      user_uuid: parent_claim_user_uuid).and_return(in_progress_form)

      processor.enqueue_submissions

      expect(in_progress_form).to have_received(:submission_pending!)
    end
  end

  describe '#collect_child_claims' do
    before do
      allow(processor).to receive(:collect_child_claims).and_call_original
    end

    let!(:parent_group) { create(:parent_claim_group, parent_claim:) }

    it 'tracks and returns child claims' do
      create(:saved_claim_group, saved_claim: form_674_claim, parent_claim:)
      create(:saved_claim_group, saved_claim: form_686_claim, parent_claim:)
      result = processor.send(:collect_child_claims)

      expect(result).to contain_exactly(form_674_claim, form_686_claim)
      expect(mock_monitor).to have_received(:track_info_event).with(
        'Collected child claims for processing',
        action: 'collect_children',
        component:,
        parent_claim_id:,
        child_claims_count: 2
      )
    end

    it 'raises error when no child claims found' do
      # Don't create any child claim groups - only parent group exists
      expect { processor.send(:collect_child_claims) }.to raise_error(
        StandardError, "No child claims found for parent claim #{parent_claim_id}"
      )
    end
  end

  describe 'handle_permanent_failure' do
    let!(:parent_group) { create(:parent_claim_group, parent_claim:) }
    let(:parent_claim_user_uuid) { JSON.parse(parent_group.user_data).dig('veteran_information', 'uuid') }

    it 'logs error' do
      processor.send(:handle_permanent_failure, 'Some error message')
      expect(mock_monitor).to have_received(:track_error_event).with(
        "Error submitting #{component}",
        action: 'error.permanent',
        component:,
        error: 'Some error message',
        parent_claim_id:
      )
    end

    context 'when parent claim group is not completed' do
      it 'marks parent claim group as failed, sends backup job, and clears IPF' do
        parent_group.update(status: SavedClaimGroup::STATUSES[:PROCESSING])
        expect(processor).to receive(:mark_parent_group_failed)
        expect(DependentsBenefits::Sidekiq::BenefitsIntakeJob).to receive(:perform_async)
        expect(InProgressForm).to receive(:destroy_by).with(user_uuid: parent_claim_user_uuid,
                                                            form_id: parent_claim.form_id)
        processor.send(:handle_permanent_failure, 'Some error message')
      end
    end

    context 'when parent claim group is already completed' do
      it 'does not mark parent claim group or send backup job' do
        parent_group.update(status: SavedClaimGroup::STATUSES[:SUCCESS])
        expect(processor).not_to receive(:mark_parent_group_failed)
        expect(processor).not_to receive(:destroy_in_progress_form)
        expect(DependentsBenefits::Sidekiq::BenefitsIntakeJob).not_to receive(:perform_async)
        processor.send(:handle_permanent_failure, 'Some error message')
      end
    end

    it 'sends error notification email and clears IPF on rescue' do
      in_progress_form = instance_double(InProgressForm, submission_pending!: true)
      allow(processor).to receive(:mark_parent_group_failed).and_raise(StandardError.new('DB error'))
      allow_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_error_notification)
      allow(InProgressForm).to receive(:find_by).with(form_id: parent_claim.form_id,
                                                      user_uuid: parent_claim_user_uuid).and_return(in_progress_form)
      expect_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_error_notification)
      expect(in_progress_form).to receive(:submission_pending!)
      expect(mock_monitor).to receive(:log_silent_failure_avoided).with(
        { parent_claim_id:, error: instance_of(StandardError) }
      )
      processor.send(:handle_permanent_failure, 'Some error message')
    end

    it 'logs silent failure if notification email fails' do
      allow(processor).to receive(:mark_parent_group_failed).and_raise(StandardError.new('DB error'))
      allow_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_error_notification).and_raise(
        StandardError.new('Email error')
      )
      expect(mock_monitor).to receive(:log_silent_failure).with(
        { parent_claim_id:, error: instance_of(StandardError) }
      )
      processor.send(:handle_permanent_failure, 'Some error message')
    end
  end

  describe '#handle_successful_submission' do
    let!(:parent_group) { create(:parent_claim_group, parent_claim:) }
    let(:parent_claim_user_uuid) { JSON.parse(parent_group.user_data).dig('veteran_information', 'uuid') }

    it 'logs start of success check' do
      processor.send(:handle_successful_submission)
      expect(mock_monitor).to have_received(:track_info_event).with(
        'Checking if claim submissions succeeded',
        action: 'success_check',
        component:,
        parent_claim_id:
      )
    end

    it 'handles errors during success handling' do
      allow(processor).to receive(:parent_group).and_raise(StandardError.new('DB error'))
      expect(mock_monitor).to receive(:track_error_event).with(
        "Error handling successful submission for #{component}",
        action: 'success.error',
        component:,
        error: instance_of(StandardError),
        parent_claim_id:
      )
      processor.send(:handle_successful_submission)
    end

    context 'when all child claims succeeded' do
      before do
        allow(form_686_claim).to receive(:submissions_succeeded?).and_return(true)
        allow(form_674_claim).to receive(:submissions_succeeded?).and_return(true)
      end

      context 'and parent claim group not completed' do
        before { parent_group.update(status: SavedClaimGroup::STATUSES[:PROCESSING]) }

        it 'marks parent claim group as succeeded, sends received notification, and clears IPF' do
          expect(processor).to receive(:mark_parent_group_succeeded)
          expect_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_received_notification)
          expect(InProgressForm).to receive(:destroy_by).with(user_uuid: parent_claim_user_uuid,
                                                              form_id: parent_claim.form_id)
          processor.send(:handle_successful_submission)
        end

        context 'with pension-related claims' do
          let(:parent_claim) { create(:dependents_claim, :pension_related) }

          before { allow(Flipper).to receive(:enabled?).with(:va_dependents_net_worth_and_pension).and_return(true) }

          it 'tracks pension-related submission for each child claim when parent claim is pension-related' do
            [form_686_claim, form_674_claim].each do |claim|
              expect(mock_monitor).to receive(:track_info_event).with(
                'Successful pension-related claim submission',
                action: 'pension.submission',
                component:,
                claim_id: claim.id,
                form_id: claim.form_id,
                parent_claim_id:,
                form_type: parent_claim.claim_form_type,
                module_stats_key: DependentsBenefits::Monitor::PENSION_SUBMISSION_STATS_KEY
              )
            end
            processor.send(:handle_successful_submission)
          end

          it 'does not track pension-related submission if parent claim is not pension-related' do
            parent_claim.parsed_form['dependents_application']['veteran_information']['is_in_receipt_of_pension'] = 0
            expect(mock_monitor).not_to receive(:track_info_event).with(
              'Successful pension-related claim submission',
              hash_including(action: 'submission', component: 'pension')
            )
            processor.send(:handle_successful_submission)
          end
        end

        context 'with no-SSN claims' do
          let(:no_ssn_claim) do
            claim = create(:add_remove_dependents_claim)
            claim.parsed_form['dependents_application']['children_to_add'] = [{ 'no_ssn' => true }]
            claim
          end

          it 'tracks no-SSN claim submission for a child claim that has no SSN' do
            # Mock all the necessary dependencies to get to the tracking call
            allow(processor).to receive(:child_claims).and_return([no_ssn_claim, form_674_claim])
            allow(no_ssn_claim).to receive_messages(submissions_succeeded?: true)
            allow(form_674_claim).to receive_messages(submissions_succeeded?: true)
            allow(processor).to receive(:mark_parent_group_succeeded)
            allow_any_instance_of(DependentsBenefits::NotificationEmail).to receive(:send_received_notification)

            processor.send(:handle_successful_submission)

            expect(mock_monitor).to have_received(:track_info_event).with(
              'Successful no-SSN claim submission',
              action: 'no_ssn_claim.submission',
              component:,
              claim_id: no_ssn_claim.id,
              form_id: no_ssn_claim.form_id,
              parent_claim_id:,
              form_type: parent_claim.claim_form_type,
              module_stats_key: DependentsBenefits::Monitor::NO_SSN_SUBMISSION_STATS_KEY
            )

            expect(mock_monitor).not_to receive(:track_info_event).with(
              'Successful no-SSN claim submission',
              hash_including(action: 'submission', component: 'pension', claim_id: form_674_claim.id)
            )
          end

          it 'does not track no-SSN submission if no child claims have no SSN' do
            allow(processor).to receive(:child_claims).and_return([form_674_claim])
            allow(form_674_claim).to receive(:no_ssn_claim?).and_return(false)

            processor.send(:handle_successful_submission)

            expect(mock_monitor).not_to have_received(:track_info_event).with(
              'Successful no-SSN claim submission',
              hash_including(action: 'submission', component: 'pension', claim_id: form_674_claim.id)
            )
          end
        end

        context 'when pension feature flag is disabled' do
          let(:claim_with_pension_data) { create(:student_claim) }

          before do
            allow(Flipper).to receive(:enabled?).with(:va_dependents_net_worth_and_pension).and_return(false)
            allow(processor).to receive(:child_claims).and_return([claim_with_pension_data])
          end

          it 'does not track pension-related submission when feature flag is disabled' do
            expect(mock_monitor).not_to receive(:track_info_event).with(
              'Submitted pension-related claim',
              hash_including(action: 'submission', component: 'pension')
            )
            processor.send(:handle_successful_submission)
          end
        end

        context 'when no-SSN feature flag is disabled' do
          let(:no_ssn_claim) do
            claim = create(:add_remove_dependents_claim)
            claim.parsed_form['dependents_application']['children_to_add'] = [{ 'no_ssn' => true }]
            claim
          end

          before do
            allow(Flipper).to receive(:enabled?).with(:va_dependents_no_ssn).and_return(false)
            allow(processor).to receive(:child_claims).and_return([no_ssn_claim])
          end

          it 'does not track no-SSN claim submission when feature flag is disabled' do
            expect(mock_monitor).not_to receive(:track_info_event).with(
              "Successful no-SSN claim submission: #{parent_claim_id}",
              hash_including(action: 'no_ssn_claim.submission')
            )
            processor.send(:handle_successful_submission)
          end
        end
      end

      context 'and parent claim group already completed' do
        before do
          parent_group.update(status: SavedClaimGroup::STATUSES[:SUCCESS])
        end

        it 'does not mark parent claim group or send notification' do
          expect(processor).not_to receive(:mark_parent_group_succeeded)
          expect_any_instance_of(DependentsBenefits::NotificationEmail).not_to receive(:send_received_notification)
          expect(mock_monitor).not_to receive(:track_info_event).with(
            'Submitted pension-related claim',
            hash_including(action: 'submission', component: 'pension')
          )
          processor.send(:handle_successful_submission)
        end
      end
    end

    context 'when not all child claims succeeded' do
      before do
        allow(form_674_claim).to receive(:submissions_succeeded?).and_return(true)
        allow(form_686_claim).to receive(:submissions_succeeded?).and_return(false)
      end

      it 'does not mark parent claim group or send notification' do
        expect(processor).not_to receive(:mark_parent_group_succeeded)
        expect_any_instance_of(DependentsBenefits::NotificationEmail).not_to receive(:send_received_notification)
        expect(mock_monitor).not_to receive(:track_info_event).with(
          'Submitted pension-related claim',
          hash_including(action: 'submission', component: 'pension')
        )
        processor.send(:handle_successful_submission)
      end
    end
  end

  describe '#notification_email' do
    it 'returns a DependentsBenefits::NotificationEmail instance' do
      email_instance = processor.send(:notification_email)
      expect(email_instance).to be_a(DependentsBenefits::NotificationEmail)
    end

    it 'memoizes the instance' do
      email_instance1 = processor.send(:notification_email)
      email_instance2 = processor.send(:notification_email)
      expect(email_instance1).to equal(email_instance2)
    end
  end
end
