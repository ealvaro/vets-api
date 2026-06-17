# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::VeteranOnboardingsController, type: :controller do
  let(:user) { create(:user, :loa3) }
  let(:veteran_onboarding) { create(:veteran_onboarding, user_account: user.user_account) }

  before do
    sign_in_as(user)
  end

  describe 'GET #show' do
    it 'returns a success response with veteran onboarding record' do
      veteran_onboarding
      get :show
      expect(response).to be_successful
      expect(response.parsed_body).to eq(veteran_onboarding.as_json)
    end

    context 'when user has no veteran onboarding record' do
      it 'creates one and returns a success response with newly created record' do
        get :show
        expect(response).to be_successful
        expect(response.parsed_body['display_onboarding_flow']).to be(true)
      end
    end
  end

  describe 'PATCH #update' do
    let(:new_attributes) do
      { display_onboarding_flow: true }
    end

    it 'updates the requested veteran_onboarding' do
      expect do
        patch :update, params: { id: veteran_onboarding.to_param, veteran_onboarding: new_attributes }
      end.to change { veteran_onboarding.reload.display_onboarding_flow }.from(false).to(true)
    end

    it 'renders a successful response' do
      patch :update, params: { id: veteran_onboarding.to_param, veteran_onboarding: new_attributes }
      expect(response).to be_successful
    end
  end
end
