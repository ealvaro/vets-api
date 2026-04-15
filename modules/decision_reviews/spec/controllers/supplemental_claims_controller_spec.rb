# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require './modules/decision_reviews/spec/support/vcr_helper'

RSpec.describe DecisionReviews::V1::SupplementalClaimsController, type: :controller do
  routes { DecisionReviews::Engine.routes }

  let(:user) { build(:user, :loa3) }

  before do
    sign_in_as(user)
  end

  describe '#process_submission' do
    it 'delegates to RequestBodyNormalizer for schema transformations' do
      normalizer_double = instance_double(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer)
      allow(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer).to receive(:new)
        .and_return(normalizer_double)
      allow(normalizer_double).to receive(:normalize).and_return({
                                                                   'data' => { 'attributes' => {} },
                                                                   'form4142' => nil,
                                                                   'additionalDocuments' => nil
                                                                 })

      # We're testing that the normalizer is called, not the full submission flow
      expect(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer).to receive(:new)
        .with(anything)
      expect(normalizer_double).to receive(:normalize)

      # Stub the rest of the submission flow so the method can complete without masking errors
      allow(controller).to receive_messages(request_body_hash: {},
                                            decision_review_service: double(create_supplemental_claim: double(body: { 'data' => { 'id' => 'test-uuid' } }, status: 200))) # rubocop:disable Layout/LineLength
      allow(controller).to receive(:create_appeal_submission).and_return(1)
      allow(AppealSubmission).to receive(:create!).and_return(double(id: 1))
      allow(controller).to receive(:store_saved_claim)
      allow(controller).to receive(:clear_in_progress_form)
      allow(controller).to receive(:render)
      allow(InProgressForm).to receive(:form_for_user).and_return(nil)
      allow(DecisionReviews::V1::Service).to receive(:file_upload_metadata).and_return({})
      allow(ActiveRecord::Base).to receive(:transaction).and_yield

      controller.send(:process_submission)
    end
  end
end
