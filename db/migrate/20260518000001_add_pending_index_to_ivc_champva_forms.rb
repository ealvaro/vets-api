# frozen_string_literal: true

# Adds two indexes to keep PollPegaStatusJob and OldRecordsCleanupJob efficient
# as the ivc_champva_forms table grows.
#
# 1. Partial index on form_uuid scoped to non-terminal rows only.
#    The job queries "pega_status IS NULL OR NOT IN (complete statuses)" on every run.
#    Without this index Postgres does a full sequential scan. With a partial index it
#    only scans the small fraction of rows that still need polling — and those rows
#    fall out of the index automatically once they reach a terminal status.
#
# 2. Index on updated_at so OldRecordsCleanupJob's
#    "WHERE updated_at < 60.days.ago" range scan uses an index instead of a seqscan.
class AddPendingIndexToIvcChampvaForms < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # Keep this list in sync with IvcChampva::PollPegaStatusJob::COMPLETE_STATUSES.
  # Both misspelled (current Pega API) and correctly-spelled (future-proof) variants
  # are included. 'processed' and 'manually processed' are also terminal per ClaimBuilder.
  #
  # NOTE: 'additional documentation requested' is intentionally excluded — the business
  # use of that status is still being clarified.
  # Both misspelled (current Pega API) and correctly-spelled variants of
  # 'eligibility denied/additional information needed' are treated as terminal.
  COMPLETE_STATUSES = [
    'eligiblity denied/additional information needed',
    'eligibility denied/additional information needed',
    'processed - eligiblity determination unknown',
    'processed - eligibility determination unknown',
    'eligible - issued a card',
    'duplicate application',
    'eligible - reissued a card',
    'document identification error',
    'processed',
    'manually processed'
  ].freeze

  def up
    # Partial index — only non-terminal (pending) rows are indexed.
    # Size stays bounded: a completed application's row is never in this index.
    # safety_assured: CONCURRENTLY + IF NOT EXISTS makes this safe to run on production.
    safety_assured do
      execute <<~SQL
        CREATE INDEX CONCURRENTLY IF NOT EXISTS index_ivc_champva_forms_on_pending_form_uuid
        ON ivc_champva_forms (form_uuid)
        WHERE pega_status IS NULL
           OR pega_status NOT IN (
                'eligiblity denied/additional information needed',
                'eligibility denied/additional information needed',
                'processed - eligiblity determination unknown',
                'processed - eligibility determination unknown',
                'eligible - issued a card',
                'duplicate application',
                'eligible - reissued a card',
                'document identification error',
                'processed',
                'manually processed'
              )
      SQL

      # Supports OldRecordsCleanupJob: WHERE updated_at < 60.days.ago
      execute <<~SQL
        CREATE INDEX CONCURRENTLY IF NOT EXISTS index_ivc_champva_forms_on_updated_at
        ON ivc_champva_forms (updated_at)
      SQL
    end
  end

  def down
    safety_assured do
      execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ivc_champva_forms_on_pending_form_uuid'
      execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ivc_champva_forms_on_updated_at'
    end
  end
end
