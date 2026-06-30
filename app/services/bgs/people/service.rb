# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module BGS
  module People
    class Service
      class VAFileNumberNotFound < StandardError; end

      attr_reader :ssn,
                  :participant_id,
                  :common_name,
                  :email,
                  :icn,
                  :user_account

      def initialize(user)
        @ssn = user.ssn
        @participant_id = user.participant_id
        @common_name = user.common_name
        @email = user.email
        @icn = user.icn
        @user_account = user.user_account
      end

      def find_person_by_participant_id
        raw_response = service.people.find_person_by_ptcpnt_id(participant_id, ssn)
        if raw_response.blank?
          exception = VAFileNumberNotFound.new
          Rails.logger.error(scrub_pii(exception.message), { user_account:, team: Constants::SENTRY_REPORTING_TEAM })

        end
        BGS::People::Response.new(raw_response, status: :ok)
      rescue => e
        Rails.logger.error(scrub_pii(e.message), { user_account:, team: Constants::SENTRY_REPORTING_TEAM })

        BGS::People::Response.new(nil, status: :error)
      end

      private

      def service
        @service ||= BGS::Services.new(external_uid: icn, external_key:)
      end

      def external_key
        @external_key ||= begin
          key = common_name.presence || email
          key&.first(Constants::EXTERNAL_KEY_MAX_LENGTH)
        end
      end

      def scrub_pii(message)
        Logging::Helper::DataScrubber.scrub(message)
      end
    end
  end
end
