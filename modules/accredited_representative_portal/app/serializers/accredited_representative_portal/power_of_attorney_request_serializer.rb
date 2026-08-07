# frozen_string_literal: true

module AccreditedRepresentativePortal
  class PowerOfAttorneyRequestSerializer < ApplicationSerializer
    REDACTION_POLICY = {
      FIELDS: %w[ssn vaFileNumber].freeze,
      CHARS_VISIBLE: 4
    }.freeze

    attributes :created_at, :expires_at

    attribute :power_of_attorney_form do |poa_request|
      next unless poa_request.power_of_attorney_form

      cloned_form = poa_request.power_of_attorney_form.parsed_data.deep_dup
      cloned_form.tap do |form|
        PowerOfAttorneyRequest::ClaimantTypes::ALL.product(REDACTION_POLICY[:FIELDS]).each do |(claimant_type, key)|
          value = form.dig(claimant_type, key).to_s
          next if value.blank?

          redacted_value = value[-REDACTION_POLICY[:CHARS_VISIBLE]..]
          form[claimant_type][key] = redacted_value
        end

        case poa_request.claimant_type
        when PowerOfAttorneyRequest::ClaimantTypes::DEPENDENT
          form['claimant'] = form.delete('dependent')
        when PowerOfAttorneyRequest::ClaimantTypes::VETERAN
          form['claimant'] = form.delete('veteran')
          form.delete('dependent')
        end
      end
    end

    attribute :resolution do |poa_request|
      next unless poa_request.resolution

      serializer =
        case poa_request.resolution.resolving
        when PowerOfAttorneyRequestDecision
          DecisionSerializer
        when PowerOfAttorneyRequestExpiration
          ExpirationSerializer
        end

      serializer
        .new(poa_request.resolution)
        .serializable_hash
    end

    attribute :accredited_individual do |poa_request|
      AccreditedIndividualSerializer
        .new(poa_request.accredited_individual)
        .serializable_hash
    end

    attribute :power_of_attorney_holder,
              if: ->(poa_request) { poa_request.accredited_organization.present? } do |poa_request|
      OrganizationPowerOfAttorneyHolderSerializer
        .new(poa_request.accredited_organization)
        .serializable_hash
    end

    attribute :power_of_attorney_form_submission,
              if: ->(poa_request) { poa_request.accepted? } do |poa_request|
      status =
        case poa_request.power_of_attorney_form_submission&.status
        when PowerOfAttorneyFormSubmission::Statuses::SUCCEEDED
          'SUCCEEDED'
        when PowerOfAttorneyFormSubmission::Statuses::ENQUEUE_FAILED,
          PowerOfAttorneyFormSubmission::Statuses::FAILED
          'FAILED'
        else
          'PENDING'
        end

      { status: }
    end

    attribute :claimant_id do |poa_request|
      claimant = poa_request.claimant
      IcnTemporaryIdentifier.save_icn(claimant.icn).id if claimant
    end

    attribute :can_accept do |poa_request, params|
      current_user = params[:current_user]
      next false unless current_user

      PowerOfAttorneyRequestPolicy.new(current_user, poa_request).can_accept?
    end

    attribute :dependent_relationship_established, if: proc { |_, params|
      params[:include_dependent_status]
    } do |poa_request|
      claimant_type = poa_request.claimant_type
      form_data = poa_request.power_of_attorney_form&.parsed_data

      if claimant_type == PowerOfAttorneyRequest::ClaimantTypes::DEPENDENT && form_data.present?
        veteran = {
          first_name: form_data.dig('veteran', 'name', 'first'),
          last_name: form_data.dig('veteran', 'name', 'last'),
          ssn: form_data.dig('veteran', 'ssn'),
          birth_date: form_data.dig('veteran', 'dateOfBirth')
        }
        dependent = {
          first_name: form_data.dig('dependent', 'name', 'first'),
          last_name: form_data.dig('dependent', 'name', 'last'),
          icn: poa_request.claimant&.icn,
          birth_date: form_data.dig('dependent', 'dateOfBirth')
        }

        begin
          DependentLookupService.new(veteran:).dependent_relationship_established?(dependent:)
        rescue => e
          Rails.logger.error('Failed to retrieve dependency establishment status.',
                             error_class: e.class.name, error_message: e.message)
          false
        end
      else
        false
      end
    end
  end
end
