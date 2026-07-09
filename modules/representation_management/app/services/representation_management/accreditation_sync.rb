# frozen_string_literal: true

module RepresentationManagement
  # Idempotently syncs Accreditation join rows (AccreditedIndividual <-> AccreditedOrganization)
  # from a daily ingestion source (the trexler XLSX reload or the accreditation API), mirroring the
  # live Veteran::RepresentativeRelationshipsSync behavior for the legacy organization_representatives
  # join.
  #
  # Callers resolve their source data down to [accredited_individual_id, accredited_organization_id]
  # pairs plus the set of organization ids seen in the run, and this service:
  #
  # - Inserts any missing (individual, organization) pair, seeding acceptance_mode from the
  #   organization's default_new_rep_acceptance_mode. Existing rows are never overwritten, so a
  #   per-rep acceptance_mode set later (e.g. by the online-submission configuration services)
  #   survives re-ingestion.
  # - Reactivates pairs that are present again.
  # - Soft-deletes (deactivated_at) pairs that have disappeared, scoped to the organizations seen in
  #   the run so partial reloads never deactivate joins for organizations they did not process.
  class AccreditationSync
    BATCH_SIZE = 1000
    DEFAULT_ACCEPTANCE_MODE = 'no_acceptance'

    class << self
      def sync!(individual_org_id_pairs:, organization_ids:)
        new.sync!(individual_org_id_pairs:, organization_ids:)
      end
    end

    def sync!(individual_org_id_pairs:, organization_ids:)
      pairs = individual_org_id_pairs.compact.uniq
      org_ids = Array(organization_ids).compact.uniq
      return if pairs.empty? || org_ids.empty?

      rows = build_rows(pairs, organization_accept_map(org_ids))

      insert_missing_rows(rows) if rows.any?
      reactivate_pairs!(pairs)
      deactivate_missing_pairs!(pairs, org_ids)
    end

    private

    # @return [Hash] { accredited_organization_id => default_new_rep_acceptance_mode }
    def organization_accept_map(org_ids)
      AccreditedOrganization
        .where(id: org_ids)
        .pluck(:id, :default_new_rep_acceptance_mode)
        .to_h
    end

    def build_rows(pairs, accept_map)
      pairs.filter_map do |individual_id, organization_id|
        next if individual_id.blank? || organization_id.blank?

        {
          accredited_individual_id: individual_id,
          accredited_organization_id: organization_id,
          acceptance_mode: accept_map.fetch(organization_id, DEFAULT_ACCEPTANCE_MODE)
        }
      end
    end

    # Idempotent insert: existing rows conflict on the unique (individual, organization) index and are
    # left untouched, so acceptance_mode is only ever seeded on first insert.
    # rubocop:disable Rails/SkipsModelValidations
    def insert_missing_rows(rows)
      Accreditation.insert_all(
        rows,
        unique_by: %i[accredited_individual_id accredited_organization_id]
      )
    end

    def reactivate_pairs!(pairs)
      pairs.each_slice(BATCH_SIZE) do |slice|
        conditions = slice.map { |_| '(accredited_individual_id = ? AND accredited_organization_id = ?)' }.join(' OR ')
        binds = slice.flat_map { |individual_id, organization_id| [individual_id, organization_id] }

        Accreditation
          .where.not(deactivated_at: nil)
          .where(conditions, *binds)
          .update_all(deactivated_at: nil)
      end
    end

    def deactivate_missing_pairs!(pairs, org_ids)
      expected = pairs.to_set { |individual_id, organization_id| [individual_id, organization_id] }
      ids_to_deactivate = []

      Accreditation
        .where(accredited_organization_id: org_ids, deactivated_at: nil)
        .select(:id, :accredited_individual_id, :accredited_organization_id)
        .find_each do |join|
          key = [join.accredited_individual_id, join.accredited_organization_id]
          ids_to_deactivate << join.id unless expected.include?(key)
        end

      return if ids_to_deactivate.empty?

      now = Time.current
      ids_to_deactivate.each_slice(BATCH_SIZE) do |slice|
        Accreditation.where(id: slice).update_all(deactivated_at: now)
      end
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
