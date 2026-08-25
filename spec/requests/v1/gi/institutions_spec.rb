# frozen_string_literal: false

require 'rails_helper'

RSpec.describe 'V1::GI::Institutions', type: :request do
  it 'strips SCO email and phone from institution details' do
    VCR.use_cassette('gi_client/v1/gets_the_institution_details') do
      get '/v1/gi/institutions/11902614'
    end

    scos = JSON.parse(response.body).dig('data', 'attributes', 'versioned_school_certifying_officials')
    expect(scos).to be_present
    scos.each do |sco|
      expect(sco).not_to have_key('email')
      expect(sco).not_to have_key('phone_number')
      expect(sco).not_to have_key('phone_area_code')
      expect(sco).not_to have_key('phone_extension')
    end
  end
end
