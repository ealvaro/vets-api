# frozen_string_literal: true

require 'dependents_benefits/helper'

module DependentsBenefits
  module ClaimBehavior
    ##
    # Methods for form schema validation and data transformation
    #
    module FormValidation
      extend ActiveSupport::Concern
      include DependentsBenefits::Helper

      # @see ::SavedClaim#form_schema
      def form_schema(form_id)
        # we want to normalize the legacy identifier then append version to match what may be in vets-json-schema
        # TODO: eliminate the appended version number in all places (future)
        fid = "#{form_id.sub('-V2', '')}-V2"
        VetsJsonSchema::SCHEMAS[fid] || VetsJsonSchema::SCHEMAS[form_id] || raise(Errno::ENOENT, fid)
      rescue => e
        monitor.track_error_event('Dependents Benefits form schema could not be loaded.',
                                  action: 'schema_load_error', component:, form_id:, error: e.message)
        nil
      end

      ##
      # Validates whether the form matches the expected VetsJsonSchema::JSON schema
      #
      # @return [void]
      def form_matches_schema
        return unless form_is_string

        schema = form_schema(form_id)

        schema_errors = validate_schema(schema)
        unless schema_errors.empty?
          monitor.track_error_event('Dependents Benefits schema failed validation.',
                                    action: 'schema_error', component:,
                                    form_id:, errors: schema_errors)
        end

        validation_errors = validate_form(schema)
        validation_errors.each do |e|
          errors.add(e[:fragment], e[:message])
          e[:errors]&.flatten(2)&.each { |nested| errors.add(nested[:fragment], nested[:message]) if nested.is_a? Hash }
        end

        unless validation_errors.empty?
          monitor.track_error_event('Dependents Benefits form did not pass validation.',
                                    action: 'validation_error', component:,
                                    form_id:, guid:, errors: validation_errors)
        end

        schema_errors.empty? && validation_errors.empty?
      end

      private

      # Validates the form data against the provided JSON schema
      #
      # Camelizes the form keys to match schema expectations and validates using JSONSchemer.
      # Returns reformatted error messages if validation fails.
      #
      # @param schema [Hash] The JSON schema to validate against
      # @return [Array<Hash>] Array of validation errors, empty if validation succeeds
      def validate_form(schema)
        form_data = parsed_form.deep_dup
        dependents_application = form_data.delete('dependents_application') || {}
        flattened_form = form_data.merge(dependents_application)
        camelized_data = deep_camelize_keys(flattened_form)

        errors = JSONSchemer.schema(schema).validate(camelized_data).to_a
        return [] if errors.empty?

        reformatted_schemer_errors(errors)
      end
    end
  end
end
