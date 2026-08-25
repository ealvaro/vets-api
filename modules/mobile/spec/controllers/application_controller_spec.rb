# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::ApplicationController, type: :controller do
  controller do
    attr_reader :payload

    def index
      head :ok
    end

    def append_info_to_payload(payload)
      super
      @payload = payload
    end
  end

  describe 'authentication', :aggregate_errors do
    let(:error_detail) { JSON.parse(response.body)['errors'].first['detail'] }

    context 'without Authentication-Method header' do
      it 'returns unauthorized' do
        get :index

        expect(response).to have_http_status(:unauthorized)
        expect(error_detail).to eq('Missing Authorization header')
      end
    end

    context 'with an unsupported Authentication-Method header' do
      before { request.headers['Authentication-Method'] = 'handshake' }

      it 'returns unauthorized' do
        get :index

        expect(response).to have_http_status(:unauthorized)
        expect(error_detail).to eq('Authentication method not supported')
      end
    end

    context 'with Authentication-Method header value of SIS' do
      let(:access_token) { create(:access_token, audience: ['vamobile']) }
      let(:bearer_token) { SignIn::AccessTokenJwtEncoder.new(access_token:).perform }
      let!(:user) { create(:user, :loa3, uuid: access_token.user_uuid) }
      let(:deceased_date) { nil }
      let(:id_theft_flag) { false }
      let(:mpi_profile) { build(:mpi_profile, deceased_date:, id_theft_flag:) }

      before do
        request.headers['Authorization'] = "Bearer #{bearer_token}"
        request.headers['Authentication-Method'] = 'SIS'
        allow_any_instance_of(MPIData).to receive(:profile).and_return(mpi_profile)
      end

      it 'authenticates successfully' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(controller.payload[:user_uuid]).to eq(access_token.user_uuid)
        expect(controller.payload[:session]).to eq(access_token.session_handle)
      end

      context 'when the access_token audience is invalid' do
        let(:access_token) { create(:access_token, audience: ['invalid']) }

        it 'returns unauthorized' do
          get :index

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when the access_token audience is vamock-mobile' do
        let(:access_token) { create(:access_token, audience: ['vamock-mobile']) }

        it 'returns ok in test environment' do
          get :index

          expect(response).to have_http_status(:ok)
        end
      end

      context 'when validating the user\'s MPI profile' do
        context 'and the MPI profile has a deceased date' do
          let(:deceased_date) { '20020202' }
          let(:mpi_locked_reason) { 'Death Flag Detected' }

          it 'returns a generic 401 that does not reveal the death flag' do
            get :index

            expect(response).to have_http_status(:unauthorized)
            expect(JSON.parse(response.body)).to eq({ 'errors' => 'Unauthorized' })
            expect(response.body).not_to include(mpi_locked_reason)
          end
        end

        context 'and the MPI profile has an id theft flag' do
          let(:id_theft_flag) { true }
          let(:mpi_locked_reason) { 'Theft Flag Detected' }

          it 'returns a generic 401 that does not reveal the theft flag' do
            get :index

            expect(response).to have_http_status(:unauthorized)
            expect(JSON.parse(response.body)).to eq({ 'errors' => 'Unauthorized' })
            expect(response.body).not_to include(mpi_locked_reason)
          end
        end
      end
    end
  end
end
