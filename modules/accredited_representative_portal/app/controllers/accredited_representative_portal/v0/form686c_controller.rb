# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class Form686cController < ApplicationController
      include AccreditedRepresentativePortal::V0::RepresentativeFormUploadConcern

      before_action :feature_enabled
      before_action :authorize_form_submission

      class DependentInformation
        include Vets::Model

        attribute :fullName, FormFullName
        attribute :dateOfBirth, Date
        attribute :ssn, String
        attribute :relationshipToVeteran, String
        attribute :awardIndicator, String
      end

      def dependents
        ar_monitoring(with_organization: true).trace('ar.claims.686cv2.dependents') do
          dependents = BGS::DependentService.new(veteran_identity).get_dependents
          persons = if dependents.blank? || dependents[:persons].blank?
                      []
                    else
                      dependents[:persons]
                    end
          @dependents_information = persons.filter_map do |person|
            person_to_dependent_information(person)
          end
          render json: @dependents_information
        end
      rescue
        render json: []
      end

      private

      def ar_monitoring(with_organization:)
        org_tag = ("org:#{organization}" if with_organization && organization.present?)

        AccreditedRepresentativePortal::Monitoring.new(
          AccreditedRepresentativePortal::Monitoring::NAME,
          default_tags: [
            "controller:#{controller_name}",
            "action:#{action_name}",
            org_tag,
            ('org_resolve:failed' if with_organization && org_tag.nil?)
          ].compact
        )
      end

      def organization
        claimant_representative&.power_of_attorney_holder&.poa_code
      rescue AccreditedRepresentativePortal::ClaimantRepresentative::Finder::Error
        nil
      end

      def veteran_identity
        @veteran_identity ||= VeteranIdentity.new(mpi_profile, @current_user, params[:veteranTempId])
      end

      def feature_enabled
        routing_error unless Flipper.enabled?(:accredited_representative_portal_submit_686c_v2)
      end

      def mpi_profile
        return @mpi_profile if @mpi_profile.present?

        mpi_response =
          MPI::Service.new.find_profile_by_identifier(
            identifier: claimant_icn,
            identifier_type: MPI::Constants::ICN
          )
        profile = mpi_response.profile
        raise Common::Exceptions::ServiceUnavailable.new, 'MPI outage' if mpi_response.server_error?
        raise Common::Exceptions::RecordNotFound, 'Claimant not found' if mpi_response.not_found? || profile.blank?

        @mpi_profile = mpi_response.profile
      end

      def authorize_form_submission
        raise Common::Exceptions::RecordNotFound, 'Claimant not found' if claimant_icn.blank?

        authorize(claimant_icn, policy_class: FormSubmissionPolicy)
      end

      def claimant_icn
        @claimant_icn ||= IcnTemporaryIdentifier.lookup_icn(params[:veteranTempId])
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def person_to_dependent_information(person)
        parsed_date = parse_date_safely(person[:date_of_birth])

        DependentInformation.new(
          fullName: FormFullName.new({
                                       first: person[:first_name],
                                       middle: person[:middle_name],
                                       last: person[:last_name]
                                     }),
          dateOfBirth: parsed_date,
          ssn: person[:ssn],
          relationshipToVeteran: person[:relationship],
          awardIndicator: person[:award_indicator]
        )
      end

      ##
      # Safely parses a date string, handling various formats
      #
      # @param date_string [String, Date, nil] The date to parse
      # @return [Date, nil] The parsed date or nil if parsing fails
      def parse_date_safely(date_string)
        return nil if date_string.blank?

        return date_string if date_string.is_a?(Date)

        begin
          Date.strptime(date_string.to_s, '%m/%d/%Y')
        rescue ArgumentError
          Date.parse(date_string.to_s)
        end
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
