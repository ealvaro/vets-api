# frozen_string_literal: true

require 'rails_helper'
require_relative 'shared_base_power_of_attorney'

describe RepresentationManagement::PowerOfAttorney::OrganizationSerializer, type: :serializer do
  subject { serialize(object, serializer_class: described_class) }

  let(:data) { JSON.parse(subject)['data'] }
  let(:attributes) { data['attributes'] }

  context 'with a Veteran::Service::Organization' do
    let(:object) { build_stubbed(:organization) }

    it_behaves_like 'power_of_attorney'

    it 'includes :type' do
      expect(attributes['type']).to eq 'organization'
    end

    it 'includes :name' do
      expect(attributes['name']).to eq object.name
    end

    it 'includes :phone' do
      expect(attributes['phone']).to eq object.phone
    end

    it 'sets the id to the poa code' do
      expect(data['id']).to eq object.poa
    end
  end

  context 'with an AccreditedOrganization' do
    let(:object) { build_stubbed(:accredited_organization) }

    it_behaves_like 'power_of_attorney'

    it 'includes :type' do
      expect(attributes['type']).to eq 'organization'
    end

    it 'includes :name' do
      expect(attributes['name']).to eq object.name
    end

    it 'includes :phone' do
      expect(attributes['phone']).to eq object.phone
    end

    it 'sets the id to the poa code' do
      expect(data['id']).to eq object.poa_code
    end
  end
end
