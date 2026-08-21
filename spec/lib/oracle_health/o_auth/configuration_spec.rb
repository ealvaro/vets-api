# frozen_string_literal: true

require 'rails_helper'
require 'oracle_health/o_auth/configuration'

RSpec.describe OracleHealth::OAuth::Configuration do
  subject(:handlers) { described_class.instance.connection.builder.handlers.map(&:name) }

  describe '#connection Betamocks wiring' do
    context 'when oracle_health.oauth.mock is enabled' do
      before do
        allow(IdentitySettings.oracle_health.oauth).to receive(:mock).and_return(true)
      end

      it { is_expected.to include('Betamocks::Middleware') }
    end

    context 'when oracle_health.oauth.mock is disabled' do
      before do
        allow(IdentitySettings.oracle_health.oauth).to receive(:mock).and_return(false)
      end

      it { is_expected.not_to include('Betamocks::Middleware') }
    end
  end
end
