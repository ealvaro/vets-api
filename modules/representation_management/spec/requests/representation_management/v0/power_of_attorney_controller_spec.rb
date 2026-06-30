# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RepresentationManagement::V0::PowerOfAttorney', type: :request do
  let(:index_path) { '/representation_management/v0/power_of_attorney' }
  let(:user) { create(:user, :loa3) }

  describe 'index' do
    context 'with a signed in user' do
      before do
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(Flipper).to receive(:enabled?)
          .with(:arc_representative_status_use_accredited_models)
          .and_return(false)
        sign_in_as(user)
      end

      context 'when arc_representative_status_use_accredited_models is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:arc_representative_status_use_accredited_models).and_return(false)
        end

        context 'when an organization is the active poa' do
          let(:org_poa) { 'og1' }
          let!(:organization) { create(:organization, poa: org_poa) }

          it 'returns the expected organization response from Veteran::Service::Organization' do
            lh_response = {
              'data' => {
                'type' => 'organization',
                'attributes' => {
                  'code' => org_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(org_poa)
          end
        end

        context 'when a representative is the active poa' do
          let(:rep_poa) { 'rp1' }
          let(:registration_number) { '12345' }
          let!(:representative) do
            create(:representative,
                   representative_id: registration_number, poa_codes: [rep_poa])
          end

          it 'returns the expected representative response from Veteran::Service::Representative' do
            lh_response = {
              'data' => {
                'type' => 'individual',
                'attributes' => {
                  'code' => rep_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(registration_number)
          end
        end
      end

      context 'when arc_representative_status_use_accredited_models is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:arc_representative_status_use_accredited_models).and_return(true)
        end

        context 'when an organization is the active poa' do
          let(:org_poa) { 'og1' }
          let!(:accredited_organization) { create(:accredited_organization, poa_code: org_poa) }

          it 'returns the expected organization response from AccreditedOrganization' do
            lh_response = {
              'data' => {
                'type' => 'organization',
                'attributes' => {
                  'code' => org_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(accredited_organization.poa_code)
            expect(response_body['data']['attributes']['name']).to eq(accredited_organization.name)
          end
        end

        context 'when an attorney individual is the active poa' do
          let(:ind_poa) { 'rp1' }
          let!(:accredited_individual) do
            create(:accredited_individual, poa_code: ind_poa, individual_type: 'attorney')
          end

          it 'returns the expected individual response from AccreditedIndividual' do
            lh_response = {
              'data' => {
                'type' => 'individual',
                'attributes' => {
                  'code' => ind_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(accredited_individual.registration_number)
            expect(response_body['data']['attributes']['individual_type']).to eq('attorney')
          end
        end

        context 'when a claims agent individual is the active poa' do
          let(:ind_poa) { 'ca1' }
          let!(:accredited_individual) do
            create(:accredited_individual, poa_code: ind_poa, individual_type: 'claims_agent')
          end

          it 'returns the expected individual response from AccreditedIndividual' do
            lh_response = {
              'data' => {
                'type' => 'individual',
                'attributes' => {
                  'code' => ind_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(accredited_individual.registration_number)
            expect(response_body['data']['attributes']['individual_type']).to eq('claims_agent')
          end
        end

        context 'when the poa record is not found in AccreditedOrganization' do
          it 'returns the expected empty response' do
            lh_response = {
              'data' => {
                'type' => 'organization',
                'attributes' => {
                  'code' => 'xyz'
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']).to eq({})
          end
        end
      end

      context 'when there is no active poa' do
        it 'returns the expected empty response' do
          lh_response = {
            'data' => {}
          }
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_return(lh_response)

          get index_path

          response_body = JSON.parse(response.body)

          expect(response).to have_http_status(:ok)
          expect(response_body['data']).to eq({})
        end
      end

      context 'when the poa record is not found in the database' do
        it 'returns the expected empty response' do
          lh_response = {
            'data' => {
              'type' => 'organization',
              'attributes' => {
                'code' => 'abc'
              }
            }
          }
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_return(lh_response)

          get index_path

          response_body = JSON.parse(response.body)

          expect(response).to have_http_status(:ok)
          expect(response_body['data']).to eq({})
        end
      end

      context 'when the service encounters an unprocessable entity error' do
        it 'returns a 422/unprocessable_entity status' do
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_raise(Common::Exceptions::UnprocessableEntity)

          get index_path

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when the user has no participant id' do
        let(:user) { build(:user_with_no_ids) }

        it 'increments the StatsD total requests metric' do
          lh_response = {
            'data' => {}
          }
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_return(lh_response)

          get index_path

          expect(StatsD).to have_received(:increment)
            .with('api.representation_management.power_of_attorney.index.no_participant_id.total')
        end

        it 'logs the request attempt' do
          lh_response = {
            'data' => {}
          }
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_return(lh_response)

          get index_path

          expect(Rails.logger).to have_received(:info)
            .with('Fetching POA status, no Participant ID in MPI profile')
        end

        context 'when the BenefitsClaims::Service returns an error' do
          it 'increments the StatsD failure metric' do
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_raise(Common::Exceptions::ServiceError)

            get index_path

            expect(StatsD).to have_received(:increment)
              .with('api.representation_management.power_of_attorney.index.no_participant_id.failure')
          end

          it 'logs the error' do
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_raise(Common::Exceptions::ServiceError)

            get index_path

            expect(Rails.logger).to have_received(:error)
              .with('Failed to fetch POA status, no Participant ID: Common::Exceptions::ServiceError')
          end
        end

        context 'when the BenefitsClaims::Service returns a successful response' do
          it 'does not increment the StatsD failure metric' do
            lh_response = {
              'data' => {}
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path

            expect(StatsD).not_to have_received(:increment)
              .with('api.representation_management.power_of_attorney.index.no_participant_id.failure')
          end
        end
      end

      context 'when the user has a participant id' do
        it 'does not increment the StatsD metrics' do
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney)
            .and_raise(Common::Exceptions::ServiceError)

          get index_path

          expect(StatsD).not_to have_received(:increment)
            .with('api.representation_management.power_of_attorney.index.no_participant_id.total')
          expect(StatsD).not_to have_received(:increment)
            .with('api.representation_management.power_of_attorney.index.no_participant_id.failure')
        end
      end
    end

    context 'without a signed in user' do
      describe 'GET #index' do
        it 'returns a 401/unauthorized status' do
          get index_path

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
