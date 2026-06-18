# frozen_string_literal: true

require_relative 'request_helper'
require_relative 'request_builder'
require 'mpi/constants'

module MPI
  module Messages
    class UnlinkProfileIdentifierMessage
      attr_reader :icn, :identifier_type, :identifier

      def initialize(icn:, identifier_type:, identifier:)
        @icn = icn
        @identifier_type = identifier_type
        @identifier = identifier
      end

      def perform
        validate_required_fields
        MPI::Messages::RequestBuilder.new(extension: MPI::Constants::UPDATE_PROFILE, body: build_body).perform
      rescue => e
        Rails.logger.error "[UnlinkProfileIdentifierMessage] Failed to build request: #{e.message}"
        raise e
      end

      private

      def validate_required_fields
        missing_values = []
        missing_values << :icn if icn.blank?
        missing_values << :identifier if identifier.blank?

        unless [Constants::IDME_UUID, Constants::LOGINGOV_UUID, Constants::MHV_UUID].include?(identifier_type)
          raise Errors::ArgumentError,
                "Invalid identifier type: #{identifier_type}. Must be one of: " \
                "#{Constants::IDME_UUID}, #{Constants::LOGINGOV_UUID}, #{Constants::MHV_UUID}"
        end

        raise Errors::ArgumentError, "Required values missing: #{missing_values}" if missing_values.present?
      end

      def build_body
        element = RequestHelper.build_control_act_process_element
        element << build_subject
        element
      end

      def build_subject
        element = RequestHelper.build_subject_element
        element << build_registration_event
        element
      end

      def build_registration_event
        element = RequestHelper.build_registration_event_element
        element << RequestHelper.build_id_null_flavor(type: null_flavor_type)
        element << RequestHelper.build_status_code
        element << build_subject_one
        element << RequestHelper.build_custodian
        element
      end

      def build_subject_one
        element = RequestHelper.build_subject_1_element
        element << build_patient
        element
      end

      def build_patient
        element = RequestHelper.build_patient_element
        element << RequestHelper.build_identifier(identifier: icn_with_aaid, root:)
        element << RequestHelper.build_status_code
        element << build_patient_person
        element << RequestHelper.build_provider_organization
        element
      end

      def build_patient_person
        element = RequestHelper.build_patient_person_element
        element << RequestHelper.build_unlink_identifier(identifier: formatted_identifier, root:)
        element
      end

      def formatted_identifier
        "#{identifier}^#{csp_identifier}"
      end

      def csp_identifier
        case identifier_type
        when Constants::IDME_UUID
          Constants::IDME_FULL_IDENTIFIER
        when Constants::LOGINGOV_UUID
          Constants::LOGINGOV_FULL_IDENTIFIER
        when Constants::MHV_UUID
          Constants::MHV_FULL_IDENTIFIER
        end
      end

      def null_flavor_type
        'NA'
      end

      def icn_with_aaid
        "#{icn}^NI^200M^USVHA^P"
      end

      def root
        MPI::Constants::VA_ROOT_OID
      end
    end
  end
end
