# frozen_string_literal: true

# Use this helper in request specs to validate API request and response bodies against
# the OpenAPI spec (modules/mobile/docs/openapi.json).
#
# Usage:
#   include CommitteeHelper
#   assert_schema_conform(200)
#
# This replaces the legacy match_json_schema matcher for all API request/response validation.
module CommitteeHelper
  include Committee::Rails::Test::Methods

  def committee_options
    @committee_options ||= {
      schema_path: Rails.root.join('modules', 'mobile', 'docs', 'openapi.json').to_s,
      prefix: '/mobile',
      strict_reference_validation: true,
      check_content_type: false
    }
  end
end
