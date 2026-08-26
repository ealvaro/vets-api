# frozen_string_literal: true

module IvcChampva
  # Loader for the small, static reference JSON files under config/benefits_claims/
  # (allowlists, reason maps, status sets) that CHAMPVA code loads once at
  # class-definition time. Centralizes the "JSON.parse a path, rescue, log, fall
  # back" shape previously copied independently in ChampvaEligibilityService's
  # DOCUMENTS_REQUESTED_CONFIG, VesReasonTranslator's REASON_MAP, and
  # RepeatIneligibilityLetterActivity's SENT_LETTER_STATUSES.
  #
  # New CHAMPVA config consumers should use this rather than reimplementing the
  # load/rescue/log pattern again. (The three existing copies above are left
  # as-is here rather than retrofitted, to keep this change scoped to the new
  # allowlist that motivated it.)
  module ConfigFileLoader
    # @param path [Pathname, String] path to the JSON file
    # @param context [String] short identifier for the log message (typically the
    #   calling class/module name), so a load failure is traceable to its caller
    # @param fallback [Object] value to return if the file is missing or invalid JSON
    # @return [Object] the parsed JSON (Hash/Array/etc.), or `fallback` on failure
    def self.load(path, context:, fallback: {})
      JSON.parse(File.read(path))
    rescue => e
      Rails.logger.error(
        "#{context}: Failed to load config file #{path}",
        { message: e.message }
      )
      fallback
    end
  end
end
