# frozen_string_literal: true

require 'rails_helper'
require_relative '../../support/vass_settings_helper'

RSpec.describe Vass::Configuration do
  subject(:vass_config) { described_class.instance }

  let(:oauth_url) { 'https://login.microsoftonline.example/oauth2/token' }

  before do
    vass_config.send(:instance_variable_set, :@__oauth_conn_pool__, nil)
  end

  describe '#oauth_connection' do
    it 'uses Settings.vass.oauth_open_timeout and oauth_read_timeout on the Faraday connection' do
      stub_vass_settings(oauth_open_timeout: 12, oauth_read_timeout: 34)

      conn = vass_config.oauth_connection(server_url: oauth_url)

      expect(conn.options.open_timeout).to eq(12)
      expect(conn.options.timeout).to eq(34)
    end

    it 'reflects updated Settings when a new connection is built' do
      stub_vass_settings(oauth_open_timeout: 7, oauth_read_timeout: 21)

      first = vass_config.oauth_connection(server_url: oauth_url)
      expect(first.options.open_timeout).to eq(7)
      expect(first.options.timeout).to eq(21)

      vass_config.send(:instance_variable_set, :@__oauth_conn_pool__, nil)
      stub_vass_settings(oauth_open_timeout: 8, oauth_read_timeout: 22)

      second = vass_config.oauth_connection(server_url: oauth_url)
      expect(second.options.open_timeout).to eq(8)
      expect(second.options.timeout).to eq(22)
    end
  end
end
