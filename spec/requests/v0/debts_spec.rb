# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'V0::Debts', type: :request do
  include SchemaMatchers

  let(:user_details) do
    {
      first_name: 'Greg',
      last_name: 'Anderson',
      middle_name: 'A',
      birth_date: '1991-04-05',
      ssn: '796043735'
    }
  end

  let(:user) { build(:user, :loa3, user_details) }

  before do
    sign_in_as(user)
  end

  describe 'GET /v0/debts' do
    context 'with a veteran who has debts' do
      it 'returns a 200 with the array of debts' do
        VCR.use_cassette('bgs/people_service/person_data') do
          VCR.use_cassette('debts/get_letters', VCR::MATCH_EVERYTHING) do
            get '/v0/debts'
            expect(response).to have_http_status(:ok)
            expect(response).to match_response_schema('debts')
          end
        end
      end
    end
  end

  context 'with a veteran with empty ssn' do
    it 'returns an error' do
      VCR.use_cassette('debts/get_letters_empty_ssn', VCR::MATCH_EVERYTHING) do
        get '/v0/debts'
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  context 'when the Debt Management Center fails' do
    # An upstream failure must not be reported to the veteran as a client error.
    # The rendered status comes from the DMC* mappings in exceptions.en.yml.
    {
      400 => { status: :bad_request, code: 'DMC400' },
      404 => { status: :bad_gateway, code: 'DMC404' },
      500 => { status: :bad_gateway, code: 'DMC500' },
      502 => { status: :bad_gateway, code: 'DMC502' },
      503 => { status: :service_unavailable, code: 'DMC503' },
      nil => { status: :service_unavailable, code: 'DMC' }
    }.each do |upstream_status, expected|
      it "renders #{expected[:code]} when the upstream responds with #{upstream_status || 'no status'}" do
        allow_any_instance_of(DebtManagementCenter::DebtsService).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new('upstream failure', upstream_status, 'upstream body')
        )

        VCR.use_cassette('bgs/people_service/person_data') do
          get '/v0/debts'
        end

        expect(response).to have_http_status(expected[:status])
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq(expected[:code])
      end
    end
  end
end
