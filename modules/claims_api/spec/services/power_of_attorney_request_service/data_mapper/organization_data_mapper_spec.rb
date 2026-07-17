# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../poa_auto_establishment_spec_helper'

describe ClaimsApi::PowerOfAttorneyRequestService::DataMapper::OrganizationDataMapper do
  subject { described_class.new(data: org_gathered_data) }

  include_context 'shared POA auto establishment data'

  it 'maps the data correctly' do
    res = subject.map_data

    expect(res).to eq(org_mapped_form_data)
  end

  context 'when gathered data includes birth_date in claimant' do
    subject { described_class.new(data: gathered_data_with_birth_date) }

    let(:gathered_data_with_birth_date) do
      org_gathered_data.merge(
        'claimant' => org_gathered_data['claimant'].merge('birth_date' => '1990-01-15')
      )
    end

    it 'includes dateOfBirth in mapped claimant data' do
      res = subject.map_data

      expect(res.dig('data', 'attributes', 'claimant', 'dateOfBirth')).to eq('1990-01-15')
    end
  end

  context 'when gathered data does not include birth_date in claimant' do
    it 'does not include dateOfBirth in mapped claimant data' do
      res = subject.map_data

      expect(res.dig('data', 'attributes', 'claimant')).not_to have_key('dateOfBirth')
    end
  end
end
