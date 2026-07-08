# frozen_string_literal: true

require 'lgy/configuration'
require 'common/client/base'

module LGY
  class Service < Common::Client::Base
    include Common::Client::Concerns::Monitoring
    configuration LGY::Configuration
    STATSD_KEY_PREFIX = 'api.lgy'

    def initialize(edipi: nil, icn: nil)
      @edipi = edipi
      @icn = icn
    end

    # rubocop:disable Metrics/MethodLength
    def coe_status
      if get_determination.body['status'] == 'ELIGIBLE' && get_application.status == 404
        increment_coe_status_counter(:eligible)
        { status: 'ELIGIBLE', reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'UNABLE_TO_DETERMINE_AUTOMATICALLY'
        increment_coe_status_counter(:unable_to_determine_automatically)
        { status: 'UNABLE_TO_DETERMINE_AUTOMATICALLY', reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'ELIGIBLE' && get_application.status == 200
        increment_coe_status_counter(:available)
        { status: 'AVAILABLE', application_create_date: get_application.body['create_date'],
          reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'NOT_ELIGIBLE'
        increment_coe_status_counter(:denied)
        { status: 'DENIED', application_create_date: get_determination.body['determination_date'],
          reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'PENDING' && get_application.status == 404
        # Kelli said we'll never having a pending status w/o an application, but LGY sqa data is getting hand crafted
        increment_coe_status_counter(:pending_no_application)
        { status: 'PENDING', reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'PENDING' && get_application.body['status'] == 'SUBMITTED'
        # SUBMITTED & RECEIVED ARE COMBINED ON LGY SIDE
        increment_coe_status_counter(:pending_submitted)
        { status: 'PENDING', application_create_date: get_application.body['create_date'],
          reference_number: get_determination.body['reference_number'] }
      elsif get_determination.body['status'] == 'PENDING' && get_application.body['status'] == 'RETURNED'
        increment_coe_status_counter(:pending_returned)
        { status: 'PENDING_UPLOAD', application_create_date: get_application.body['create_date'],
          reference_number: get_determination.body['reference_number'] }
      else
        increment_coe_status_counter(:unexpected_status)
        Rails.logger.error(
          'Unexpected COE statuses!',
          {
            determination_status: get_determination.body['status'],
            application_status: get_application.body['status'],
            get_application_status: get_application.status
          }
        )
        nil
      end
    end
    # rubocop:enable Metrics/MethodLength

    def get_determination
      @get_determination ||= with_monitoring do
        perform(
          :get,
          "#{end_point}/determination",
          { 'edipi' => @edipi, 'icn' => @icn },
          request_headers
        )
      end
    end

    def get_application
      @get_application ||= with_monitoring do
        perform(
          :get,
          "#{end_point}/application",
          { 'edipi' => @edipi, 'icn' => @icn },
          request_headers
        )
      end
    rescue Common::Client::Errors::ClientError => e
      # if the Veteran is automatically approved, LGY will return a 404 (no application exists)
      return e if e.status == 404

      raise e
    end

    def put_application(payload:)
      with_monitoring do
        response = perform(
          :put,
          "#{end_point}/application?edipi=#{@edipi}&icn=#{@icn}",
          payload.to_json,
          request_headers
        )
        response.body
      end
    rescue Common::Client::Errors::ClientError => e
      Rails.logger.error(
        "COE application submission failed with http status: #{e.status}",
        { message: e.message, status: e.status, body: e.body }
      )
      raise e
    end

    def get_coe_file
      with_monitoring do
        perform(
          :get,
          "#{end_point}/documents/coe/file",
          { 'edipi' => @edipi, 'icn' => @icn },
          request_headers.merge(pdf_headers)
        )
      end
    rescue Common::Client::Errors::ClientError => e
      # a 404 is expected if no COE is available
      return e if e.status == 404

      raise e
    end

    def post_document(payload:)
      with_monitoring do
        perform(
          :post,
          "#{end_point}/document?edipi=#{@edipi}&icn=#{@icn}",
          payload.to_json,
          request_headers
        )
      end
    end

    def get_coe_documents
      with_monitoring do
        perform(
          :get,
          "#{end_point}/documents",
          { 'edipi' => @edipi, 'icn' => @icn },
          request_headers
        )
      end
    end

    # It is necessary to fetch a list of the user's documents and check
    # whether the requested document is within that list, to ensure that a
    # vet cannot access documents belonging to other vets. LGY does not have
    # a similar validation on their end.
    def get_document(id)
      with_monitoring do
        document_ids = get_coe_documents.body.map { |doc| doc['id'].to_s }
        if document_ids.include?(id)
          perform(
            :get,
            "#{end_point}/document/#{id}/file",
            { 'edipi' => @edipi, 'icn' => @icn },
            request_headers.merge(pdf_headers)
          )
        else
          raise Common::Exceptions::RecordNotFound, id
        end
      end
    end

    def post_grant_application(payload:)
      with_monitoring do
        perform(
          :post,
          "#{grant_manager_end_point}/application/createGrantApplication",
          payload.to_json,
          sahsha_request_headers
        )
      end
    end

    def request_headers
      {
        Authorization: "api-key { \"appId\":\"#{config.app_id}\", \"apiKey\": \"#{config.api_key}\"}"
      }
    end

    def sahsha_request_headers
      {
        Authorization: "api-key { \"appId\":\"#{config.sahsha_app_id}\", \"apiKey\": \"#{config.sahsha_api_key}\"}"
      }
    end

    def pdf_headers
      {
        'Accept' => 'application/octet-stream', 'Content-Type' => 'application/octet-stream'
      }
    end

    private

    def increment_coe_status_counter(suffix)
      StatsD.increment(
        "#{STATSD_KEY_PREFIX}.coe_status_response",
        tags: ["status:#{suffix}"]
      )
    end

    def end_point
      "#{Settings.lgy.base_url}/eligibility-manager/api/eligibility"
    end

    def grant_manager_end_point
      "#{Settings.lgy_sahsha.base_url}/grant-manager/api/grants"
    end
  end
end
