# frozen_string_literal: true

module SignIn
  class DeviceParser
    PARSER = UserAgentParser::Parser.new

    def initialize(user_agent)
      @user_agent = user_agent
    end

    def perform
      return { browser: nil, device_description: nil } if user_agent.blank?

      { browser:, device_description: }
    rescue => e
      Rails.logger.info("[SignIn::DeviceParser] parse error: #{e.message}")
      { browser: nil, device_description: nil }
    end

    private

    attr_reader :user_agent

    def parsed
      @parsed ||= PARSER.parse(user_agent)
    end

    def browser
      parsed.family
    end

    def device_description
      device = parsed.device&.family
      return device if device.present? && device != 'Other'

      os_description
    end

    def os_description
      os = parsed.os
      name = os&.family
      return name if name.blank?

      version = os.version&.to_s.presence
      version ? "#{name} #{version}" : name
    end
  end
end
