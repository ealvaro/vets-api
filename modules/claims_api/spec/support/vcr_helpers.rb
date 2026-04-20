# frozen_string_literal: true

# Shared VCR helper methods for extracting response data from VCR cassettes
module VcrHelpers
  # Helper method to extract VCR response data
  def self.load_vcr_response_data(cassette_path, interaction_index = 0)
    cassette_file = Rails.root.join('spec', 'support', 'vcr_cassettes', "#{cassette_path}.yml")
    cassette_data = YAML.safe_load(File.read(cassette_file), aliases: true)
    response_body = cassette_data['http_interactions'][interaction_index]['response']['body']['string']
    JSON.parse(response_body, symbolize_names: true)
  end
end
