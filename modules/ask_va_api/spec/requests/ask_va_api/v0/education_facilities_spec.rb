# frozen_string_literal: false

require 'rails_helper'

RSpec.describe 'AskVAApi::V0::EducationFacilities', type: :request do
  include SchemaMatchers

  let(:inflection_header) { { 'X-Key-Inflection' => 'camel' } }

  # response shape expected by the frontend
  def expect_institution_detail_shape(response_body)
    body = JSON.parse(response_body)

    expect(body).to include(
      'data' => a_hash_including(
        'id',
        'attributes' => a_hash_including(
          'facility_code',
          'name',
          'physical_state',
          'physical_zip'
        )
      ),
      'links' => a_hash_including('self')
    )
  end

  # response shape expected by the frontend
  def expect_institution_search_results_shape(response_body)
    body = JSON.parse(response_body)

    expect(body).to include(
      'data' => a_collection_including(
        a_hash_including(
          'id',
          'attributes' => a_hash_including(
            'facility_code',
            'name',
            'physical_state',
            'physical_zip'
          )
        )
      ),
      'links' => a_hash_including('self'),
      'meta' => a_hash_including('count')
    )
  end

  it 'responds to GET #search' do
    VCR.use_cassette('gi_client/v1/gets_institution_search_results') do
      get '/ask_va_api/v0/education_facilities/search?name=illinois'
    end
    expect(response).to be_successful
    expect_institution_search_results_shape(response.body) # assert response shape for search
  end

  it 'responds to GET #search when camel-inflected' do
    VCR.use_cassette('gi_client/v1/gets_institution_search_results') do
      get '/ask_va_api/v0/education_facilities/search?name=illinois', headers: inflection_header
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end

  it 'responds to GET #search with bad encoding' do
    VCR.use_cassette('gi_client/v1/gets_institution_search_results') do
      get '/ask_va_api/v0/education_facilities/search?name=%ADillinois'
    end

    expect(response).to be_successful
  end

  it 'responds to GET #show' do
    VCR.use_cassette('gi_client/v1/gets_the_institution_details') do
      get '/ask_va_api/v0/education_facilities/11902614'
    end

    expect(response).to be_successful
    expect_institution_detail_shape(response.body) # assert response shape for show
  end

  it 'responds to GET #show when camel-inflected' do
    VCR.use_cassette('gi_client/v1/gets_the_institution_details') do
      get '/ask_va_api/v0/education_facilities/11902614', headers: inflection_header
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end

  it 'responds to GET #autocomplete' do
    VCR.use_cassette('gi_client/gets_a_list_of_institution_autocomplete_suggestions') do
      get '/ask_va_api/v0/education_facilities/autocomplete?term=university'
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end

  it 'responds to GET #autocomplete when camel-inflected' do
    VCR.use_cassette('gi_client/gets_a_list_of_institution_autocomplete_suggestions') do
      get '/ask_va_api/v0/education_facilities/autocomplete?term=university', headers: inflection_header
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end

  it 'responds to GET #autocomplete with bad encoding' do
    VCR.use_cassette('gi_client/gets_a_list_of_institution_autocomplete_suggestions') do
      get '/ask_va_api/v0/education_facilities/autocomplete?term=%ADuniversity'
    end

    expect(response).to be_successful
  end

  it 'responds to GET institution #children' do
    VCR.use_cassette('gi_client/gets_the_institution_children') do
      get '/ask_va_api/v0/education_facilities/10086018/children'
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end

  it 'responds to GET institution #children when camel-inflected' do
    VCR.use_cassette('gi_client/gets_the_institution_children') do
      get '/ask_va_api/v0/education_facilities/10086018/children', headers: inflection_header
    end

    expect(response).to be_successful
    expect(response.body).to be_a(String)
  end
end
