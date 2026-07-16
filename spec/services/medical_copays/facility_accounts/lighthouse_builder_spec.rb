# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::LighthouseBuilder do
  subject(:builder) { described_class.new(lighthouse_service:) }

  let(:lighthouse_service) { instance_double(MedicalCopays::LighthouseIntegration::Service) }
  let(:organization_id) { '4-5pFm5BMGzyD' }
  let(:facility_identifier_value) { 'vha_896' }

  let(:organization_resource) do
    {
      'resourceType' => 'Organization',
      'id' => organization_id,
      'identifier' => [
        { 'system' => 'http://hl7.org/fhir/sid/us-npi', 'value' => '0221760022' },
        {
          'use' => 'usual',
          'type' => {
            'coding' => [
              {
                'system' => 'http://terminology.hl7.org/CodeSystem/v2-0203',
                'code' => 'FI',
                'display' => 'Facility ID'
              }
            ],
            'text' => 'Facility ID'
          },
          'system' => 'https://api.va.gov/services/fhir/v0/r4/NamingSystem/va-facility-identifier',
          'value' => facility_identifier_value
        }
      ],
      'name' => 'TEST VAMC'
    }
  end

  before do
    allow(lighthouse_service).to receive(:fetch_organization)
      .with(organization_id, described_class::ORG_CACHE_STATSD_KEY)
      .and_return(organization_resource)
  end

  describe '#get_station_id' do
    it 'resolves an organization to the bare station id from its Facility ID identifier' do
      expect(builder.send(:get_station_id, organization_id)).to eq('896')
    end

    context 'when the identifier value is division-suffixed' do
      let(:facility_identifier_value) { 'vha_640A0' }

      it 'truncates to the parent station id' do
        expect(builder.send(:get_station_id, organization_id)).to eq('640')
      end
    end

    context 'when the identifier value is shorter than a parent station' do
      let(:facility_identifier_value) { 'vha_6' }

      it 'excludes the value rather than resolving a partial station id' do
        expect(builder.send(:get_station_id, organization_id)).to be_nil
      end
    end

    context 'when the organization has no Facility ID identifier' do
      let(:organization_resource) do
        {
          'resourceType' => 'Organization',
          'id' => organization_id,
          'identifier' => [
            { 'system' => 'http://hl7.org/fhir/sid/us-npi', 'value' => '1396794293' }
          ],
          'name' => 'LYONS- VA NEW JERSEY HCS'
        }
      end

      it 'returns nil rather than falling back to the org FHIR id' do
        expect(builder.send(:get_station_id, organization_id)).to be_nil
      end
    end
  end
end
