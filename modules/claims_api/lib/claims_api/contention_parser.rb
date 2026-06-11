# frozen_string_literal: true

module ClaimsApi
  module ContentionParser
    # When we submit disabilities to BGS, they format the values coming back as
    # disabilityName (disabilityActionType),
    # For backwards compatibility  we are matching on any disabilityActionTypes we have ever provided
    DISABILITY_ACTION_TYPE = %w[New Secondary None Increase].freeze

    def self.parse(raw)
      return [] if raw.blank?

      parts = raw.split(/,\s*/)
      entries = []
      current = []

      parts.each do |part|
        part = part.strip
        next if part.blank?

        current << part
        if DISABILITY_ACTION_TYPE.any? { |tag| part.end_with?("(#{tag})") }
          entries << current.join(', ')
          current = []
        end
      end

      # Handle any remaining parts that contain at least one non-blank element
      entries << current.join(', ') if current.any?(&:present?)

      entries
    end
  end
end
