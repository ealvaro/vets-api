# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MebApi::V0::ApidocsController, type: :controller do
  routes { MebApi::Engine.routes }

  describe '#index' do
    it 'returns resolved OpenAPI spec as JSON' do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with('application/json')

      json_response = JSON.parse(response.body)

      # Verify basic structure
      expect(json_response['openapi']).to eq('3.0.0')
      expect(json_response['info']['title']).to eq('DGI Education Benefits')

      # Verify $refs are resolved (no $ref keys should remain)
      expect(schema_has_refs?(json_response)).to be(false)

      # Verify schemas are resolved
      expect(json_response['components']['schemas']).to be_present
      expect(json_response['components']['schemas']['ClaimantInfoResponse']).to be_a(Hash)
      expect(json_response['components']['schemas']['ToeClaimantInfoResponse']).to be_a(Hash)

      # Verify new supplemental COE fields are present in ClaimantInfoResponse
      claimant_info_response = json_response['components']['schemas']['ClaimantInfoResponse']
      expect(claimant_info_response['properties']['ssn']).to be_present
      expect(claimant_info_response['properties']['benefits']).to be_present
      expect(claimant_info_response['properties']['has_ch_33_original_claim_in_progress']).to be_present
      expect(claimant_info_response['properties']['ch_33_received_date']).to be_present

      # Verify ToeClaimantInfoResponse has toe_sponsors field
      toe_claimant_info_response = json_response['components']['schemas']['ToeClaimantInfoResponse']
      expect(toe_claimant_info_response['properties']['toe_sponsors']).to be_present

      # Verify error responses are resolved
      expect(json_response['components']['responses']['BadRequest']).to be_a(Hash)
      expect(json_response['components']['responses']['BadRequest']['description']).to be_present
    end

    it 'handles circular references gracefully' do
      swagger = { '$ref' => '#/' }

      expect { controller.send(:resolve_refs, swagger, Pathname.new('/tmp')) }.not_to raise_error
    end

    it 'resolves nested $refs correctly' do
      get :index
      json_response = JSON.parse(response.body)

      # Check that deeply nested schemas are fully resolved
      schemas = json_response['components']['schemas']
      schemas.each_value do |schema|
        # Recursively check there are no unresolved $refs
        expect(schema_has_refs?(schema)).to be(false),
                                            "Found unresolved $ref in schema: #{schema.inspect[0..200]}"
      end
    end
  end

  private

  def schema_has_refs?(obj)
    case obj
    when Hash
      return true if obj.key?('$ref')

      obj.values.any? { |v| schema_has_refs?(v) }
    when Array
      obj.any? { |item| schema_has_refs?(item) }
    else
      false
    end
  end
end
