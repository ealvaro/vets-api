# frozen_string_literal: true

module DebtManagementCenter
  module Sharepoint
    module Graph
      class Request
        include Common::Client::Concerns::Monitoring

        SERVICE_NAME = 'sharepoint_graph'
        STATSD_KEY_PREFIX = 'api.vha.financial_status_report.sharepoint.graph.request'
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 30

        attr_reader :settings

        def initialize
          @settings = Settings.vha.sharepoint_graph
        end

        def upload(form_contents:, form_submission:, station_id:)
          pdf_path = build_pdf(
            form_contents:,
            form_submission:,
            station_id:
          )

          response = with_monitoring do
            upload_connection.put(upload_path(form_submission)) do |req|
              req.headers['Content-Type'] = 'application/pdf'
              req.body = File.binread(pdf_path)
            end
          end

          StatsD.increment("#{STATSD_KEY_PREFIX}.success")

          response
        rescue => e
          StatsD.increment("#{STATSD_KEY_PREFIX}.failure")
          log_upload_failure(form_submission, e)

          raise
        ensure
          File.delete(pdf_path) if pdf_path && File.exist?(pdf_path)
        end

        private

        def log_upload_failure(form_submission, error)
          Rails.logger.error('SharePoint Graph upload failed',
                             submission_id: form_submission.id,
                             message: error.message)
        end

        def build_pdf(form_contents:, form_submission:, station_id:)
          PdfFill::Filler.fill_ancillary_form(
            form_contents,
            "#{form_submission.id}-#{station_id}",
            '5655'
          )
        end

        def access_token
          @access_token ||= begin
            response = authentication_connection.post(
              settings.authentication.tenant_url
            ) do |req|
              req.body = {
                client_id: settings.authentication.client_id,
                client_secret: settings.authentication.client_secret,
                scope: 'https://graph.microsoft.com/.default',
                grant_type: 'client_credentials'
              }
            end

            response.body.fetch('access_token')
          end
        end

        def upload_path(form_submission)
          file_name = "#{Time.current.utc.strftime('%Y%m%dT%H%M%S')}_#{form_submission.id}.pdf"

          "#{settings.upload.path.chomp('/')}/#{file_name}:/content"
        end

        def authentication_connection
          Faraday.new(url: settings.authentication.base_url) do |conn|
            conn.request :url_encoded
            conn.options.open_timeout = OPEN_TIMEOUT
            conn.options.timeout = READ_TIMEOUT

            conn.use(:breakers, service_name: SERVICE_NAME)
            conn.use Faraday::Response::RaiseError

            conn.response :raise_custom_error,
                          error_prefix: SERVICE_NAME

            conn.response :json
            conn.response :betamocks if mock_enabled?

            conn.adapter Faraday.default_adapter
          end
        end

        def upload_connection
          Faraday.new(
            url: settings.upload.base_url,
            headers: {
              'Authorization' => "Bearer #{access_token}",
              'Accept' => 'application/json'
            }
          ) do |conn|
            conn.use(:breakers, service_name: SERVICE_NAME)
            conn.use Faraday::Response::RaiseError
            conn.options.open_timeout = OPEN_TIMEOUT
            conn.options.timeout = READ_TIMEOUT

            conn.response :raise_custom_error,
                          error_prefix: SERVICE_NAME

            conn.response :json
            conn.response :betamocks if mock_enabled?

            conn.adapter Faraday.default_adapter
          end
        end

        def mock_enabled?
          settings.mock || false
        end
      end
    end
  end
end
