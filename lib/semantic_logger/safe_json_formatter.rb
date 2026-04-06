# frozen_string_literal: true

class SafeJsonFormatter < SemanticLogger::Formatters::Json
  # Raw formatter path can call `log.file_name_and_line`, which expects an
  # Exception-like object with a backtrace. Skip source extraction when callers
  # pass non-exceptions such as a String to `exception:`.
  def file_name_and_line
    return if log.exception && !log.exception.respond_to?(:backtrace)

    super
  end

  def exception
    return unless log.exception

    if log.exception.respond_to?(:backtrace)
      super
    else
      hash[:exception] = {
        name: log.exception.class.name,
        message: sanitize_string(log.exception.to_s)
      }
    end
  end

  def call(log, logger)
    super
  rescue JSON::GeneratorError
    fallback = hash || {}
    sanitize_values(fallback).tap do |safe|
      # String keys: sanitize_values normalizes hash keys to UTF-8 strings for JSON.
      safe['level'] ||= log.level.to_s
      safe['message'] ||= '[SafeJsonFormatter: original message unrecoverable]'
      safe['safe_json_formatter_fallback'] = true
    end.to_json
  end

  private

  def sanitize_string(value)
    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  end

  def sanitize_values(value)
    case value
    when String
      sanitize_string(value)
    when Hash
      value.each_with_object({}) do |(key, nested), acc|
        acc[sanitize_hash_key(key)] = sanitize_values(nested)
      end
    when Array
      value.map { |nested| sanitize_values(nested) }
    else
      value
    end
  end

  def sanitize_hash_key(key)
    sanitize_string(key.to_s)
  end
end
