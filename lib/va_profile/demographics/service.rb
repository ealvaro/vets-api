# frozen_string_literal: true

require 'common/client/concerns/monitoring'
require 'common/client/errors'
require 'va_profile/service'
require 'va_profile/stats'
require_relative 'configuration'
require_relative 'demographic_response'
require_relative 'preferred_name_response'
require_relative 'gender_identity_response'
require 'logging/helper/data_scrubber'
require 'identity/parsers/gc_ids_constants'

module VAProfile
  module Demographics
    class Service < VAProfile::Service
      OID = '2.16.840.1.113883.4.349'
      include Common::Client::Concerns::Monitoring

      STATSD_KEY_PREFIX = "#{VAProfile::Service::STATSD_KEY_PREFIX}.demographics".freeze
      configuration VAProfile::Demographics::Configuration

      # Returns a response object containing the user's preferred name, and gender-identity
      def get_demographics
        with_monitoring do
          unless DemographicsPolicy.new(@user).access_update?
            log_missing_icn
            return build_response(401, nil)
          end

          response = perform(:get, identity_path)
          build_response(response&.status, response&.body)
        end
      rescue Common::Client::Errors::ClientError => e
        if e.status == 404
          Rails.logger.error(scrub_pii(e.message), demographics_not_found_context)

          return build_response(404, nil)
        elsif e.status >= 400 && e.status < 500
          return build_response(e.status, nil)
        end

        handle_error(e)
      rescue => e
        handle_error(e)
      end

      # PUTs an updated preferred_name to the VAProfile API
      # @param preferred_name [VAProfile::Models::PreferredName] the preferred_name to update
      def save_preferred_name(preferred_name)
        post_or_put_data(:post, preferred_name, 'preferred-name', PreferredNameResponse)
      end

      # PUTs an updated gender_identity to the VAProfile API
      # @param gender_identity [VAProfile::Models::GenderIdentity] the gender_identity to update
      def save_gender_identity(gender_identity)
        post_or_put_data(:post, gender_identity, 'gender-identity', GenderIdentityResponse)
      end

      def post_or_put_data(method, model, path, response_class)
        with_monitoring do
          unless DemographicsPolicy.new(@user).access_update?
            log_missing_icn
            raise 'User does not have an ICN'
          end

          model.set_defaults(@user)
          response = perform(method, identity_path(path), model.in_json)

          return response_class.new(200, "#{model.model_name.element}": model) if response_successful?(response)

          response_class.from(response)
        end
      rescue => e
        handle_error(e)
      end

      def response_successful?(response)
        response&.status == 200 && response&.body == {}
      end

      def identity_path(dir = nil)
        path = "#{OID}/#{ERB::Util.url_encode(icn_with_aaid.to_s)}"
        dir ? "#{path}/#{dir}" : path
      end

      def build_response(status, body)
        DemographicResponse.from(
          status:,
          body:,
          id: @user.user_account_uuid,
          type: 'mvi_models_mvi_profiles',
          gender: @user.gender_mpi,
          birth_date: @user.birth_date_mpi
        )
      end

      private

      def icn_with_aaid
        return if @user&.icn.blank?

        "#{@user.icn}#{Identity::Parsers::GCIdsConstants::ICN_ASSIGNING_AUTHORITY_ID}"
      end

      def demographics_not_found_context
        { icn_present: @user&.icn.present?, va_profile: :demographics_not_found }
      end

      def log_missing_icn
        StatsD.increment('va_profile.demographics.missing_icn', tags: ['service:demographics'])
        Rails.logger.warn(
          event: 'va_profile.demographics.missing_icn',
          service: 'demographics',
          user_uuid: @user&.uuid
        )
      end

      def scrub_pii(message)
        Logging::Helper::DataScrubber.scrub(message)
      end
    end
  end
end
