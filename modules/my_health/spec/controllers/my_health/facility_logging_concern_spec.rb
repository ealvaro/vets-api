# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MyHealth::FacilityLoggingConcern, type: :controller do
  controller(ApplicationController) do
    include MyHealth::FacilityLoggingConcern

    def index
      render json: { success: true }
    end

    def append_info_to_payload(payload)
      super
      @payload = payload
    end
  end

  let(:user) { build(:user, :mhv) }

  before do
    sign_in_as(user, stub_mhv_account: true)
    routes.draw { get 'index' => 'anonymous#index' }
    allow(Flipper).to receive(:enabled?).with(:mhv_facility_logging, anything).and_return(true)
  end

  describe '#append_info_to_payload' do
    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_facility_logging, anything).and_return(false)
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: %w[515 648],
                                                        cerner_facility_ids: %w[668])
      end

      it 'does not add facility data to the payload' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload).not_to have_key(:facility_ids)
        expect(payload).not_to have_key(:cerner_facility_ids)
      end
    end

    context 'when user has VistA treatment facility IDs' do
      before do
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: %w[515 648],
                                                        cerner_facility_ids: [])
      end

      it 'includes facility_ids in the payload' do
        get :index
        expect(controller.instance_variable_get(:@payload)[:facility_ids]).to eq(%w[515 648])
      end

      it 'does not include cerner_facility_ids when empty' do
        get :index
        expect(controller.instance_variable_get(:@payload)).not_to have_key(:cerner_facility_ids)
      end
    end

    context 'when user has Cerner (Oracle Health) facility IDs' do
      before do
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: [],
                                                        cerner_facility_ids: %w[668])
      end

      it 'includes cerner_facility_ids in the payload' do
        get :index
        expect(controller.instance_variable_get(:@payload)[:cerner_facility_ids]).to eq(%w[668])
      end

      it 'does not include facility_ids when empty' do
        get :index
        expect(controller.instance_variable_get(:@payload)).not_to have_key(:facility_ids)
      end
    end

    context 'when user has both VistA and Cerner facility IDs' do
      before do
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: %w[515 648],
                                                        cerner_facility_ids: %w[668 552])
      end

      it 'includes both facility_ids and cerner_facility_ids' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload[:facility_ids]).to eq(%w[515 648])
        expect(payload[:cerner_facility_ids]).to eq(%w[668 552])
      end
    end

    context 'when user has no facility IDs' do
      before do
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: [],
                                                        cerner_facility_ids: [])
      end

      it 'does not include facility keys in the payload' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload).not_to have_key(:facility_ids)
        expect(payload).not_to have_key(:cerner_facility_ids)
      end
    end

    context 'when facility methods return nil' do
      before do
        allow_any_instance_of(User).to receive_messages(va_treatment_facility_ids: nil,
                                                        cerner_facility_ids: nil)
      end

      it 'handles nil gracefully without raising' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload).not_to have_key(:facility_ids)
        expect(payload).not_to have_key(:cerner_facility_ids)
      end
    end

    context 'when there is no authenticated user' do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it 'does not add facility data to the payload' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload).not_to have_key(:facility_ids)
        expect(payload).not_to have_key(:cerner_facility_ids)
      end
    end

    context 'when an error occurs fetching facility data' do
      before do
        allow_any_instance_of(User).to receive(:va_treatment_facility_ids).and_raise(StandardError, 'MPI timeout')
      end

      it 'rescues the error and does not break the request' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/FacilityLoggingConcern: failed to append facility info/)
        get :index
      end

      it 'does not add facility data to the payload' do
        get :index
        payload = controller.instance_variable_get(:@payload)
        expect(payload).not_to have_key(:facility_ids)
        expect(payload).not_to have_key(:cerner_facility_ids)
      end
    end
  end
end
