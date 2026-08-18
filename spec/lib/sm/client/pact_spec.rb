# frozen_string_literal: true

require 'rails_helper'
require 'sm/client'

# rubocop:disable RSpec/DescribeClass
describe 'sm client' do
  describe 'pact' do
    subject(:client) { @client }

    before do
      VCR.use_cassette 'sm_client/session' do
        @client ||= begin
          client = SM::Client.new(session: { user_id: '10616687' })
          client.authenticate
          client
        end
      end
    end

    it 'gets all pact teams', :vcr do
      VCR.use_cassette 'sm_client/pact/gets_all_pacts' do
        pact = client.get_pact
        expect(pact[:data]).not_to be_empty
      end
    end

    it 'gets a pact team for a matching station', :vcr do
      VCR.use_cassette 'sm_client/pact/gets_a_pact' do
        pact = client.get_pact_for_station(123)

        expect(pact[:data]).not_to be_empty
        expect(pact[:data].map { |team| team[:station_number] }.uniq).to eq([123])
        expect(pact[:data].first[:team_name]).to eq('Team 123')
      end
    end

    it 'returns an empty collection when no pact team matches the station' do
      VCR.use_cassette 'sm_client/pact/gets_a_pact' do
        pact = client.get_pact_for_station(999)

        expect(pact[:data]).to be_empty
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
