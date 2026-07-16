# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module OrganizationHelper
      ORG_CACHE_STATSD_KEY = 'api.mcp.lighthouse.org_cache'

      def fetch_organization(org_id, statsd_key = ORG_CACHE_STATSD_KEY)
        return nil if org_id.blank?

        cache_miss = false
        organization = Rails.cache.fetch("lighthouse:org:#{org_id}", expires_in: 24.hours, skip_nil: true) do
          cache_miss = true
          organization_service.read(org_id)&.dig('entry', 0, 'resource')
        end

        StatsD.increment(statsd_key, tags: ["result:#{cache_miss ? 'miss' : 'hit'}"])
        organization
      end

      private

      def retrieve_organization_address(org_id)
        address = fetch_organization(org_id)&.dig('address', 0)

        return nil unless address

        {
          address_line1: address.dig('line', 0),
          address_line2: address.dig('line', 1),
          address_line3: address.dig('line', 2),
          city: address['city'],
          state: address['state'],
          postalCode: address['postalCode']
        }
      rescue => e
        Rails.logger.error { "Failed to fetch organization address: #{e.class}" }
        raise
      end
    end
  end
end
