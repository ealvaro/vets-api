# frozen_string_literal: true

require_relative '../../../support/helpers/rails_helper'

RSpec.describe 'Mobile::V0::PowerOfAttorney', type: :request do
  let(:index_path) { '/mobile/v0/power_of_attorney' }

  describe 'GET #index' do
    context 'with a signed in user' do
      let!(:user) { sis_user }

      context 'when using legacy models (flag off)' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mobile_power_of_attorney_use_accredited_models).and_return(false)
        end

        context 'when an organization is the active poa' do
          let(:org_poa) { 'og1' }
          let!(:organization) { create(:organization, poa: org_poa) }

          it 'returns the expected organization response' do
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

            get index_path, headers: sis_headers

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

          it 'returns the expected representative response' do
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

            get index_path, headers: sis_headers

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(registration_number)
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

            get index_path, headers: sis_headers

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

            get index_path, headers: sis_headers

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

            get index_path, headers: sis_headers

            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      context 'when using accredited models (flag on)' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mobile_power_of_attorney_use_accredited_models).and_return(true)
        end

        context 'when an organization is the active poa' do
          let(:org_poa) { 'og1' }
          let!(:accredited_organization) { create(:accredited_organization, poa_code: org_poa) }

          it 'returns the expected organization response' do
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

            get index_path, headers: sis_headers

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(org_poa)
          end
        end

        context 'when a representative with direct poa_code is the active poa' do
          let(:rep_poa) { 'rp1' }
          let(:registration_number) { '12345' }
          let!(:accredited_individual) do
            create(:accredited_individual,
                   registration_number:,
                   individual_type: 'attorney',
                   poa_code: rep_poa)
          end

          it 'returns the expected representative response' do
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

            get index_path, headers: sis_headers

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(registration_number)
          end
        end

        context 'when a representative through an organization is the active poa' do
          let(:org_poa) { 'rp2' }
          let(:registration_number) { '67890' }
          let!(:accredited_organization) { create(:accredited_organization, poa_code: org_poa) }
          let!(:accredited_individual) do
            individual = create(:accredited_individual,
                                registration_number:,
                                individual_type: 'representative')
            create(:accreditation,
                   accredited_individual: individual,
                   accredited_organization:)
            individual
          end

          it 'returns the expected representative response' do
            lh_response = {
              'data' => {
                'type' => 'individual',
                'attributes' => {
                  'code' => org_poa
                }
              }
            }
            allow_any_instance_of(BenefitsClaims::Service)
              .to receive(:get_power_of_attorney)
              .and_return(lh_response)

            get index_path, headers: sis_headers

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']['id']).to eq(registration_number)
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

            get index_path, headers: sis_headers

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

            get index_path, headers: sis_headers

            response_body = JSON.parse(response.body)

            expect(response).to have_http_status(:ok)
            expect(response_body['data']).to eq({})
          end
        end
      end
    end

    context 'without a signed in user' do
      it 'returns a 401/unauthorized status' do
        get index_path

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
