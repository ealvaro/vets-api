# frozen_string_literal: true

module SearchKendra
  class QueryNormalizer
    REPLACEMENTS = YAML.safe_load(
      Rails.root.join('config', 'search', 'query_replacements.yml').read
    ).freeze

    def self.normalize(query)
      normalized = query.to_s.downcase.strip
      REPLACEMENTS.fetch(normalized, normalized)
    end
  end
end
