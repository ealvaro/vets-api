# frozen_string_literal: true

class SavedClaim::DisabilityCompensation::Form526AllClaim < SavedClaim::DisabilityCompensation
  # sets the form and validation schema for this saved claim
  add_form_and_validation('21-526EZ-ALLCLAIMS')

  STRICT_SCHEMA = '21-526EZ-ALLCLAIMS-STRICT'

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
    if Flipper.enabled?(:disability_526_schema_hardening_logging) && valid
      # LOGGING ONLY
      schema = VetsJsonSchema::SCHEMAS[STRICT_SCHEMA]

      schema_errors = validate_schema(schema)
      unless schema_errors.empty?
        Rails.logger.error("#{self.class} HARDENED schema failed validation.",
                           { errors: schema_errors, form_id:, guid: })
      end

      validation_errors = validate_form(schema)
      unless validation_errors.empty?
        Rails.logger.error("#{self.class} form did not pass HARDENED validation",
                           { errors: validation_errors, form_id:, guid: })
      end

      # pass thru the original validation result
    end

    valid
  end

  private

  # get the flipper status for the schema hardening enforcement flag
  def enforce_hardened_schema?
    Flipper.enabled?(:disability_526_schema_hardening_enforce)
  end
end
