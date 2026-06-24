# frozen_string_literal: true

require 'cgi'
require 'forwardable'

module SharePoint
  class AuthenticationError < StandardError; end

  class Service
    extend Forwardable

    attr_reader :sharepoint_feature

    def_delegators :settings, :sharepoint_graph_url, :client_id, :client_secret, :tenant_id, :scope,
                   :site_id, :drive_id, :authentication_url

    def initialize(sharepoint_feature:)
      @sharepoint_feature = sharepoint_feature
      @settings = resolve_settings(sharepoint_feature)
    end

    # Uploads CSV data to the specified SharePoint file_path
    #
    # @param csv_data [String] CSV content to upload
    # @param sharepoint_path [String] Folder path within the drive/Documents (root) folder
    # @param file_name [String] Filename for the uploaded CSV
    #
    # @return [Faraday::Response]
    def upload_csv(csv_data, sharepoint_path, file_name)
      encoded_path = encode_sharepoint_path(sharepoint_path)
      encoded_file_name = encode_sharepoint_path_segment(file_name)
      file_upload_path = "/v1.0/sites/#{site_id}/drives/#{drive_id}/root:/#{encoded_path}/#{encoded_file_name}:/content"

      csv_headers = {
        'Content-Type' => 'text/csv',
        'Content-Length' => csv_data.bytesize.to_s
      }

      response = upload_file(csv_data, file_upload_path, addl_headers: csv_headers)

      if response.success?
        StatsD.increment("#{statsd_key_prefix}.upload_csv.success")
      else
        StatsD.increment("#{statsd_key_prefix}.upload_csv.fail")
      end

      response
    rescue => e
      StatsD.increment("#{statsd_key_prefix}.upload_csv.fail")
      Rails.logger.error('SharePoint CSV upload failed', { message: e.message })
      raise
    end

    private

    attr_reader :settings

    def statsd_key_prefix
      "api.sharepoint.#{sharepoint_feature}"
    end

    def access_token
      @access_token ||= set_sharepoint_access_token
    end

    def set_sharepoint_access_token
      auth_response = auth_connection.post("/#{tenant_id}/oauth2/v2.0/token", {
                                             grant_type: 'client_credentials',
                                             client_id:,
                                             client_secret:,
                                             scope:
                                           })

      token = auth_response.body['access_token']
      if token.blank?
        raise AuthenticationError,
              "SharePoint authentication failed (status: #{auth_response.status}): #{auth_response.body['error']}"
      end

      token
    end

    def upload_file(data, file_upload_path, addl_headers: {})
      sharepoint_file_connection.put(file_upload_path) do |req|
        req.headers.merge!(addl_headers)
        req.body = data
      end
    end

    def resolve_settings(sharepoint_feature)
      settings = Settings.sharepoint[sharepoint_feature]
      if settings.blank?
        raise ArgumentError, "No SharePoint settings found for sharepoint_feature: #{sharepoint_feature}"
      end

      settings
    end

    def service_name
      "SharePoint::#{sharepoint_feature.to_s.camelize}"
    end

    def auth_connection
      Faraday.new(url: authentication_url) do |conn|
        conn.use(:breakers, service_name: "#{service_name}_auth")
        conn.request :url_encoded
        conn.response :json
        conn.options.open_timeout = 10
        conn.options.timeout = 30
        conn.response :betamocks if mock_enabled?
        conn.adapter Faraday.default_adapter
      end
    end

    def sharepoint_file_connection
      Faraday.new(url: sharepoint_graph_url, headers: default_headers) do |conn|
        conn.use(:breakers, service_name:)
        conn.options.open_timeout = 10
        conn.options.timeout = 30
        conn.response :betamocks if mock_enabled?
        conn.adapter Faraday.default_adapter
      end
    end

    def default_headers
      {
        'Authorization' => "Bearer #{access_token}",
        'Accept' => 'application/json'
      }
    end

    def mock_enabled?
      ActiveModel::Type::Boolean.new.cast(settings.mock)
    end

    def encode_sharepoint_path(path)
      path.to_s.split('/').compact_blank.map { |segment| encode_sharepoint_path_segment(segment) }.join('/')
    end

    def encode_sharepoint_path_segment(segment)
      CGI.escape(segment.to_s).tr('+', '%20')
    end
  end
end
