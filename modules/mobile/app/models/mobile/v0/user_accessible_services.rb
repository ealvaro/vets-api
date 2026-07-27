# frozen_string_literal: true

require 'mhv/oh_facilities_helper/service'

module Mobile
  module V0
    class UserAccessibleServices
      def initialize(user, request = nil)
        @user = user
        @request = request
      end

      def authorized
        service_auth_map.select { |_, v| v == true }.keys.sort
      end

      # forming this requires evaluating all auth rules. Currently, they are only used together. if we ever need
      # available services without authorized services we should decouple them.
      def available
        service_auth_map.keys.sort
      end

      def service_auth_map # rubocop:disable Metrics/MethodLength
        @service_auth_map ||= {
          allergiesOracleHealthEnabled: versioned_flagged_access?(%i[mhv_accelerated_delivery_uhd_enabled],
                                                                  :allergies_oracle_health),
          appeals: access?(appeals: :access?),
          appointments: access?(vaos: :access?) && @user.icn.present? && access?(vaos: :facilities_access?) &&
                        !emergency_brake_active?('appointments'),
          benefitsPushNotification: @user.icn.present? && Flipper.enabled?(
            :event_bus_gateway_letter_ready_push_notifications, icn_actor
          ),
          claims: access?(lighthouse: :access?),
          cstLettersContentUpdates: versioned_flagged_access?(
            %i[cst_letters_content_updates], Mobile::V0::Letter::CONTENT_UPDATES_APP_VERSION
          ),
          cstLettersDescriptionContentFormat: versioned_flagged_access?(
            %i[cst_letters_description_content_format], Mobile::V0::Letter::DESCRIPTION_CONTENT_FORMAT_APP_VERSION
          ),
          cstMultiClaimProvider: @user.icn.present? && Flipper.enabled?(
            :cst_multi_claim_provider_mobile, icn_actor
          ),
          decisionLetters: access?(bgs: :access?),
          directDepositBenefits: access?(lighthouse: :mobile_access?),
          directDepositBenefitsUpdate: access?(lighthouse: :mobile_access?),
          disabilityRating: access?(lighthouse: :access?),
          genderIdentity: access?(demographics: :access_update?) && access?(mpi: :queryable?),
          labsAndTestsEnabled: versioned_flagged_access?(%i[mhv_accelerated_delivery_uhd_enabled],
                                                         :labs_oracle_health),
          lettersAndDocuments: access?(lighthouse: :access?),
          militaryServiceHistory: access?(vet360: :military_access?),
          medicationsOracleHealthEnabled: versioned_flagged_access?(%i[mhv_accelerated_delivery_uhd_enabled],
                                                                    :medications_oracle_health),
          paymentHistory: access?(bgs: :access?),
          preferredName: access?(demographics: :access_update?) && access?(mpi: :queryable?),
          prescriptions: access?(mhv_prescriptions: :access?) && !emergency_brake_active?('rx'),
          scheduleAppointments: access?(schedule_appointment: :access?),
          secureMessaging: access?(mhv_messaging: :mobile_access?) && !emergency_brake_active?('sm'),
          secureMessagingOracleHealthEnabled: Flipper.enabled?(:mhv_secure_messaging_cerner_pilot, @user),
          userProfileUpdate: access?(va_profile: :access_to_v2?)
        }
      end # rubocop:enable Metrics/MethodLength

      private

      # Returns true if the provided app version meets or exceeds the minimum required version.
      # A Symbol is looked up in settings (vahb.version_requirement); a String is used as a literal version.
      def min_version?(feature)
        app_version = @request&.headers&.[]('App-Version')
        required_version = feature.is_a?(Symbol) ? Settings.vahb.version_requirement[feature] : feature

        # Treat missing versions as an old version
        return false if app_version.nil? || required_version.nil?

        # Treat malformed versions as an old version
        begin
          version = Gem::Version.new(app_version)
          version >= Gem::Version.new(required_version)
        rescue ArgumentError
          false
        end
      end

      # Returns true if the feature flag is enabled for the user and the app version meets the minimum requirement
      def versioned_flagged_access?(flag_names, feature)
        flag_names.all? { |flag_name| Flipper.enabled?(flag_name, @user) } && min_version?(feature)
      end

      def flagged_access?(flag_name, flag_on_policy, flag_off_policy)
        if Flipper.enabled?(flag_name, @user)
          access?(flag_on_policy)
        else
          access?(flag_off_policy)
        end
      end

      def icn_actor
        Flipper::Actor.new(@user.icn)
      end

      def access?(policies)
        policies.all? do |policy_name, policy_rule|
          if policy_rule.is_a? Array
            policy_rule.all? { |rule| access?({ policy_name => rule }) }
          else
            @user.authorize(policy_name, policy_rule)
          end
        end
      end

      def emergency_brake_active?(tool)
        oh_migration_service.emergency_brake_active?(tool)
      end

      def oh_migration_service
        @oh_migration_service ||= MHV::OhFacilitiesHelper::Service.new(@user)
      end
    end
  end
end
