# frozen_string_literal: true

require 'rails_helper'

describe CheckIn::Vds::SiteInfo::ClinicsService do
  subject { described_class.new }

  let(:site_id) { '534' }
  let(:vds_clinics) do
    [
      {
        clinicIen: '1081',
        name: 'CHS NEUROSURGERY VARMA',
        friendlyName: 'CHS NEUROSURGERY VARMA',
        physicalLocation: '1ST FL SPECIALTY MODULE 2'
      }
    ]
  end
  let(:faraday_response) { double('Faraday::Response') }
  let(:faraday_env) { double('Faraday::Env', status: 200, body: vds_clinics.to_json) }

  describe '#get_clinics' do
    before do
      allow_any_instance_of(Faraday::Connection).to receive(:get)
        .with("/vds/info/v1/sites/#{site_id}/clinics", {})
        .and_return(faraday_response)
      allow(faraday_response).to receive(:env).and_return(faraday_env)
    end

    it 'returns parsed clinic list from VDS-Site-Info' do
      expect(subject.get_clinics(site_id:)).to eq(JSON.parse(vds_clinics.to_json))
    end

    context 'when VDS clinics api returns server error' do
      let(:resp) { Faraday::Response.new(body: { error: 'Internal server error' }, status: 500) }
      let(:exception) { Common::Exceptions::BackendServiceException.new(nil, {}, resp.status, resp.body) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(exception)
      end

      it 're-raises so the caller decides how to handle it' do
        expect do
          subject.get_clinics(site_id:)
        end.to(raise_error do |error|
          expect(error).to be_a(Common::Exceptions::BackendServiceException)
        end)
      end
    end
  end
end
