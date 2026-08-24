# frozen_string_literal: true

module DisabilityCompensation
  module ServiceConnected
    SERVICE_CONNECTED_DECISIONS = ['service connected', '1151 granted'].freeze

    def service_connected?(decision_text)
      SERVICE_CONNECTED_DECISIONS.include?(decision_text&.downcase)
    end
  end
end
