# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module PaginatedService
      module PagedResource
        def fetch_paged_resources(service:, max_pages:, count:, page_params: {}, &include_entry)
          collected = []
          last_raw = nil

          (1..max_pages).each do |page|
            raw = service.list(count:, page:, **page_params)
            last_raw = raw
            entries = raw['entry'] || []

            break if entries.empty?

            entries.each do |entry|
              collected << entry if include_entry.nil? || include_entry.call(entry)
            end

            next_link = raw['link']&.find { |l| l['relation'] == 'next' }
            break if next_link.blank?
          end

          { 'raw_bundle' => last_raw, 'entries' => collected }
        end
      end
    end
  end
end
