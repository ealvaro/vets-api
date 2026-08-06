# frozen_string_literal: true

require 'rails_helper'

# The gated BD stack exists only to bound the gated send's availability check with
# a tight, Sidekiq-safe Faraday read timeout while sharing the primary client's
# breakers circuit and metrics. These specs pin that contract.
RSpec.describe EventBusGateway::GatedClaimLettersProvider do
  it 'talks to BD through the gated service' do
    user = instance_double(User)
    allow(ClaimLetters::DoctypeService).to receive(:allowed_for_user).and_return([])

    provider = described_class.new(user)

    expect(provider.instance_variable_get(:@service)).to be_a(EventBusGateway::GatedClaimLettersService)
  end

  describe 'the gated service and configuration it depends on' do
    it 'binds the gated service to the gated configuration' do
      expect(EventBusGateway::GatedClaimLettersService.configuration)
        .to be_a(EventBusGateway::GatedClaimLettersConfiguration)
    end

    it 'uses the tight gated read timeout, tighter than the default BD client' do
      expect(EventBusGateway::GatedClaimLettersConfiguration.read_timeout)
        .to eq(EventBusGateway::Constants::GATED_SEND_BD_TIMEOUT_SECONDS)
      expect(EventBusGateway::GatedClaimLettersConfiguration.read_timeout)
        .to be < BenefitsDocuments::Configuration.read_timeout
    end

    it 'inherits the BenefitsDocuments service_name so breakers and metrics stay shared' do
      expect(EventBusGateway::GatedClaimLettersConfiguration.instance.service_name).to eq('BenefitsDocuments')
    end
  end
end
