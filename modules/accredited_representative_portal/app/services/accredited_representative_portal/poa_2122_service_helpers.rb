# frozen_string_literal: true

module AccreditedRepresentativePortal
  module Poa2122ServiceHelpers
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
      Veteran::Service::Organization.where(poa: codes)
    end

    def set_active_reps_mode!(org_scope, mode)
      reps_scope =
        Veteran::Service::OrganizationRepresentative
        .active
        .where(organization_poa: org_scope.select(:poa))
        .where.not(acceptance_mode: mode)

      expected = reps_scope.count

      updated = reps_scope.update_all(acceptance_mode: mode) # rubocop:disable Rails/SkipsModelValidations

      if updated != expected
        raise MismatchError,
              "Poa2122ServiceHelpers#set_active_reps_mode! mismatch: expected #{expected} reps, updated #{updated}"
      end

      updated
    end

    # rubocop:disable Rails/SkipsModelValidations
    def set_org_acceptance_modes!(org_scope, primary_mode:, default_rep_mode:)
      orgs_to_update_scope =
        org_scope.where(
          'primary_org_acceptance_mode != :primary OR default_new_rep_acceptance_mode != :default',
          primary: primary_mode, default: default_rep_mode
        )

      expected = orgs_to_update_scope.count

      updated = orgs_to_update_scope.update_all(
        primary_org_acceptance_mode: primary_mode,
        default_new_rep_acceptance_mode: default_rep_mode
      )

      if updated != expected
        raise MismatchError,
              "Poa2122ServiceHelpers#set_org_acceptance_modes! mismatch: expected #{expected} orgs, updated #{updated}"
      end

      updated
    end
    # rubocop:enable Rails/SkipsModelValidations

    def set_specific_reps_mode!(org_poa, rep_ids, mode)
      reps_scope =
        Veteran::Service::OrganizationRepresentative
        .active
        .where(organization_poa: org_poa, representative_id: rep_ids)
        .where.not(acceptance_mode: mode)

      expected = reps_scope.count
      updated = reps_scope.update_all(acceptance_mode: mode) # rubocop:disable Rails/SkipsModelValidations

      if updated != expected
        raise MismatchError,
              "Poa2122ServiceHelpers#set_specific_reps_mode! mismatch: expected #{expected} reps, updated #{updated}"
      end

      updated
    end
  end
end
