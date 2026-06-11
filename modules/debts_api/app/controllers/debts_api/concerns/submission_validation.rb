# frozen_string_literal: true

require 'debt_management_center/debts_service'
require 'debt_management_center/constants'

module DebtsApi
  module Concerns
    module SubmissionValidation
      extend ActiveSupport::Concern

      class BaseValidator
        class FormInvalid < ArgumentError; end

        class << self
          INVALID_ERROR_MESSAGE = 'Invalid request payload schema'

          def validate_form_schema(form, schema_file)
            schema_path = Rails.root.join('lib', 'debt_management_center', 'schemas', schema_file).to_s
            errors = JSON::Validator.fully_validate(schema_path, form)

            log_and_raise_error(errors) if errors.any?
          end

          def log_and_raise_error(errors, error_class: FormInvalid, message: INVALID_ERROR_MESSAGE, error: nil)
            Rails.logger.error(errors)
            raise error if error

            raise error_class, message
          end
        end
      end

      class FSRValidator < BaseValidator
        REQUIRED_SUPPORTING_STATEMENT_OPTIONS = %w[
          compromise
          hardship-suspension
          monthly
          waiver
        ].freeze

        class << self
          def validate_supporting_statement(form)
            selected_debts = Array(form['selectedDebtsAndCopays'])
            resolution_options = selected_debts.pluck('resolutionOption').compact
            required_options = resolution_options & REQUIRED_SUPPORTING_STATEMENT_OPTIONS
            supporting_statement = form.dig('additionalData', 'additionalComments')
            supporting_statement_blank = supporting_statement.to_s.strip.blank?

            return unless required_options.any? && supporting_statement_blank

            StatsD.increment(
              "#{DebtsApi::V0::Form5655Submission::STATS_KEY}.supporting_statement.blank"
            )
            log_and_raise_error(
              'Supporting personal statement is required',
              error: Common::Exceptions::UnprocessableEntity.new(
                detail: 'Supporting personal statement is required'
              )
            )
          end
        end
      end

      class DisputeDebtValidator < BaseValidator
        class << self
          def validate_form_schema(metadata, user)
            parsed = JSON.parse(metadata)
            disputes = parsed['disputes']
            BaseValidator.validate_form_schema(disputes, 'dispute_debts.json')
            validate_debt_exist_for_user(disputes, user)
            parsed
          end

          private

          def validate_debt_exist_for_user(disputes, user)
            composite_debt_ids = disputes.map { |d| d['composite_debt_id'] }
            log_and_raise_error('At least one composite debt ID is required') if composite_debt_ids.blank?

            debts_service = DebtManagementCenter::DebtsService.new(user)
            found_debts = debts_service.get_debts_by_ids(composite_debt_ids)

            if found_debts.length < composite_debt_ids.length
              missing_count = composite_debt_ids.length - found_debts.length
              log_and_raise_error(
                "Invalid debt identifiers: #{missing_count} of #{composite_debt_ids.length} not found"
              )
            end
          end
        end
      end
    end
  end
end
