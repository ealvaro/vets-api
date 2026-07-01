# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class EpsProvider < BaseProvider
        attr_accessor :network_id, :npi, :specialties,
                      :digital_booking_features, :appointment_types

        alias provider_service_id id
        alias provider_service_id= id=

        def initialize(attrs = {})
          super
          self.provider_type = 'eps'
        end

        ##
        # Whether this EPS provider can be scheduled online.
        #
        # Mirrors +Eps::ProviderService#filter_self_schedulable+: a provider is online-schedulable only
        # when Wellhive reports both digital capability and direct booking enabled. Phone-only providers
        # (surfaced behind the post-MVP flag) return +false+ and are scheduled by calling +phone+.
        #
        # @return [Boolean]
        def online_scheduling?
          digital_booking_features&.dig(:is_digital) == true &&
            digital_booking_features&.dig(:direct_booking, :is_enabled) == true
        end

        ##
        # First self-schedulable EPS appointment type id
        #
        # @return [String]
        # @raise [Common::Exceptions::BackendServiceException] when types are missing or none self-schedulable
        #
        def first_self_schedulable_appointment_type_id!
          if appointment_types.blank?
            raise Common::Exceptions::BackendServiceException.new(
              'PROVIDER_APPOINTMENT_TYPES_MISSING',
              {},
              502,
              'Provider appointment types data is not available'
            )
          end

          self_schedulable = appointment_types.select { |apt| apt[:is_self_schedulable] == true }
          if self_schedulable.blank?
            raise Common::Exceptions::BackendServiceException.new(
              'PROVIDER_SELF_SCHEDULABLE_TYPES_MISSING',
              {},
              502,
              'No self-schedulable appointment types available for this provider'
            )
          end

          self_schedulable.first[:id]
        end

        # Builds an EpsProvider from an EPS provider service response (Hash or OpenStruct)
        def self.from_eps_provider_service(provider)
          provider = provider.to_h if provider.is_a?(OpenStruct)
          location = provider[:location] || {}
          practice_name = location[:name].presence || provider[:name]

          new(
            id: provider[:id],
            name: provider[:name],
            facility_name: practice_name,
            address: parse_eps_address(location[:address]),
            phone: extract_phone(provider),
            latitude: location[:latitude],
            longitude: location[:longitude],
            npi: extract_npi(provider),
            specialties: provider[:specialties] || [],
            network_id: provider[:network_ids]&.first,
            digital_booking_features: provider[:features],
            appointment_types: provider[:appointment_types] || []
          )
        end

        def self.parse_eps_address(address_string)
          return nil if address_string.blank?

          # EPS addresses come as a single comma-separated string
          # e.g. "1105 Palmetto Ave, Melbourne, FL, 32901, US"
          parts = address_string.split(',').map(&:strip)
          {
            street1: parts[0],
            city: parts[1],
            state: parts[2],
            zip: parts[3]
          }
        end

        def self.extract_phone(provider)
          contacts = provider[:contact_details]
          return nil if contacts.blank?

          phone_contact = contacts.find { |c| c[:system] == 'phone' && c[:use] == 'for_patient' }
          phone_contact ||= contacts.find { |c| c[:system] == 'phone' }
          phone_contact&.dig(:value)
        end

        def self.extract_npi(provider)
          providers = provider[:individual_providers]
          return nil if providers.blank?

          providers.first&.dig(:npi)
        end
      end
    end
  end
end
