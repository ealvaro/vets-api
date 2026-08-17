# frozen_string_literal: true

# HTTP client configuration for the RepresentationManagement::GCLAWS::Client
#
module RepresentationManagement
  module GCLAWS
    class Configuration
      DEFAULT_SORT_PARAMS = {
        'agents' => {
          'sortColumn' => 'LastName',
          'sortOrder' => 'ASC'
        },
        'attorneys' => {
          'sortColumn' => 'Number',
          'sortOrder' => 'ASC'
        },
        # The representatives endpoint only honors LastName/FirstName as sort columns; any other value is
        # ignored and falls back to the default (LastName). LastName gives the best paginated coverage and
        # stability of the two, though the endpoint is non-deterministic so minor churn remains. See #126323.
        'representatives' => {
          'sortColumn' => 'LastName',
          'sortOrder' => 'ASC'
        },
        'veteran_service_organizations' => {
          'sortColumn' => 'Organization.OrganizationName',
          'sortOrder' => 'ASC'
        }
      }.freeze

      URL_MAPPING = {
        'agents' => Settings.gclaws.accreditation.agents.url,
        'attorneys' => Settings.gclaws.accreditation.attorneys.url,
        'representatives' => Settings.gclaws.accreditation.representatives.url,
        'representative_contacts' => Settings.gclaws.accreditation.representative_contacts.url,
        'veteran_service_organizations' => Settings.gclaws.accreditation.veteran_service_organizations.url
      }.freeze

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 30

      def initialize(type:, page: nil, page_size: nil)
        @type = type
        @page = page
        @page_size = page_size
      end

      def connection
        Faraday.new(url:, params:, headers:) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson\b/
          conn.adapter Faraday.default_adapter
        end
      end

      # Builds a Faraday connection for POST requests (no query params).
      # Reuses the shared URL_MAPPING and headers so auth/URL logic stays in one place.
      def post_connection
        Faraday.new(url:, headers:) do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          conn.request :json
          conn.response :json, content_type: /\bjson\b/
          conn.adapter Faraday.default_adapter
        end
      end

      private

      def api_key
        Settings.gclaws.accreditation.api_key
      end

      def headers
        {
          'x-api-key' => api_key,
          'Origin' => origin
        }
      end

      def origin
        Settings.gclaws.accreditation.origin
      end

      def params
        DEFAULT_SORT_PARAMS[@type].merge({ 'page' => @page, 'pageSize' => @page_size })
      end

      def url
        URL_MAPPING[@type]
      end
    end
  end
end
