# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RepresentationManagement::V0::AccreditedEntitiesForAppoint', type: :request do
  let(:path) { '/representation_management/v0/accredited_entities_for_appoint' }
  let!(:bob_law) { create(:accredited_individual, :with_location, first_name: 'Bob', last_name: 'Law') }
  let!(:bob_smith) { create(:accredited_individual, :with_location, first_name: 'Bob', last_name: 'Smith') }
  let!(:bob_law_firm) { create(:accredited_organization, :with_location, name: 'Bob Law Firm') }
  let!(:bob_smith_firm) { create(:accredited_organization, :with_location, name: 'Bob Smith Firm') }

  before do
    allow(Flipper).to receive(:enabled?).with(:appoint_a_representative_enable_pdf).and_return(true)
  end

  context 'the response should be an empty array' do
    context 'when the query parameter is an empty string' do
      it 'returns an empty array' do
        get path, params: { query: '' }

        parsed_response = JSON.parse(response.body)
        expect(parsed_response).to eq([])
      end
    end

    context 'when the query parameter is not present' do
      it 'returns an empty array' do
        get path

        parsed_response = JSON.parse(response.body)
        expect(parsed_response).to eq([])
      end
    end

    it 'when there are no matching results' do
      get path, params: { query: 'Zach' }
      parsed_response = JSON.parse(response.body)
      expect(parsed_response).to eq([])
    end
  end

  context 'when the search is valid' do
    it 'returns a array of individuals and organizations' do
      get path, params: { query: 'Bob' }

      parsed_response = JSON.parse(response.body)
      expect(parsed_response.size).to eq(4)
      expect(parsed_response[0]['data']['attributes']['full_name']).to eq('Bob Law')
      expect(parsed_response[1]['data']['attributes']['full_name']).to eq('Bob Smith')
      expect(parsed_response[2]['data']['attributes']['name']).to eq('Bob Law Firm')
      expect(parsed_response[3]['data']['attributes']['name']).to eq('Bob Smith Firm')
    end

    it 'gates a nested organization can_accept_digital_poa_requests by the per-rep acceptance_mode' do
      individual = create(:accredited_individual, :with_organizations, :with_location,
                          first_name: 'Bob', last_name: 'Jones')
      individual.accredited_organizations.first.update!(can_accept_digital_poa_requests: true)

      individual.accreditations.first.update!(acceptance_mode: 'self_only')

      get path, params: { query: 'Bob' }

      parsed_response = JSON.parse(response.body)
      entry = parsed_response.find { |e| e['data']['attributes']['full_name'] == 'Bob Jones' }
      organization = entry['data']['attributes']['accredited_organizations']['data'].first

      expect(organization['attributes']['can_accept_digital_poa_requests']).to be(true)
      expect(organization['attributes']).not_to have_key('acceptance_mode')
      expect(organization['attributes']).not_to have_key('reps_can_accept_any_request')
    end

    it 'reports a nested organization as not accepting when the per-rep acceptance_mode is no_acceptance' do
      individual = create(:accredited_individual, :with_organizations, :with_location,
                          first_name: 'Bob', last_name: 'Jones')
      individual.accredited_organizations.first.update!(can_accept_digital_poa_requests: true)

      individual.accreditations.first.update!(acceptance_mode: 'no_acceptance')

      get path, params: { query: 'Bob' }

      parsed_response = JSON.parse(response.body)
      entry = parsed_response.find { |e| e['data']['attributes']['full_name'] == 'Bob Jones' }
      organization = entry['data']['attributes']['accredited_organizations']['data'].first

      expect(organization['attributes']['can_accept_digital_poa_requests']).to be(false)
    end

    it 'includes reps_can_accept_any_request on a top-level organization result' do
      org = create(:accredited_organization, :with_location, :with_representatives,
                   name: 'Bob Any Request Org', can_accept_digital_poa_requests: true)
      org.accreditations.first.update!(acceptance_mode: 'any_request')

      get path, params: { query: 'Bob Any Request Org' }

      parsed_response = JSON.parse(response.body)
      entry = parsed_response.find { |e| e['data']['attributes']['name'] == 'Bob Any Request Org' }

      expect(entry['data']['attributes']['reps_can_accept_any_request']).to be(true)
      expect(entry['data']['attributes']['can_accept_digital_poa_requests']).to be(true)
    end
  end

  context "when the feature flag 'arc_appoint_a_representative_use_accredited_models' is disabled" do
    before do
      allow(Flipper).to receive(:enabled?).with(:arc_appoint_a_representative_use_accredited_models).and_return(false)
    end

    it 'returns a 404' do
      get path

      expect(response).to have_http_status(:not_found)
    end
  end
end
