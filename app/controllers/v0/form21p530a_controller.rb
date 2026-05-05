# frozen_string_literal: true

require 'form21p530a/monitor'

module V0
  class Form21p530aController < ApplicationController
    include RetriableConcern
    include PdfFill::Forms::FormHelper

    service_tag 'state-tribal-interment-allowance'
    skip_before_action :authenticate, unless: :auth_required?
    before_action :load_user, unless: :auth_required?
    before_action :check_feature_enabled

    def create
      claim = build_claim
      monitor.track_submission_begun(claim, user_uuid: current_user&.uuid)

      if claim.save
        claim.process_attachments!
        monitor.track_submission_success(claim, user_uuid: current_user&.uuid)
        clear_saved_form(claim.form_id)
        render json: SavedClaimSerializer.new(claim)
      else
        raise Common::Exceptions::ValidationErrors, claim
      end
    rescue => e
      monitor.track_submission_failure(claim, e, user_uuid: current_user&.uuid)
      raise
    end

    def download_pdf
      pdf_start_time = Time.current
      parsed_form = parse_and_transform_payload
      source_file_path = generate_pdf(parsed_form)
      source_file_path = PdfFill::Forms::Va21p530a.stamp_signature(source_file_path, parsed_form)

      user_uuid = current_user&.uuid
      claim_guid = parsed_form['claimGuid']
      monitor.track_pdf_generation_success(pdf_start_time, user_uuid:, claim_guid:)

      client_file_name = "21P-530a_#{SecureRandom.uuid}.pdf"
      file_contents = File.read(source_file_path)
      send_data file_contents, filename: client_file_name, type: 'application/pdf', disposition: 'attachment'
    rescue Common::Exceptions::ValidationErrors
      raise
    rescue => e
      handle_pdf_generation_error(e, parsed_form)
    ensure
      File.delete(source_file_path) if source_file_path && File.exist?(source_file_path)
    end

    # GET /v0/form21p530a/download_pdf/:guid - Download PDF from saved claim by GUID
    def download_pdf_by_guid
      pdf_start_time = Time.current
      claim_guid = params[:guid]
      claim = SavedClaim::Form21p530a.find_by!(guid: claim_guid)
      source_file_path = claim.to_pdf

      monitor.track_pdf_generation_success(pdf_start_time, user_uuid: current_user&.uuid, claim_guid: claim.guid)

      file_contents = File.read(source_file_path)
      client_file_name = "21P-530a_#{claim.veteran_name.gsub(' ', '_')}.pdf"
      send_data file_contents, filename: client_file_name, type: 'application/pdf', disposition: 'attachment'
    rescue ActiveRecord::RecordNotFound => e
      monitor.track_pdf_generation_failure(e, user_uuid: current_user&.uuid, claim_guid:)
      raise Common::Exceptions::RecordNotFound, claim_guid
    rescue => e
      handle_pdf_generation_error(e, { 'claimGuid' => claim_guid })
    ensure
      File.delete(source_file_path) if source_file_path && File.exist?(source_file_path)
    end

    private

    def check_feature_enabled
      routing_error unless Flipper.enabled?(:form_530a_enabled, current_user)
    end

    def stats_key
      'api.form21p530a'
    end

    def transform_country_codes(payload)
      parsed = JSON.parse(payload)
      address = parsed.dig('burialInformation', 'recipientOrganization', 'address')
      if address&.key?('country')
        transformed_country = extract_country(address)
        if transformed_country
          validate_country_code!(transformed_country)
          address['country'] = transformed_country
        end
      end
      parsed.to_json
    end

    def validate_country_code!(country_code)
      return if country_code.blank?

      IsoCountryCodes.find(country_code)
    rescue IsoCountryCodes::UnknownCodeError
      claim = SavedClaim::Form21p530a.new
      claim.errors.add '/burialInformation/recipientOrganization/address/country',
                       "'#{country_code}' is not a valid country code"
      raise Common::Exceptions::ValidationErrors, claim
    end

    def build_claim
      payload = request.raw_post
      transformed_payload = transform_country_codes(payload)
      SavedClaim::Form21p530a.new(form: transformed_payload)
    end

    def parse_and_transform_payload
      raw_payload = request.raw_post
      transformed_payload = transform_country_codes(raw_payload)
      JSON.parse(transformed_payload)
    end

    def generate_pdf(parsed_form)
      with_retries('Generate 21P-530A PDF') do
        PdfFill::Filler.fill_ancillary_form(parsed_form, SecureRandom.uuid, '21P-530A')
      end
    end

    def monitor
      @monitor ||= Form21p530a::Monitor.new
    end

    def handle_pdf_generation_error(error, parsed_form = nil)
      user_uuid = current_user&.uuid
      claim_guid = parsed_form&.dig('claimGuid')
      monitor.track_pdf_generation_failure(error, user_uuid:, claim_guid:)
      render json: {
        errors: [{
          title: 'PDF Generation Failed',
          detail: 'An error occurred while generating the PDF',
          status: '500'
        }]
      }, status: :internal_server_error
    end

    def auth_required?
      Flipper.enabled?(:aquia_bio_auth_required, current_user)
    end
  end
end
