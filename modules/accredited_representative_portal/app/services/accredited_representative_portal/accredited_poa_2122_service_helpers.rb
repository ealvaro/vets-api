# frozen_string_literal: true

module AccreditedRepresentativePortal
  module AccreditedPoa2122ServiceHelpers
    ACCEPTANCE_MODES = %w[any_request self_only no_acceptance].freeze

    class MismatchError < StandardError; end

    def normalize_codes(input)
      Array(input)
        .flatten
        .flat_map { |c| c.to_s.split(/[,\s]+/) }
        .map(&:strip)
        .compact_blank
        .uniq
    end

    def organizations_for(codes)
      AccreditedOrganization.where(poa_code: codes)
    end

    def validate_mode!(mode, label)
      raise ArgumentError, "Invalid #{label}: #{mode}" unless ACCEPTANCE_MODES.include?(mode)
    end

    def set_active_reps_mode!(org_scope, mode)
      reps_scope =
        Accreditation
        .active
        .joins(:accredited_organization)
        .where(accredited_organizations: { id: org_scope.select(:id) })
        .where.not(acceptance_mode: mode)

      expected = reps_scope.count
      updated = reps_scope.update_all(acceptance_mode: mode) # rubocop:disable Rails/SkipsModelValidations

      if updated != expected
        raise AccreditedPoa2122ServiceHelpers::MismatchError,
              'AccreditedPoa2122ServiceHelpers#set_active_reps_mode! mismatch: ' \
              "expected #{expected} reps, updated #{updated}"
      end

      updated
    end

    def set_org_acceptance_modes!(org_scope, primary_mode:, default_rep_mode:)
      orgs_to_update_scope =
        org_scope.where(
          'primary_org_acceptance_mode != :primary OR default_new_rep_acceptance_mode != :default',
          primary: primary_mode,
          default: default_rep_mode
        )

      expected = orgs_to_update_scope.count

      updated = orgs_to_update_scope.update_all( # rubocop:disable Rails/SkipsModelValidations
        primary_org_acceptance_mode: primary_mode,
        default_new_rep_acceptance_mode: default_rep_mode
      )

      if updated != expected
        raise AccreditedPoa2122ServiceHelpers::MismatchError,
              'AccreditedPoa2122ServiceHelpers#set_org_acceptance_modes! mismatch: ' \
              "expected #{expected} orgs, updated #{updated}"
      end

      updated
    end

    def set_specific_reps_mode!(poa_code, registration_numbers, mode)
      reps_scope =
        Accreditation
        .active
        .joins(:accredited_organization, :accredited_individual)
        .where(accredited_organizations: { poa_code: })
        .where(accredited_individuals: { registration_number: registration_numbers })
        .where.not(acceptance_mode: mode)

      expected = reps_scope.count
      updated = reps_scope.update_all(acceptance_mode: mode) # rubocop:disable Rails/SkipsModelValidations

      if updated != expected
        raise AccreditedPoa2122ServiceHelpers::MismatchError,
              'AccreditedPoa2122ServiceHelpers#set_specific_reps_mode! mismatch: ' \
              "expected #{expected} reps, updated #{updated}"
      end

      updated
    end
  end
end
