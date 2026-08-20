# frozen_string_literal: true

require 'rails_helper'
require 'bpds/submission_handler'

RSpec.describe SurvivorsBenefits::V0::ClaimsController, type: :controller do
  routes { SurvivorsBenefits::Engine.routes }

  it 'includes BPDS::SubmissionHandler' do
    expect(described_class.include?(BPDS::SubmissionHandler)).to be(true)
  end

  describe '#survivors_benefits_bpds_parallel_enabled?' do
    let(:user) { create(:user) }

    before do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(subject).to receive(:current_user).and_return(user) # rubocop:disable RSpec/SubjectStub
    end

    context 'when the per-form flag is off' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, user).and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, user).and_return(false)
      end

      it 'returns false' do
        expect(subject.send(:survivors_benefits_bpds_parallel_enabled?)).to be(false)
      end
    end

    context 'when the per-form flag is on and after-VBMS is off' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, user).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, user).and_return(false)
      end

      it 'returns true' do
        expect(subject.send(:survivors_benefits_bpds_parallel_enabled?)).to be(true)
      end
    end

    context 'when both per-form and after-VBMS flags are on' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, user).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, user).and_return(true)
      end

      it 'returns false (after-VBMS path takes over)' do
        expect(subject.send(:survivors_benefits_bpds_parallel_enabled?)).to be(false)
      end
    end
  end

  describe '#create BPDS dispatch' do
    let(:user) { create(:user) }
    let(:claim) { build(:survivors_benefits_claim) }
    let(:monitor) { instance_double(SurvivorsBenefits::Monitor) }

    before do
      sign_in_as(user)
      allow(SurvivorsBenefits::Monitor).to receive(:new).and_return(monitor)
      allow(monitor).to receive_messages(track_create_attempt: nil, track_create_error: nil,
                                         track_create_success: nil, track_create_validation_error: nil,
                                         track_process_attachment_error: nil)
      allow(SurvivorsBenefits::SavedClaim).to receive(:new).and_return(claim)
      # build(:...) leaves claim unsaved (id nil); the request assigns a real id at save time.
      # Pin it so `.with(claim.id, ...)` expectations match the value passed at call time.
      allow(claim).to receive(:id).and_return(99)
      allow(SurvivorsBenefits::BenefitsIntake::SubmitClaimJob).to receive(:perform_async)
      allow_any_instance_of(described_class).to receive(:upload_to_s3).and_return('https://example.com/p.pdf')
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_enabled, anything).and_return(true)
    end

    context 'when the BPDS parallel gate is open' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, anything).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, anything).and_return(false)
      end

      it 'calls submit_claim_to_bpds with the claim id and current user' do
        expect_any_instance_of(described_class).to receive(:submit_claim_to_bpds)
          .with(claim.id, claim.form_id, instance_of(User))

        post(:create, params: { survivors_benefits_claim: { form: claim.form } })
      end

      context 'when submit_claim_to_bpds raises (BPDS is experimental and must not disrupt submission)' do
        let(:bpds_monitor) { instance_double(BPDS::Monitor, track_submit_failure: nil) }

        before do
          allow(BPDS::Monitor).to receive(:new).and_return(bpds_monitor)
          allow_any_instance_of(described_class).to receive(:submit_claim_to_bpds)
            .and_raise(StandardError.new('MPI timeout'))
        end

        it 'still enqueues SubmitClaimJob and does not re-raise' do
          expect(SurvivorsBenefits::BenefitsIntake::SubmitClaimJob).to receive(:perform_async)
            .with(claim.id, anything)

          post(:create, params: { survivors_benefits_claim: { form: claim.form } })

          expect(response).to have_http_status(:ok)
        end

        it 'tracks the BPDS failure' do
          expect(bpds_monitor).to receive(:track_submit_failure).with(claim.id, claim.form_id,
                                                                      instance_of(StandardError))

          post(:create, params: { survivors_benefits_claim: { form: claim.form } })
        end
      end
    end

    context 'when the per-form BPDS flag is off' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, anything).and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, anything).and_return(false)
      end

      it 'does not call submit_claim_to_bpds' do
        expect_any_instance_of(described_class).not_to receive(:submit_claim_to_bpds)

        post(:create, params: { survivors_benefits_claim: { form: claim.form } })
      end
    end

    context 'when the after-VBMS flag is on' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_service_enabled, anything).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_bpds_submit_after_vbms, anything).and_return(true)
      end

      it 'does not call submit_claim_to_bpds (handler path takes over)' do
        expect_any_instance_of(described_class).not_to receive(:submit_claim_to_bpds)

        post(:create, params: { survivors_benefits_claim: { form: claim.form } })
      end
    end
  end
end
