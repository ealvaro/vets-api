# frozen_string_literal: true

require 'rspec/expectations'

# NOTE: This matcher is only for validating non-request/response JSON (e.g., log output).
# For validating API request and response bodies in request specs, use `assert_schema_conform`
# from CommitteeHelper, which validates against the OpenAPI spec (modules/mobile/docs/openapi.json).
#
# Usage:
#   include JsonSchemaMatchers
#   match_json_schema('schema_name')
module JsonSchemaMatchers
  extend RSpec::Matchers::DSL

  matcher :match_json_schema do |schema_name, options = {}|
    schema_path = Rails.root.join('modules', 'mobile', 'spec', 'support', 'schemas', "#{schema_name}.json").to_s
    match { |data| JSON::Validator.validate!(schema_path, data, options) }
  end
end
