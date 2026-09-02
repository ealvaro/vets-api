# frozen_string_literal: true

class SavedClaim::DisabilityCompensation::Form526AllClaim < SavedClaim::DisabilityCompensation
  # sets the form and validation schema for this saved claim
  add_form_and_validation('21-526EZ-ALLCLAIMS')

  STRICT_SCHEMA = '21-526EZ-ALLCLAIMS-STRICT'

  # shared allowlist of keys safe to log for hardened-validation errors
  HARDENED_ERROR_LOG_KEYS = %i[message data_pointer].freeze

  def form_schema
    enforce_hardened_schema? ? VetsJsonSchema::SCHEMAS[STRICT_SCHEMA] : super
  end

  def form_matches_schema
    valid = super
    return if valid.nil? # @see SavedClaim#form_is_string

    # prevent double validation if schema hardening is enforced
    return valid if enforce_hardened_schema?

    # only log schema hardening events if the feature flag is enabled
    # and there are no errors from the original validation
    log_hardened_validation_errors if Flipper.enabled?(:disability_526_schema_hardening_logging) && valid

    valid
  end

  private

  # get the flipper status for the schema hardening enforcement flag
  def enforce_hardened_schema?
    Flipper.enabled?(:disability_526_schema_hardening_enforce)
  end

  # LOGGING ONLY - runs hardened schema validation and logs any errors,
  # without affecting the original validation result
  def log_hardened_validation_errors
    schema = VetsJsonSchema::SCHEMAS[STRICT_SCHEMA]

    schema_errors = validate_schema(schema)
    unless schema_errors.empty?
      Rails.logger.error("#{self.class} HARDENED schema failed validation.",
                         { errors: slice_errors(schema_errors), form_id:, guid: })
    end

    validation_errors = validate_form(schema)
    unless validation_errors.empty?
      Rails.logger.error("#{self.class} form did not pass HARDENED validation",
                         { errors: slice_errors(validation_errors), form_id:, guid: })
    end
  rescue => e
    Rails.logger.warn("#{self.class} hardened-validation logging failed", { error: e.message, form_id:, guid: })
  end

  # slices each error down to only the keys defined in HARDENED_ERROR_LOG_KEYS
  def slice_errors(errors)
    errors.map { |e| e.slice(*HARDENED_ERROR_LOG_KEYS) }
  end
end
