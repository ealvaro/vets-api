# frozen_string_literal: true

module BenefitsClaims
  module Providers
    module IvcChampva
      # Translates raw VES eligibility reason codes into plain-language FE copy and
      # extracts any associated link. Kept separate from ClaimBuilder so that module
      # isn't also responsible for reason-map parsing/translation.
      module VesReasonTranslator
        REASON_MAP_PATH = Rails.root.join('config', 'benefits_claims', 'ves_eligibility_reason_map.json').freeze

        REASON_MAP = begin
          JSON.parse(File.read(REASON_MAP_PATH))
              .reject { |k, _| k.start_with?('_') }
              .freeze
        rescue => e
          Rails.logger.error(
            '[BenefitsClaims::Providers::IvcChampva::VesReasonTranslator] Failed to load VES eligibility reason map',
            { message: e.message }
          )
          {}.freeze
        end

        # Substitutes the reason map's literal "[Name]" placeholder with the person's first name.
        # Unmapped codes return nil (instead of the raw code) so the FE never has to distinguish
        # a raw code from plain-language text.
        def self.translate(raw_reason, first_name = nil)
          entry = reason_entry(raw_reason)
          text = entry.is_a?(Hash) ? entry['text'] : entry
          return nil if text.blank?

          text.gsub('[Name]', first_name.presence || 'The applicant')
        end

        # Returns the { 'text' =>, 'url' => } link for a reason code so the FE can render it as
        # a real hyperlink instead of parsing it out of the reason text. Only a couple of reason
        # codes (e.g. the TRICARE ones) have an associated link; everything else returns nil.
        def self.link_for(raw_reason)
          entry = reason_entry(raw_reason)
          entry.is_a?(Hash) ? entry['link'] : nil
        end

        def self.reason_entry(raw_reason)
          return nil if raw_reason.blank?

          REASON_MAP[raw_reason.to_s.downcase.strip]
        end
      end
    end
  end
end
