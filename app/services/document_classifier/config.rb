# frozen_string_literal: true

module DocumentClassifier
  module Config
    class Error < StandardError; end

    REQUIRED_SETTINGS = %i[api_key api_version base_url model].freeze

    module_function

    def validate!
      missing = REQUIRED_SETTINGS.select { |name| public_send(name).blank? }
      return if missing.empty?

      raise Error, "Missing document classifier VA GPT settings: #{missing.join(', ')}"
    end

    def api_key = settings.api_key.to_s
    def api_version = settings.api_version.to_s
    def model = settings.model.to_s

    def open_timeout
      value = settings.open_timeout.to_i
      value.positive? ? value : 10
    end

    def read_timeout
      value = settings.read_timeout.to_i
      value.positive? ? value : 60
    end

    def base_url
      value = settings.base_url.to_s
      value.present? ? "#{value.sub(%r{/+\z}, '')}/" : value
    end

    def responses_path
      settings.responses_path.to_s.sub(%r{\A/+}, '')
    end

    def settings
      Settings.document_classifier.va_gpt
    end
  end
end
