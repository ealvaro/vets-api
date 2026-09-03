# frozen_string_literal: true

require 'csv'

# One-time backfill: copy POA acceptance configuration from the legacy
# Veteran::Service::* tables into the Accredited* tables after the model migration.
#
# The migration that added acceptance columns to `accreditations` and
# `accredited_organizations` defaulted them (no_acceptance / false) and did NOT
# backfill from the legacy tables, so any org/rep configured on the legacy side
# reads as unconfigured on the accredited side. This copies that state over.
#
# Mappings:
#   veteran_organizations(poa)                    -> accredited_organizations(poa_code)
#     can_accept_digital_poa_requests, primary_org_acceptance_mode, default_new_rep_acceptance_mode
#   organization_representatives(active)          -> accreditations(active)
#     acceptance_mode, matched by (org poa_code, rep registration_number)
#
# FILL-IF-UNSET, NOT A TWO-WAY SYNC:
#   Only rows still sitting at their post-migration default are written. The accredited
#   side can be configured independently (vso:configure_accredited_online_submission,
#   vso:set_accredited_reps_acceptance_mode), and those deliberate values must not be
#   reverted to legacy state. Rows where BOTH sides are non-default and they disagree are
#   reported as conflicts and left untouched for manual reconciliation.
#
# Safety:
#   - Dry-run by default. Pass mode=commit to write.
#   - Every planned change is written to a reversal manifest (CSV) in BOTH modes, so the
#     dry run doubles as the rollback artifact. Path is printed at the end of the run.
#   - Idempotent: only rows still at their default are updated, so re-running reports 0.
#   - Compare-and-swap: each UPDATE is scoped to the value observed at plan time, so a
#     concurrent write (or a soft-deactivation) drops the affected count and rolls back.
#   - Unscoped production commits require confirm=<orgs>:<reps> matching the freshly
#     computed plan, which also proves a dry run was reviewed and detects plan drift.
#   - Do not run between 01:30-05:00 UTC: Veteran::VSOReloader (02:00) destroys orgs and
#     AccreditedEntitiesDailyUpdate/AccreditationSync (04:00) rewrites acceptance_mode.
#
# Usage:
#   bundle exec rake "vso:backfill_accredited_acceptance_from_legacy"                  # dry run, all orgs
#   bundle exec rake "vso:backfill_accredited_acceptance_from_legacy[dry_run,091 083]" # dry run, two orgs
#   bundle exec rake "vso:backfill_accredited_acceptance_from_legacy[commit,091]"      # commit, one org
#   bundle exec rake "vso:backfill_accredited_acceptance_from_legacy[commit,,12:340]"  # commit all, confirmed
#
namespace :vso do
  desc 'Backfill Accredited* acceptance flags/modes from legacy Veteran::Service::* tables'
  task :backfill_accredited_acceptance_from_legacy, %i[mode poa_codes confirm] => :environment do |_t, args|
    # Post-migration defaults. A target still holding these is considered "unconfigured"
    # and is safe to fill from legacy; anything else was set deliberately.
    org_defaults = {
      can_accept_digital_poa_requests: false,
      primary_org_acceptance_mode: 'no_acceptance',
      default_new_rep_acceptance_mode: 'no_acceptance'
    }.freeze
    rep_default = 'no_acceptance'
    batch_size = RepresentationManagement::AccreditationSync::BATCH_SIZE

    mode = (args[:mode].presence || 'dry_run').strip
    raise ArgumentError, "mode must be 'dry_run' or 'commit' (got #{mode.inspect})" unless %w[dry_run
                                                                                              commit].include?(mode)

    commit = mode == 'commit'
    poa_filter = args[:poa_codes].to_s.split(/[\s,]+/).map { |c| c.strip.upcase }.compact_blank.uniq

    Rails.logger.tagged('rake:vso:backfill_accredited_acceptance_from_legacy') do
      log = lambda { |msg|
        puts msg
        Rails.logger.info(msg)
      }
      scope_desc = poa_filter.any? ? "scoped to POA: #{poa_filter.join(', ')}" : 'all orgs'
      log.call("Mode: #{commit ? 'COMMIT' : 'DRY RUN'} | #{scope_desc}")

      manifest = [] # [table, id, poa_code, registration_number, attr, old_value, new_value]

      # ---- Plan org-level changes -------------------------------------------------
      legacy_orgs = Veteran::Service::Organization.all
      legacy_orgs = legacy_orgs.where(poa: poa_filter) if poa_filter.any?
      legacy_org_by_poa = legacy_orgs.index_by(&:poa)

      accredited_orgs = AccreditedOrganization.all
      accredited_orgs = accredited_orgs.where(poa_code: poa_filter) if poa_filter.any?
      accredited_org_by_poa = accredited_orgs.index_by(&:poa_code)

      org_plans = [] # [id, poa_code, diff, expected_current]
      org_missing = []
      org_conflicts = []

      legacy_org_by_poa.each do |poa, legacy|
        target = accredited_org_by_poa[poa]
        if target.nil?
          org_missing << poa
          next
        end

        diff = {}
        expected_current = {}
        org_defaults.each do |attr, default|
          src = legacy.public_send(attr)
          cur = target.public_send(attr)
          next if src.nil? || src == cur          # nothing to copy (or legacy NULL -> skip, target is NOT NULL)
          next if src == default                  # legacy is itself unconfigured

          if cur != default
            # Target was configured deliberately and disagrees with legacy. Never revert.
            org_conflicts << "#{poa}.#{attr}: accredited=#{cur.inspect} legacy=#{src.inspect}"
            next
          end

          diff[attr] = src
          expected_current[attr] = cur
        end
        next if diff.empty?

        diff.each do |attr, new_value|
          manifest << ['accredited_organizations', target.id, poa, nil, attr, expected_current[attr], new_value]
        end
        org_plans << [target.id, poa, diff, expected_current]
      end

      # ---- Plan rep-level changes -------------------------------------------------
      target_scope = Accreditation.active.joins(:accredited_individual)
      target_scope = if poa_filter.any?
                       target_scope.for_organization_poa_codes(poa_filter)
                     else
                       target_scope.joins(:accredited_organization)
                     end

      target_by_key = {}
      key_collisions = []
      target_rows = target_scope.pluck('accredited_organizations.poa_code',
                                       'accredited_individuals.registration_number',
                                       'accreditations.id', 'accreditations.acceptance_mode')
      target_rows.each do |poa_code, reg, id, current_mode|
        key = "#{poa_code}|#{reg}"
        # Same registration_number can exist across individual_types; refuse to guess.
        key_collisions << key if target_by_key.key?(key)
        target_by_key[key] = [id, current_mode]
      end

      legacy_reps = Veteran::Service::OrganizationRepresentative.active
      legacy_reps = legacy_reps.where(organization_poa: poa_filter) if poa_filter.any?

      # Bucket by [expected_current_mode, new_mode] so the UPDATE can compare-and-swap.
      rep_plans = Hash.new { |h, k| h[k] = [] }
      rep_missing = []
      rep_conflicts = []

      legacy_reps.pluck(:organization_poa, :representative_id, :acceptance_mode).each do |poa_code, reg, src_mode|
        target = target_by_key["#{poa_code}|#{reg}"]
        if target.nil?
          rep_missing << "#{poa_code}|#{reg}"
          next
        end
        id, current_mode = target
        next if src_mode == rep_default || current_mode == src_mode

        if current_mode != rep_default
          rep_conflicts << "#{poa_code}|#{reg}: accredited=#{current_mode} legacy=#{src_mode}"
          next
        end

        manifest << ['accreditations', id, poa_code, reg, 'acceptance_mode', current_mode, src_mode]
        rep_plans[[current_mode, src_mode]] << id
      end
      planned_rep_changes = rep_plans.values.sum(&:size)

      # ---- Write the reversal manifest (both modes) -------------------------------
      manifest_path = Rails.root.join('tmp',
                                      "backfill_accredited_acceptance_#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.csv")
      CSV.open(manifest_path, 'w') do |csv|
        csv << %w[table id poa_code registration_number attribute old_value new_value]
        manifest.each { |row| csv << row }
      end

      # ---- Report -----------------------------------------------------------------
      sample = lambda { |arr|
        if arr.any?
          " (#{arr.first(20).join(', ')}#{arr.size > 20 ? ', …' : ''})"
        else
          ''
        end
      }
      log.call('')
      log.call('--- Orgs ---')
      log.call("  legacy orgs in scope:        #{legacy_org_by_poa.size}")
      log.call("  needing update:              #{org_plans.size}")
      log.call("  MISSING accredited org:      #{org_missing.size}#{sample.call(org_missing)}")
      log.call("  CONFLICT (left untouched):   #{org_conflicts.size}#{sample.call(org_conflicts)}")
      log.call('--- Reps (active) ---')
      log.call("  needing update:              #{planned_rep_changes}")
      log.call("  MISSING accreditation:       #{rep_missing.size}#{sample.call(rep_missing)}")
      log.call("  CONFLICT (left untouched):   #{rep_conflicts.size}#{sample.call(rep_conflicts)}")
      log.call("Reversal manifest: #{manifest_path}")

      if poa_filter.any? && (unmatched = poa_filter - legacy_org_by_poa.keys).any?
        log.call("WARNING: requested POA codes with no legacy org: #{unmatched.join(', ')}")
      end

      if commit
        # Unscoped production commits must echo back the plan they reviewed.
        if poa_filter.empty? && Rails.env.production?
          expected = "#{org_plans.size}:#{planned_rep_changes}"
          unless args[:confirm].to_s.strip == expected
            raise "Unscoped production commit requires confirm=#{expected} (got #{args[:confirm].inspect})"
          end
        end

        if key_collisions.any?
          raise "Refusing to commit: #{key_collisions.size} registration-number " \
                "collisions#{sample.call(key_collisions)}"
        end

        # ---- Apply (transactional, compare-and-swap) ------------------------------
        orgs_updated = 0
        reps_updated = 0

        ActiveRecord::Base.transaction do
          org_plans.each do |id, _poa, diff, expected_current|
            # Scoped to the values observed at plan time: 0 rows means it moved under us.
            orgs_updated += AccreditedOrganization.where(id:).where(expected_current)
                                                  .update_all(diff.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
          end
          if orgs_updated != org_plans.size
            raise "Org backfill mismatch: planned #{org_plans.size}, updated #{orgs_updated}"
          end

          rep_plans.each do |(expected_mode, new_mode), ids|
            ids.each_slice(batch_size) do |slice|
              reps_updated += Accreditation.active.where(id: slice, acceptance_mode: expected_mode)
                                           .update_all(acceptance_mode: new_mode, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
            end
          end
          if reps_updated != planned_rep_changes
            raise "Rep backfill mismatch: planned #{planned_rep_changes}, updated #{reps_updated}"
          end
        end

        # Only after the transaction has actually committed.
        log.call('')
        log.call("COMMITTED — orgs updated: #{orgs_updated}, accreditations updated: #{reps_updated}")
        log.call("Reverse with the manifest at: #{manifest_path}")
      else
        log.call('')
        log.call('DRY RUN — no changes written. Re-run with mode=commit to apply.')
      end
    end
  end
end
