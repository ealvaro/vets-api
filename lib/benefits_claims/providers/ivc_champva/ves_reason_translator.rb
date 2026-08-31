# frozen_string_literal: true

require 'ivc_champva/config_file_loader'

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
          StatsD.increment(::IvcChampva::ConfigFileLoader::SILENT_FAILURE_METRIC,
                           tags: ["context:#{::IvcChampva::ConfigFileLoader.sanitize_tag_value(name)}"])
          {}.freeze
        end

        # Incremented when a raw VES reason code isn't in REASON_MAP at all (as opposed to
        # being a known code whose value is intentionally null, pending content sign-off --
        # see the map's _comment). An unmapped code means VES introduced/changed a code this
        # map doesn't know about yet, and the FE silently renders no reason text for it.
        UNMAPPED_REASON_METRIC = 'ivc_champva.eligibility.ves_reason_code_unmapped'

        # Substitutes the reason map's literal "[Name]" placeholder with the person's first name.
        # Unmapped codes return nil (instead of the raw code) so the FE never has to distinguish
        # a raw code from plain-language text. The single call site (ClaimBuilder) always calls
        # this alongside .link_for for the same raw_reason, so the unmapped-code metric is
        # tracked only here -- tracking it in both would double-count every occurrence.
        def self.translate(raw_reason, first_name = nil)
          track_if_unmapped(raw_reason)
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

          REASON_MAP[normalize_reason(raw_reason)]
        end

        # @param raw_reason [String, nil]
        # @return [void]
        def self.track_if_unmapped(raw_reason)
          return if raw_reason.blank?
          return if REASON_MAP.key?(normalize_reason(raw_reason))

          Rails.logger.warn(
            '[BenefitsClaims::Providers::IvcChampva::VesReasonTranslator] Unmapped VES reason code',
            { raw_reason: }
          )
          # Unlike the 'context:' tags elsewhere in this file, this value comes straight from
          # VES (external, uncontrolled) rather than a hardcoded Ruby class name -- sanitizing
          # is even more important here, since an unmapped code is by definition one we've never
          # seen before and can't assume is colon-free.
          StatsD.increment(
            UNMAPPED_REASON_METRIC,
            tags: ["reason:#{::IvcChampva::ConfigFileLoader.sanitize_tag_value(normalize_reason(raw_reason))}"]
          )
        end

        # @param raw_reason [String]
        # @return [String]
        def self.normalize_reason(raw_reason)
          raw_reason.to_s.downcase.strip
        end
      end
    end
  end
end
