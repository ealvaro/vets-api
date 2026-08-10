# frozen_string_literal: true

require 'rails_helper'
require 'bep/configuration'

class TestConfiguration < BEP::Configuration
  def base_path
    'http://www.example.com'
  end

  def service_name
    'test-service'
  end
end

RSpec.describe BEP::Configuration do
  let(:instance) { TestConfiguration.instance }

  describe '#connection' do
    it 'returns a faraday connection with the right parameters' do
      connection = instance.connection
      expect(connection).to be_a(Faraday::Connection)
      expect(connection.headers['Accept']).to eq('application/json')
      expect(connection.headers['Content-Type']).to eq('application/json')
      expect(connection.headers['User-Agent']).to eq('Vets.gov Agent')
      expect(connection.url_prefix.to_s).to eq('http://www.example.com/')
    end
  end
end
