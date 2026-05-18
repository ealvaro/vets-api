# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module PaginatedService
      class ChargeItemService
        include PagedResource

        # Keep in sync with MedicalCopays::LighthouseIntegration::Service::CHARGE_ITEM_FETCH_LIMIT
        CHARGE_ITEM_FETCH_LIMIT = 100
        MAX_CHARGE_ITEM_SEARCH_PAGES = 40

        def initialize(icn)
          @icn = icn
        end

        def fetch_paginated_charge_items(charge_item_ids)
          needed = Array(charge_item_ids).compact.uniq.to_set
          return {} if needed.empty?

          result = fetch_paged_resources(
            service: lighthouse_charge_item_client,
            max_pages: MAX_CHARGE_ITEM_SEARCH_PAGES,
            count: CHARGE_ITEM_FETCH_LIMIT
          ) { |entry| needed.include?(entry.dig('resource', 'id')) }

          result['entries'].each_with_object({}) do |entry, hash|
            resource = entry['resource']
            hash[resource['id']] = resource if resource && resource['id']
          end
        rescue => e
          Rails.logger.warn { "Failed to fetch charge items (paginated service): #{e.class}" }
          {}
        end

        private

        def lighthouse_charge_item_client
          @lighthouse_charge_item_client ||= ::Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service.new(@icn)
        end
      end
    end
  end
end
