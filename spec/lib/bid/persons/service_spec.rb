# frozen_string_literal: true

require 'rails_helper'
require 'bid/persons/service'

RSpec.describe BID::Persons::Service do
  let(:user) { create(:evss_user, :loa3) }
  let(:service) { BID::Persons::Service.new(user) }
  let(:participant_id) { '600293960' }

  describe '#get_relationships' do
    context 'fetching a list of relationships' do
      it 'successfully receives a relationships object' do
        VCR.use_cassette('bid/persons/get_relationships') do
          response = service.get_relationships(participant_id)

          expect(response.status).to eq(200)
          expect(response.body['find_relationships_response'].size).to eq(1)
          expect(response.body['find_relationships_response'][0]['ptcpnt_type_nm']).to eq('Person')
        end
      end
    end
  end
end
