# frozen_string_literal: true

require 'claims_evidence_api/service/search'
require 'claims_evidence_api/service/files'
require 'lighthouse/letters_generator/content'

module V0
  class TsaLetterController < ApplicationController
    service_tag 'tsa_letter'
    before_action { authorize :tsa_letter, :access? }

    ERROR_MAP = {
      400 => Common::Exceptions::BadRequest,
      401 => Common::Exceptions::Unauthorized,
      403 => Common::Exceptions::Forbidden,
      500 => Common::Exceptions::ExternalServerInternalServerError,
      501 => Common::Exceptions::NotImplemented
    }.freeze
    NONBLOCKING_ERRORS = [Common::Exceptions::BadRequest, Common::Exceptions::Forbidden].freeze

    def show
      files_metadata = request_data_with_error_handling('TSA Letter Show Error') do
        fetch_letter_metadata
      end
      serialized = most_recent_letter(files_metadata)
      render(json: serialized)
    rescue *NONBLOCKING_ERRORS
      # 400 is a bad request, but it's unclear why this happens
      # 403 indicates that the API doesn't know the user.
      render(json: { data: nil })
    end

    def download
      files_metadata = request_data_with_error_handling('TSA Letter Metadata Error') do
        fetch_letter_metadata
      end

      user_owns_file = files_metadata.any? do |file|
        params[:id] == file['uuid'] && params[:version_id] == file['currentVersionUuid']
      end
      unless user_owns_file
        raise Common::Exceptions::RecordNotFound.new(
          nil, detail: "Requested TSA letter file id #{params[:id]}, version id #{params[:version_id]} was not found."
        )
      end

      download_service = ClaimsEvidenceApi::Service::Files.new
      letter_response = request_data_with_error_handling('TSA Letter Download Error') do
        download_service.download(params[:id], params[:version_id])
      end
      send_data(
        letter_response.body,
        type: 'application/pdf',
        filename: 'VETS Safe Travel Outreach Letter.pdf'
      )
    end

    private

    def fetch_letter_metadata
      search_service = ClaimsEvidenceApi::Service::Search.new
      filters = { subject: ['VETS Safe Travel Outreach Letter'] }
      folder_identifier = "VETERAN:ICN:#{current_user.icn}"
      search_service.folder_identifier = folder_identifier
      response = search_service.find(filters:)
      response.body['files'] || []
    end

    def most_recent_letter(files)
      return { data: nil } if files.blank?

      latest = files.max do |a, b|
        a_time = DateTime.parse(a.dig('currentVersion', 'providerData', 'modifiedDateTime'))
        b_time = DateTime.parse(b.dig('currentVersion', 'providerData', 'modifiedDateTime'))
        a_time <=> b_time
      end

      attributes = build_letter_attributes(latest)
      tsa_letter_metadata = OpenStruct.new(attributes)
      TsaLetterSerializer.new(tsa_letter_metadata)
    rescue Date::Error
      datetimes = files.map { |file| file.dig('currentVersion', 'providerData', 'modifiedDateTime') }
      raise Common::Exceptions::UnprocessableEntity,
            detail: "Invalid datetime format found in TSA letters data: #{datetimes.join(', ')}",
            source: self.class.name
    end

    def build_letter_attributes(latest)
      attributes = {
        document_id: latest['uuid'],
        document_version: latest['currentVersionUuid'],
        modified_datetime: latest.dig('currentVersion', 'providerData', 'modifiedDateTime')
      }

      return attributes unless Flipper.enabled?(:cst_letters_content_updates, current_user)

      attributes.merge(
        name: Lighthouse::LettersGenerator::Content::LETTER_NAME_OVERRIDES['tsa'],
        description: Lighthouse::LettersGenerator::Content::LETTER_DESCRIPTIONS['tsa']
      )
    end

    def request_data_with_error_handling(description, &data_request)
      data_request.call
    rescue Common::Client::Errors::ClientError => e
      status = e.respond_to?(:status) && e.status
      case status
      when *ERROR_MAP.keys
        Rails.logger.info(description,
                          error_status: status,
                          user_account_id: current_user.user_account_uuid)
        error_class = ERROR_MAP[status]
        raise error_class
      else
        raise e
      end
    end
  end
end
