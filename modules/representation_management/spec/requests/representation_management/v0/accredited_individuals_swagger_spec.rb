# frozen_string_literal: true

require 'swagger_helper'
require Rails.root.join('spec', 'rswag_override.rb').to_s
require_relative '../../../support/swagger_shared_components/v0'

RSpec.describe 'Accredited Individuals',
               openapi_spec: 'modules/representation_management/app/swagger/v0/swagger.json',
               type: :request do
  before do
    allow(Flipper).to receive(:enabled?).with(:find_a_representative_use_accredited_models).and_return(true)

    create(:accredited_individual,
           :with_location,
           first_name: 'Bob',
           last_name: 'Law',
           full_name: 'Bob Law',
           address_type: 'Domestic',
           address_line1: '123 Main St',
           city: 'Anytown',
           country_name: 'USA',
           country_code_iso3: 'USA',
           province: 'New York',
           state_code: 'NY',
           zip_code: '12345',
           phone: '123-456-7890',
           email: 'boblaw@example.com',
           individual_type: 'attorney')
  end

  path '/representation_management/v0/accredited_individuals' do
    get('Search for accredited individuals') do
      tags 'Accredited Individuals'
      consumes 'application/json'
      produces 'application/json'
      operationId 'searchAccreditedIndividuals'
      description 'Returns accredited individuals based on search criteria including location and type'

      parameter name: :lat, in: :query, example: 40.7128, required: true,
                description: 'Latitude coordinate',
                schema: {
                  type: :number,
                  format: :float
                }
      parameter name: :long, in: :query, example: -74.0060, required: true,
                description: 'Longitude coordinate',
                schema: {
                  type: :number,
                  format: :float
                }
      parameter name: :type, in: :query, required: true,
                description: 'Type of accredited individual',
                schema: {
                  type: :string,
                  enum: %w[attorney claims_agent representative]
                }
      parameter name: :distance, in: :query, example: 50, required: false,
                description: 'Maximum distance in miles. If not provided, accredited individuals will not be ' \
                             'filtered by distance.',
                schema: {
                  type: :integer,
                  enum: [5, 10, 25, 50, 100, 200]
                }
      parameter name: :name, in: :query, example: 'John Doe', required: false,
                description: 'Name to search for. A fuzzy match is performed. If not provided, accredited ' \
                             'individuals will not be filtered by name.',
                schema: {
                  type: :string
                }
      parameter name: :org_name, in: :query, example: 'Organization Name', required: false,
                description: 'Name of the Veterans Service Organization (VSO). Must be an exact match. If not ' \
                             'provided, individuals will not be filtered by organization affiliation. Parameter ' \
                             'is ignored if the "type" parameter value is not "representative."',
                schema: {
                  type: :string
                }
      parameter name: :page, in: :query, required: false,
                description: 'Page number',
                schema: {
                  type: :integer,
                  default: 1
                }
      parameter name: :per_page, in: :query, required: false,
                description: 'Number of results per page',
                schema: {
                  type: :integer,
                  default: 10
                }
      parameter name: :sort, in: :query, required: false,
                description: 'Sort order',
                schema: {
                  type: :string,
                  enum: %w[distance_asc first_name_asc first_name_desc last_name_asc last_name_desc],
                  default: 'distance_asc'
                }

      response '200', 'OK' do
        let(:lat) { 40.7128 }
        let(:long) { -74.0060 }
        let(:type) { 'attorney' } # Query parameter - doesn't conflict with RSpec's type: :request
        let(:distance) { 50 }
        let(:name) { 'Bob Law' }
        let(:page) { 1 }
        let(:per_page) { 10 }
        let(:sort) { 'distance_asc' }

        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { '$ref' => '#/components/schemas/accreditedIndividual' }
                 },
                 meta: {
                   type: :object,
                   properties: {
                     pagination: {
                       type: :object,
                       properties: {
                         current_page: { type: :integer, example: 1 },
                         per_page: { type: :integer, example: 10 },
                         total_pages: { type: :integer, example: 1 },
                         total_entries: { type: :integer, example: 1 }
                       }
                     }
                   }
                 }
               }
        run_test!
      end

      response '400', 'bad request response' do
        let(:lat) { nil }
        let(:long) { nil }
        let(:type) { nil }
        let(:distance) { nil }
        let(:name) { nil }
        let(:page) { nil }
        let(:per_page) { nil }
        let(:sort) { nil }

        schema type: :object,
               properties: {
                 errors: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       title: { type: :string },
                       detail: { type: :string },
                       code: { type: :string },
                       status: { type: :string }
                     }
                   }
                 }
               }
        run_test!
      end

      response '422', 'unprocessable content response' do
        let(:lat) { 40.7128 }
        let(:long) { -74.0060 }
        let(:type) { 'invalid_type' }
        let(:distance) { nil }
        let(:name) { nil }
        let(:page) { nil }
        let(:per_page) { nil }
        let(:sort) { nil }

        schema '$ref' => '#/components/schemas/errors'
        run_test!
      end
    end
  end
end
