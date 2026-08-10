# frozen_string_literal: true

module AccreditedRepresentativePortal
  module PowerOfAttorneyRequestService
    class Create
      ORGANIZATION = PowerOfAttorneyHolder::Types::VETERAN_SERVICE_ORGANIZATION
      ACCREDITED_ENTITY_ERROR = 'poa_code can not be blank'

      # @note For the 21-22 pilot:
      #   1. poa_code is required and it is associated with a Veteran::Service::Organization record
      #   2. the holder_type is always an AccreditedOrganization
      def initialize(claimant:, form_data:, poa_code:, registration_number: nil)
        @claimant = claimant
        @form_data = form_data
        @poa_code = poa_code
        @registration_number = registration_number

        @errors = []
      end

      def call
        @errors << ACCREDITED_ENTITY_ERROR if @poa_code.blank?

        if @errors.any?
          {
            errors: @errors
          }
        else
          {
            request: create_poa_request
          }
        end
      rescue => e
        @errors << e.message

        {
          errors: @errors
        }
      end

      private

      # rubocop:disable Metrics/MethodLength
      def create_poa_request
        ar_monitoring.trace('ar.power_of_attorney_request_service.create',
                            tags: { 'poa_request.poa_code' => @poa_code },
                            root_tags: { 'poa_request.poa_code' => @poa_code }) do |_span|
          request = nil

          ActiveRecord::Base.transaction do
            request = PowerOfAttorneyRequest.new(
              claimant: @claimant,
              power_of_attorney_holder_type: ORGANIZATION,
              accredited_individual_registration_number: @registration_number,
              power_of_attorney_holder_poa_code: @poa_code
            )

            # PowerOfAttorneyForm expects the incoming data to be json, not a hash
            request.build_power_of_attorney_form(data: @form_data.to_json)

            if unresolved_requests.any?
              unresolved_requests.each do |unresolved|
                unresolved.mark_replaced!(request)
              end
            end

            request.save!
          rescue ActiveRecord::RecordInvalid => e
            handle_form_validation_error(request)
            raise e
          end

          pathway = @registration_number.present? ? 'rep_first' : 'org_first'

          Monitoring.new.track_count('ar.poa.request.count')
          Monitoring.new.track_count("ar.poa.request.pathway.#{pathway}")

          request
        end
      end
      # rubocop:enable Metrics/MethodLength

      def handle_form_validation_error(request)
        if request.power_of_attorney_form&.errors&.any?
          form = request.power_of_attorney_form
          schema_errors = form.schema_validation_errors || []

          # Only track and log if there are actual schema validation errors
          if schema_errors.any?
            ar_monitoring.track_count(
              'ar.poa.form.schema_validation_error',
              tags: {
                'poa_request.poa_code' => @poa_code,
                'form.error_count' => schema_errors.length.to_s
              }
            )

            Rails.logger.error(
              'POA form schema validation failed',
              {
                poa_code: @poa_code,
                errors: schema_errors.map { |e| "#{e['instanceLocation']} #{e['error']}".strip }
              }
            )
          end
        end
      end

      def ar_monitoring
        @ar_monitoring ||= AccreditedRepresentativePortal::Monitoring.new(
          AccreditedRepresentativePortal::Monitoring::NAME,
          default_tags: [].compact
        )
      end

      def unresolved_requests
        @unresolved_requests ||= PowerOfAttorneyRequest.unresolved.where(claimant: @claimant)
      end
    end
  end
end
