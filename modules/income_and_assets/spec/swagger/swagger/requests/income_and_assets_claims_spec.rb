# frozen_string_literal: true

require 'rails_helper'

reg_office = 'Department of Veteran Affairs, Pension Intake Center, P.O. Box 5365, Janesville, Wisconsin 53547-5365'

# Income and Assets Claim Integration
RSpec.describe Swagger::Requests::IncomeAndAssetsClaims, type: %i[request serializer] do
  let(:full_claim) do
    build(:income_and_assets_claim).parsed_form
  end
  let(:user) { build(:user, :loa3) }
  let(:mpi_stub) { double('MPI') }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(MPI::Service).to receive(:new).and_return(mpi_stub)
    allow(mpi_stub).to receive(:find_profile_by_identifier).and_return(
      OpenStruct.new({ profile: OpenStruct.new({
                                                 ssn: '123121234', participant_id: '123456789'
                                               }) })
    )
  end

  describe 'POST create' do
    subject do
      post '/income_and_assets/v0/form0969',
           params: params.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json', 'HTTP_X_KEY_INFLECTION' => 'camel',
                      'Cookie' => sign_in(user, nil, true) }
    end

    context 'with invalid params' do
      let(:params) do
        {
          incomeAndAssetsClaim: {
            form: full_claim.merge('veteranSocialSecurityNumber' => 'just a string').to_json
          }
        }
      end

      it 'shows the validation errors' do
        subject
        expect(response).to have_http_status(:unprocessable_content)

        expect(
          JSON.parse(response.body)['errors'][0]['detail'].include?(
            '/veteran-social-security-number - string at `/veteranSocialSecurityNumber` ' \
            'does not match pattern: ^[0-9]{9}$'
          )
        ).to be(true)
      end
    end

    context 'with valid params' do
      let(:params) do
        {
          incomeAndAssetsClaim: {
            form: full_claim.to_json
          }
        }
      end

      it 'renders success' do
        subject
        expect(JSON.parse(response.body)['data']['attributes'].keys.sort)
          .to eq(%w[confirmationNumber form guid regionalOffice submittedAt])
      end

      it 'returns the expected regional office' do
        subject
        expect(JSON.parse(response.body)['data']['attributes']['regionalOffice'].join(', '))
          .to eq(reg_office)
      end
    end
  end
end
