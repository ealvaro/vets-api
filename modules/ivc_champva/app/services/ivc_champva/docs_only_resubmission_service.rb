# frozen_string_literal: true

module IvcChampva
  class DocsOnlyResubmissionService
    def initialize(current_user:)
      @current_user = current_user
    end

    def call(parsed_form_data)
      controller = IvcChampva::V1::UploadsController.new
      controller.instance_variable_set(:@current_user, @current_user)

      controller.send(:ensure_docs_only_resubmission_enabled, parsed_form_data)
      controller.send(:validate_docs_only_resubmission!, parsed_form_data)
      controller.send(:hydrate_docs_only_resubmission_data, parsed_form_data)
      IvcChampva::MetadataValidator.validate_docs_only_resubmission(parsed_form_data)

      controller.send(:process_docs_only_resubmission, parsed_form_data)
    rescue ArgumentError => e
      Rails.logger.error("Validation error in CHAMPVA docs-only resubmission: #{e.message}")
      { json: { error_message: e.message }, status: 422 }
    rescue => e
      Rails.logger.error("Docs-only resubmission error: #{e.message}")
      Rails.logger.error(Array(e.backtrace).join("\n"))
      { json: { error_message: "Error: #{e.message}" }, status: 500 }
    end
  end
end
