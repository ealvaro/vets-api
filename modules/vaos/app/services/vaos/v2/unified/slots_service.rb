# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      # Fetches appointment availability (slots) for unified scheduling: VA clinic providers via
      # VAOS SystemsService, community care via EPS ProviderService. VA providers must include
      # +location_id+ and +id+ (clinic IEN; see VAProvider).
      class SlotsService
        STATSD_KEY_PREFIX = 'api.vaos.unified_slots'

        def initialize(user)
          @user = user
        end

        ##
        # @param provider [BaseProvider] VAProvider or EpsProvider
        # @param start_dt [String] ISO8601 start of search window (VA and EPS)
        # @param end_dt [String] ISO8601 end of search window (VA and EPS)
        # @param clinical_service [String, nil] VAOS clinical service (required for VA)
        # @param appointment_id [String, nil] EPS draft appointment id (required for EPS)
        # @return [Array<BaseSlot>]
        #
        # EPS +appointmentTypeId+ comes from +EpsProvider#first_self_schedulable_appointment_type_id!+
        # (EPS +appointment_types+ on the provider).
        #
        def slots_for(provider:, start_dt:, end_dt:, clinical_service: nil, appointment_id: nil)
          case provider
          when VAProvider
            fetch_va_slots(provider, start_dt, end_dt, clinical_service)
          when EpsProvider
            fetch_eps_slots(provider, start_dt, end_dt, appointment_id)
          else
            raise ArgumentError, "Unsupported provider type: #{provider.class.name}"
          end
        end

        private

        attr_reader :user

        ##
        # VPG +/vpg/v1/slots+ rejects the +clinicalService+ filter for VistA-backed sites with a
        # 400 ("Service Type cannot be used as a filter for VistA sites") and only honors it for
        # Cerner / Oracle Health sites. We forward +clinical_service+ only when the provider is
        # at a Cerner facility; for VistA sites +clinic_id+ + +location_id+ are sufficient to
        # scope the lookup. +clinical_service+ is still required for Cerner so the upstream gets
        # the same filtering it had pre-unified.
        def fetch_va_slots(provider, start_dt, end_dt, clinical_service)
          if provider.location_id.blank? || provider.id.blank?
            raise Common::Exceptions::UnprocessableEntity.new(
              detail: 'VA provider requires location_id and id (clinic IEN) for slot lookup'
            )
          end

          forward_clinical_service = provider.cerner?
          if forward_clinical_service && clinical_service.blank?
            raise Common::Exceptions::ParameterMissing, 'clinical_service'
          end

          raw = systems_service.get_available_slots(
            location_id: provider.location_id,
            clinic_id: provider.id,
            clinical_service: forward_clinical_service ? clinical_service : nil,
            provider_id: nil,
            start_dt:,
            end_dt:
          )
          slots = Array(raw).map { |slot| VASlot.from_vaos_slot(slot, location_id: provider.location_id) }
          log_fetch_success(provider.provider_type, slots)
          slots
        end

        def fetch_eps_slots(provider, start_dt, end_dt, appointment_id)
          raise Common::Exceptions::ParameterMissing, 'start_dt' if start_dt.blank?
          raise Common::Exceptions::ParameterMissing, 'end_dt' if end_dt.blank?
          raise Common::Exceptions::ParameterMissing, 'appointment_id' if appointment_id.blank?

          appointment_type_id = provider.first_self_schedulable_appointment_type_id!
          provider_id = provider.provider_service_id.presence || provider.id
          opts = {
            appointmentTypeId: appointment_type_id,
            startOnOrAfter: start_dt,
            startBefore: end_dt,
            appointmentId: appointment_id
          }
          response = eps_provider_service.get_provider_slots(provider_id, opts)
          slots = Array(response&.slots).map { |slot| EpsSlot.from_eps_slot(slot) }
          # CC providers need ~3 business days to accept and prep for a
          # referral; Wellhive doesn't apply this floor for us, so any slot
          # within the cutoff is one the provider will reject.
          filtered = CCLeadTimeFilter.filter(slots)
          log_lead_time_filtered(provider.provider_type, slots.size - filtered.size)
          log_fetch_success(provider.provider_type, filtered)
          filtered
        end

        def log_fetch_success(provider_type, slots)
          tags = ["provider_type:#{provider_type}"]
          StatsD.increment("#{STATSD_KEY_PREFIX}.fetch.success", tags:)
          StatsD.increment("#{STATSD_KEY_PREFIX}.fetch.no_results", tags:) if slots.blank?
        end

        def log_lead_time_filtered(provider_type, count)
          return if count.zero?

          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.lead_time.filtered",
            count,
            tags: ["provider_type:#{provider_type}"]
          )
        end

        def systems_service
          @systems_service ||= VAOS::V2::SystemsService.new(user)
        end

        def eps_provider_service
          @eps_provider_service ||= Eps::ProviderService.new(user)
        end
      end
    end
  end
end
