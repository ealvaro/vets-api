# frozen_string_literal: true

require 'claims_api/v1/poa_pdf_constructor/organization'
require 'claims_api/v1/poa_pdf_constructor/individual'
require 'claims_api/stamp_signature_error'
require 'bd/bd'

module ClaimsApi
  module V1
    class PoaFormBuilderJob < ClaimsApi::ServiceBase
      sidekiq_options retry_for: 48.hours

      # Generate a 21-22 or 21-22a form for a given POA request.
      # Upon successful update of the POA in BGS, PDF is generated and uploaded to BD.
      # Dependent jobs are run synchronously to ensure proper order of operations
      # since the PDF generation depends on a successful POA update.
      #
      # @param power_of_attorney_id [String] Unique identifier of the submitted POA
      def perform(power_of_attorney_id, action, form_number = nil)
        power_of_attorney = ClaimsApi::PowerOfAttorney.find(power_of_attorney_id)
        # update the POA before generating PDF so that the PDF isn't uploaded first on a failed POA update
        run_update_poa_job(power_of_attorney)
        validate_poa_assignment_successful!(power_of_attorney)

        generate_pdf_and_upload(power_of_attorney, action, form_number)
      rescue Errno::ENOENT
        rescue_file_not_found(power_of_attorney)
      rescue ClaimsApi::StampSignatureError => e
        signature_errors = (power_of_attorney.signature_errors || []).push(e.detail)
        power_of_attorney.update(status: ClaimsApi::PowerOfAttorney::ERRORED, signature_errors:)
        ClaimsApi::Logger.log('poa', poa_id: power_of_attorney_id, message: 'Prawn Signature Error')
      rescue => e
        rescue_generic_errors(power_of_attorney, e)
        raise
      end

      private

      def generate_pdf_and_upload(power_of_attorney, action, form_number)
        rep_or_org = form_number == '2122A' ? 'representative' : 'serviceOrganization'
        poa_code = power_of_attorney.form_data&.dig(rep_or_org, 'poaCode')

        output_path = pdf_constructor(poa_code).construct(data(power_of_attorney), id: power_of_attorney.id)

        doc_type = form_number == '2122' ? 'L190' : 'L075'
        benefits_doc_upload(poa: power_of_attorney, pdf_path: output_path, doc_type:, action:)
      end

      def benefits_doc_upload(poa:, pdf_path:, doc_type:, action:)
        PoaDocumentService.new.create_upload(poa:, pdf_path:, doc_type:, action:)
      end

      def pdf_constructor(poa_code)
        if poa_code_in_organization?(poa_code)
          ClaimsApi::V1::PoaPdfConstructor::Organization.new
        else
          @rep = ClaimsApi::AccreditationTables.representative.where('? = ANY(poa_codes)',
                                                                     poa_code).order(created_at: :desc).first
          ClaimsApi::V1::PoaPdfConstructor::Individual.new
        end
      end

      # running jobs synchronously to ensure POA is updated before PDF generation and upload
      def run_update_poa_job(power_of_attorney)
        if dependent_filing?(power_of_attorney)
          ClaimsApi::PoaAssignDependentClaimantJob.new.perform(power_of_attorney.id)
        else
          ClaimsApi::PoaUpdater.new.perform(power_of_attorney.id)
        end
      end

      # validate success and mark raise error to retry if POA is errored
      def validate_poa_assignment_successful!(power_of_attorney)
        power_of_attorney.reload
        if power_of_attorney.status == ClaimsApi::PowerOfAttorney::ERRORED
          raise ::Common::Exceptions::ServiceError.new(
            detail: power_of_attorney.vbms_error_message
          )
        end
      end

      #
      # Combine form_data with auth_headers
      #
      # @param power_of_attorney [ClaimsApi::PowerOfAttorney] Record for this poa change request
      #
      # @return [Hash] All data to be inserted into pdf
      def data(power_of_attorney)
        if @rep.present?
          power_of_attorney.form_data =
            power_of_attorney.form_data.deep_merge({ 'representative' => { 'type' => @rep.user_types[0] } })
        end

        power_of_attorney.form_data.deep_merge({
                                                 'veteran' => {
                                                   'firstName' => power_of_attorney.auth_headers['va_eauth_firstName'],
                                                   'lastName' => power_of_attorney.auth_headers['va_eauth_lastName'],
                                                   'ssn' => power_of_attorney.auth_headers['va_eauth_pnid'],
                                                   'birthdate' => power_of_attorney.auth_headers['va_eauth_birthdate']
                                                 }
                                               })
      end

      def poa_code_in_organization?(poa_code)
        ClaimsApi::AccreditationTables.organization.find_by(poa: poa_code).present?
      end
    end
  end
end
