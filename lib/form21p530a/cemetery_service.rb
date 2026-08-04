# frozen_string_literal: true

module Form21p530a
  # Standalone BGS SOAP client for the findCemeteries endpoint.
  # Does not depend on ClaimsApi — can survive its removal.
  class CemeteryService
    ENDPOINT = 'StandardDataWebServiceBean/StandardDataWebService'
    ACTION = 'findCemeteries'
    KEY = 'Cemetery'

    def initialize
      bgs = Settings.bgs
      @url = bgs.url
      @timeout = bgs.timeout || 120
      @env = bgs.env
      @client_ip = resolve_client_ip
      @client_username = bgs.client_username
      @client_station_id = bgs.client_station_id
      @application = bgs.application
      @external_uid = 'find_cemeteries_service_uid'
      @external_key = 'find_cemeteries_service_key'
      @ssl_verify_mode = bgs.ssl_verify_mode == 'none' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    end

    def find_cemeteries
      response = connection.post(
        "#{@url}/#{ENDPOINT}",
        soap_body,
        soap_headers
      )

      raise ::Common::Exceptions::BadGateway if response.status != 200

      parse_response(response.body)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed
      raise ::Common::Exceptions::BadGateway
    end

    private

    def connection
      @connection ||= Faraday.new(ssl: { verify_mode: @ssl_verify_mode }) do |f|
        f.use :breakers
        f.adapter Faraday.default_adapter
        f.options.timeout = @timeout
      end
    end

    def soap_body
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <env:Envelope
          xmlns:xsd="http://www.w3.org/2001/XMLSchema"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xmlns:tns="#{namespace}"
          xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
        >
          #{soap_header}
          <env:Body>
            <tns:#{ACTION}/>
          </env:Body>
        </env:Envelope>
      XML
    end

    def soap_header
      <<~XML
        <env:Header>
          <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <wsse:UsernameToken>
              <wsse:Username>#{@client_username}</wsse:Username>
            </wsse:UsernameToken>
            <vaws:VaServiceHeaders xmlns:vaws="http://vbawebservices.vba.va.gov/vawss">
              <vaws:CLIENT_MACHINE>#{@client_ip}</vaws:CLIENT_MACHINE>
              <vaws:STN_ID>#{@client_station_id}</vaws:STN_ID>
              <vaws:applicationName>#{@application}</vaws:applicationName>
              <vaws:ExternalUid>#{@external_uid}</vaws:ExternalUid>
              <vaws:ExternalKey>#{@external_key}</vaws:ExternalKey>
            </vaws:VaServiceHeaders>
          </wsse:Security>
        </env:Header>
      XML
    end

    def soap_headers
      {
        'Content-Type' => 'text/xml;charset=UTF-8',
        'Host' => "#{@env}.vba.va.gov",
        'Soapaction' => "\"#{ACTION}\""
      }
    end

    def namespace
      @namespace ||= fetch_namespace
    end

    def fetch_namespace
      wsdl = connection.get("#{@url}/#{ENDPOINT}?WSDL")
      Hash.from_xml(wsdl.body).dig('definitions', 'targetNamespace').to_s
    end

    def parse_response(body)
      result = Hash.from_xml(body).dig('Envelope', 'Body', "#{ACTION}Response", KEY)
      transform_keys(Array.wrap(result))
    end

    def transform_keys(array)
      array.map { |hash| hash.deep_transform_keys { |k| k.underscore.to_sym } }
    end

    def resolve_client_ip
      if Rails.env.test?
        '127.0.0.1'
      else
        Socket.ip_address_list.detect(&:ipv4_private?)&.ip_address || '127.0.0.1'
      end
    end
  end
end
