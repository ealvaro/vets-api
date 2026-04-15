# frozen_string_literal: true

require 'va_profile/contact_information/v2/service'

module AccreditedRepresentativePortal
  class ClaimantDetailsService
    attr_reader :profile, :icn

    def initialize(icn:, representative_name:, benefit_type_param: nil, power_of_attorney_requests: [],
                   is_representative: false)
      @icn = icn
      @representative_name = representative_name
      @benefit_type_param = benefit_type_param
      @power_of_attorney_requests = power_of_attorney_requests
      @is_representative = is_representative
    end

    def call
      @profile = claimant_profile_by_icn
      raise Common::Exceptions::RecordNotFound, 'Claimant not found' if profile.blank?

      payload = claimant_payload

      itf_types = itf_types_from_param(@benefit_type_param)
      itf_results = itf_types.map { |benefit_type| safe_intent_to_file(benefit_type) }.compact

      payload[:data][:itf] = itf_results
      payload
    end

    private

    def claimant_profile_by_icn
      MPI::Service.new.find_profile_by_identifier(
        identifier: icn,
        identifier_type: MPI::Constants::ICN
      )&.profile
    end

    def itf_types_from_param(type)
      return [type] if type.present?

      %w[compensation pension survivor]
    end

    def safe_intent_to_file(benefit_type)
      BenefitsClaims::Service.new(icn).get_intent_to_file(benefit_type)
    rescue => e
      # Avoid logging e.message to reduce the risk of unintentionally exposing
      # sensitive data from upstream services (e.g., identifiers in error text).
      Rails.logger.warn(
        'ClaimantDetailsService ITF lookup failed',
        { benefit_type:, error: e.class.name }
      )
      nil
    end

    def claimant_payload
      data = {
        first_name: profile.given_names&.first,
        last_name: profile.family_name,
        birth_date: profile.birth_date,
        ssn: profile.ssn&.last(4),
        phone: profile.home_phone,
        address: claimant_address,
        representative_name: @representative_name,
        email: claimant_email
      }

      if Flipper.enabled?(:accredited_representative_portal_cd_pending_notice)
        data[:is_representative] = @is_representative
        data[:poa_requests] = serialized_poa_requests
      end

      { data: }
    end

    def claimant_address
      addr = profile.address
      {
        line1: addr&.street,
        line2: addr&.street2,
        city: addr&.city,
        state: addr&.state,
        zip: addr&.postal_code
      }
    end

    def claimant_email
      # In VA Profile, a user can have only one email address.
      # See app/models/va_profile_redis/v2/contact_information.rb#L44
      va_profile&.person&.emails&.first&.email_address
    end

    def serialized_poa_requests
      @power_of_attorney_requests.map do |request|
        {
          id: request.id,
          resolution: serialized_resolution(request)
        }
      end
    end

    def serialized_resolution(request)
      return nil if request.resolution.blank?

      serialized = PowerOfAttorneyRequestSerializer.new(request).serializable_hash
      serialized[:resolution] || serialized['resolution']
    end

    def va_profile
      return nil if profile.vet360_id.blank?

      @va_profile ||= VAProfile::ContactInformation::V2::Service.get_person(profile.vet360_id)
    rescue RuntimeError, IOError
      # VAProfile will return RuntimeError if the profile cannot be found.
      # IOError may happen in development if vets-api-mockdata is missing or out-of-date.
      nil
    rescue => e
      Rails.logger.error("ARP: Claimant Details - Unable to fetch claimant email from VA Profile. #{e.class}")
      nil
    end
  end
end
