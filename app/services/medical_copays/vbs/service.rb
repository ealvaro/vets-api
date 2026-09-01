# frozen_string_literal: true

module MedicalCopays
  module VBS
    ##
    # Service object for isolating dependencies in the {MedicalCopaysController}
    #
    # @!attribute request
    #   @return [MedicalCopays::Request]
    # @!attribute request_data
    #   @return [RequestData]
    # @!attribute response_data
    #   @return [ResponseData]
    class Service
      include RedisCaching
      class StatementNotFound < StandardError; end
      class ServiceError < StandardError; end

      attr_reader :request, :request_data, :user

      STATSD_KEY_PREFIX = 'api.mcp.vbs'
      STATSD_PRE_RETRIEVAL = "#{STATSD_KEY_PREFIX}.pdf.total".freeze
      STATSD_RETRIEVAL_SUCCESS = "#{STATSD_KEY_PREFIX}.pdf.success".freeze
      STATSD_RETRIEVAL_INVALID = "#{STATSD_KEY_PREFIX}.pdf.invalid_body".freeze
      STATSD_RETRIEVAL_FAILURE = "#{STATSD_KEY_PREFIX}.pdf.failure".freeze
      STATSD_CACHED_COPAYS_FIRED = "#{STATSD_KEY_PREFIX}.init_cached_copays.fired".freeze
      STATSD_CACHED_COPAYS_RETURNED = "#{STATSD_KEY_PREFIX}.init_cached_copays.cached_response_returned".freeze
      STATSD_CACHED_COPAYS_RESPONSE_CACHED = "#{STATSD_KEY_PREFIX}.init_cached_copays.response_cached".freeze
      STATSD_CACHED_COPAYS_FAILURE = "#{STATSD_KEY_PREFIX}.summary.failure".freeze
      STATSD_COPAYS_INVALID_REQUEST = "#{STATSD_KEY_PREFIX}.summary.invalid_request".freeze
      STATSD_COPAY_NOT_FOUND = "#{STATSD_KEY_PREFIX}.summary.not_found".freeze

      ##
      # Builds a Service instance
      #
      # @param opts [Hash]
      # @return [Service] an instance of this class
      #
      def self.build(opts = {})
        new(opts)
      end

      def initialize(opts)
        @request = MedicalCopays::Request.build
        @user = opts[:user]
        @request_data = RequestData.build(user:) unless user.nil?
      end

      ##
      # Gets the user's medical copays by edipi and vista account numbers
      #
      # @return [Hash]
      #
      def get_copays
        unless request_data.valid?
          track_invalid_request
          raise InvalidVBSRequestError, request_data.errors
        end

        info_if_logging("MedicalCopays::VBS::Service#get_copays request data: #{@user.uuid}")

        response = get_cached_copay_response

        # enable zero balance debt feature if flip is on
        if Flipper.enabled?(:medical_copays_zero_debt)
          zero_balance_statements = MedicalCopays::ZeroBalanceStatements.build(
            statements: response.body,
            facility_hash: user.vha_facility_hash
          )
          response.body.concat(zero_balance_statements.list)
        end

        result = ResponseData.build(response:).handle
        count = result[:data].is_a?(Array) ? result[:data].size : 0
        info_if_logging("MedicalCopays::VBS::Service#get_copays returned, status: #{result[:status]}, count: #{count}")
        result
      end

      def get_cached_copay_response
        StatsD.increment(STATSD_CACHED_COPAYS_FIRED)

        cached_response = get_user_cached_response

        if cached_response
          StatsD.increment(STATSD_CACHED_COPAYS_RETURNED)
          info_if_logging('MedicalCopays::VBS::Service#get_cached_copay_response cache hit')

          return Faraday::Response.new(status: 200, body: cached_response)
        end

        info_if_logging('MedicalCopays::VBS::Service#get_cached_copay_response cache miss, requesting from backend')

        response = request.post("#{settings.base_path}/GetStatementsByEDIPIAndVistaAccountNumber", request_data.to_hash)

        response_body = response.body

        if cache_response?(response_body)
          Rails.cache.write("vbs_copays_data_#{user.uuid}", response_body, expires_in: self.class.time_until_5am_utc)
          StatsD.increment(STATSD_CACHED_COPAYS_RESPONSE_CACHED,
                           tags: ["type:#{response_body.empty? ? 'empty' : 'full'}"])
        end

        Faraday::Response.new(status: 200, body: response_body)
      rescue => e
        track_cached_copay_error(e)
        raise ServiceError
      end

      ##
      # Get's the users' medical copay by statement id from list
      #
      # @param id [UUID] - uuid of the statement
      # @return [Hash] - JSON data of statement and status
      #
      def get_copay_by_id(id)
        info_if_logging("MedicalCopays::VBS::Service#get_copay_by_id requested, id: #{id}")

        all_statements = get_copays

        # Return hash with error information if bad response
        return all_statements unless all_statements[:status] == 200

        statement = all_statements[:data].find { |copay| copay['id'] == id }

        if statement.nil?
          track_copay_not_found(id)
          raise StatementNotFound
        end

        info_if_logging("MedicalCopays::VBS::Service#get_copay_by_id statement found, id: #{id}")
        { data: statement, status: 200 }
      end

      ##
      # Gets the PDF medical copay statment by statment_id
      #
      # @return [Hash]
      #
      def get_pdf_statement_by_id(statement_id)
        track_pdf_request(statement_id)

        response = request.get("#{settings.base_path}/GetPDFStatementById/#{statement_id}")
        decoded = Base64.decode64(response.body['statement'])

        track_pdf_result(decoded, statement_id)

        decoded
      rescue => e
        track_pdf_error(e, statement_id)
        raise e
      end

      def get_user_cached_response
        cache_key = "vbs_copays_data_#{user.uuid}"
        Rails.cache.read(cache_key)
      end

      def send_statement_notifications(_statements_json_byte)
        # Commenting for now since we are causingissues in production
        # when the child job runs: "NewStatementNotificationJob"
        # CopayNotifications::ParseNewStatementsJob.perform_async(statements_json_byte)
        true
      end

      def settings
        Settings.mcp.vbs_v2
      end

      private

      def info_if_logging(message)
        Rails.logger.info(message) if Flipper.enabled?(:debts_copay_logging)
      end

      # Empty responses were already cached before the flag existed. The flag adds non-empty ones.
      def cache_response?(response)
        return false unless response.is_a?(Array)
        return true if response.empty?

        Flipper.enabled?(:medical_copays_cache_vbs_full_response, user)
      end

      def track_invalid_request
        StatsD.increment(STATSD_COPAYS_INVALID_REQUEST)
        Rails.logger.error('MedicalCopays::VBS::Service#get_copays invalid request data')
      end

      def track_copay_not_found(id)
        StatsD.increment(STATSD_COPAY_NOT_FOUND)
        Rails.logger.error("MedicalCopays::VBS::Service#get_copay_by_id statement not found, id: #{id}")
      end

      def track_cached_copay_error(error)
        StatsD.increment(STATSD_CACHED_COPAYS_FAILURE)
        Rails.logger.error("MedicalCopays::VBS::Service#get_cached_copay_response error: #{safe_error_details(error)}")
      end

      def track_pdf_request(statement_id)
        StatsD.increment(STATSD_PRE_RETRIEVAL)
        info_if_logging("MedicalCopays::VBS::Service#get_pdf_statement_by_id requested, statement_id: #{statement_id}")
      end

      def track_pdf_result(decoded, statement_id)
        # bytes distinguishes a real PDF (KB-MB) from a 200 with an empty or
        # non-PDF body (0 or a few hundred bytes); the %PDF- header confirms it is a PDF
        if decoded.start_with?('%PDF-')
          StatsD.increment(STATSD_RETRIEVAL_SUCCESS)
          info_if_logging(
            'MedicalCopays::VBS::Service#get_pdf_statement_by_id success, ' \
            "statement_id: #{statement_id}, bytes: #{decoded.bytesize}"
          )
        else
          StatsD.increment(STATSD_RETRIEVAL_INVALID)
          Rails.logger.error(
            'MedicalCopays::VBS::Service#get_pdf_statement_by_id invalid PDF body on 200 response, ' \
            "statement_id: #{statement_id}, bytes: #{decoded.bytesize}"
          )
        end
      end

      def track_pdf_error(error, statement_id)
        StatsD.increment(STATSD_RETRIEVAL_FAILURE)
        Rails.logger.error(
          "MedicalCopays::VBS::Service#get_pdf_statement_by_id error: #{safe_error_details(error)}, " \
          "statement_id: #{statement_id}"
        )
      end

      def safe_error_details(error)
        if error.is_a?(Common::Exceptions::BackendServiceException)
          "#{error.class} - status: #{error.original_status}, key: #{error.key}"
        else
          error.class.to_s
        end
      end
    end
  end
end
