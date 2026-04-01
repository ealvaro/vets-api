# frozen_string_literal: true

module Vass
  module Logging
    extend ActiveSupport::Concern

    RESERVED_LOG_KEYS = %i[service timestamp controller action event error_code class_name vass_uuid].freeze
    private_constant :RESERVED_LOG_KEYS

    private

    ##
    # Logs an informational VASS event.
    #
    # @param event [String] Event name (e.g. 'otp_generated', 'jwt_issued')
    # @param vass_uuid [String, nil] Optional VASS UUID for traceability
    # @param level [Symbol] Log level (defaults to :info)
    # @param metadata [Hash] Additional metadata to include in the log
    #
    def log_vass_event(event, vass_uuid: nil, level: :info, **metadata)
      write_vass_log(event:, vass_uuid:, level:, **metadata.except(*RESERVED_LOG_KEYS))
    end

    ##
    # Logs a VASS error condition.
    #
    # @param error_code [String] Error identifier (e.g. 'missing_contact_info', 'auth_failure')
    # @param vass_uuid [String, nil] Optional VASS UUID for traceability
    # @param level [Symbol] Log level (defaults to :error)
    # @param metadata [Hash] Additional metadata to include in the log
    #
    def log_vass_error(error_code, vass_uuid: nil, level: :error, **metadata)
      write_vass_log(error_code:, vass_uuid:, level:, **metadata.except(*RESERVED_LOG_KEYS))
    end

    def write_vass_log(event: nil, error_code: nil, vass_uuid: nil, level: :info, **metadata)
      raise ArgumentError, 'Provide event or error_code, not both' if event && error_code

      valid_levels = %i[debug info warn error fatal]
      level = :info unless valid_levels.include?(level)

      log_data = metadata.merge(service: 'vass', timestamp: Time.current.iso8601)

      if respond_to?(:controller_name)
        log_data[:controller] = controller_name
        log_data[:action] = action_name if respond_to?(:action_name)
      else
        log_data[:class_name] = self.class.name
      end

      log_data[:event] = event if event
      log_data[:error_code] = error_code if error_code
      log_data[:vass_uuid] = vass_uuid if vass_uuid

      Rails.logger.public_send(level, log_data.to_json)
    rescue JSON::GeneratorError, Encoding::UndefinedConversionError => e
      raise Vass::Errors::AuditLogError, "Failed to write audit log: #{e.message}"
    end
  end
end
