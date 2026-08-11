# frozen_string_literal: true

# Grant/revoke/verify the scoped Postgres role used to give Lighthouse
# temporary read/write access to the vets-api tables involved in their
# Benefits Intake / Benefit Claims / Decision Reviews migration.
#
# This rake task exists for environments where a `psql` client isn't
# available (e.g. a bare app-container terminal), only ActiveRecord is.
#
# TEMPORARY: this task exists only for the duration of the Lighthouse
# migration/rollback window. Remove this file once the follow-up revocation
# ticket is closed -- CREATE ROLE / GRANT capability shouldn't linger in
# the app long-term.
#
# Two roles are managed here:
#   grant_rw/revoke_rw      -- lighthouse_migration_rw, direct read/write
#                              (SELECT/INSERT/UPDATE/DELETE) on the tables.
#   grant_repl/revoke_repl  -- lighthouse_migration_repl, used by AWS DMS to
#                              keep the sync running during the migration
#                              window. DMS only needs SELECT (initial full
#                              load) plus the rds_replication role (CDC);
#                              it never writes through SQL, so no DML.
#
# Usage:
#   ROLE_PASSWORD=... VALID_UNTIL='2026-12-31 00:00:00-00' \
#     bundle exec rake lighthouse_pg_access:grant_rw    # or grant_repl
#   bundle exec rake lighthouse_pg_access:verify
#   FORCE=true bundle exec rake lighthouse_pg_access:revoke_rw   # or revoke_repl
#
# Env vars:
#   ROLE_PASSWORD  Required for grant_rw/grant_repl. Generate out-of-band, e.g.:
#                    openssl rand -base64 32
#   VALID_UNTIL    Required for grant_rw/grant_repl. Postgres timestamp, e.g.
#                    '2026-12-31 00:00:00-00'
#   ROLE_NAME      Defaults to lighthouse_migration_rw (grant_rw/revoke_rw) or
#                  lighthouse_migration_repl (grant_repl/revoke_repl).
#                  verify checks lighthouse_migration_rw unless overridden.
#   FORCE          Required (=true) to run grant/revoke tasks in production
#                  non-interactively, matching the features:setup convention.
#
# DMS prerequisites outside this task's control: the RDS parameter group
# needs rds.logical_replication=1, and DMS's replication slot must be
# dropped at teardown (see revoke_repl output).

# The vets-api tables in scope for the Lighthouse migration.
LIGHTHOUSE_PG_ACCESS_TABLES = [
  # Group A: modules/vba_documents (Benefits Intake)
  'vba_documents_upload_submissions',
  'vba_documents_monthly_stats',

  # Group B: modules/claims_api (Benefit Claims)
  'claims_api_auto_established_claims',
  'claims_api_supporting_documents',
  'claims_api_power_of_attorneys',
  'claims_api_power_of_attorney_requests',
  'claims_api_intent_to_files',
  'claims_api_processes',
  'claims_api_record_metadata',
  'claims_api_claim_submissions',
  'claims_api_evidence_waiver_submissions',

  # Group C: modules/appeals_api (Decision Reviews)
  'appeals_api_higher_level_reviews',
  'appeals_api_notice_of_disagreements',
  'appeals_api_supplemental_claims',
  'appeals_api_evidence_submissions',

  # Group D: core (config/features) -- feature-flag state
  'flipper_features',
  'flipper_gates'
].freeze

namespace :lighthouse_pg_access do
  def lighthouse_pg_access_role_name
    ENV.fetch('ROLE_NAME', 'lighthouse_migration_rw')
  end

  def lighthouse_pg_access_repl_role_name
    ENV.fetch('ROLE_NAME', 'lighthouse_migration_repl')
  end

  def lighthouse_pg_access_conn
    ActiveRecord::Base.connection
  end

  def lighthouse_pg_access_quoted_tables
    LIGHTHOUSE_PG_ACCESS_TABLES.map { |t| lighthouse_pg_access_conn.quote_table_name(t) }.join(', ')
  end

  # Confirms the *connecting* role -- not the target Lighthouse role -- has
  # enough privilege to run CREATE ROLE / GRANT before attempting anything.
  def lighthouse_pg_access_require_admin_privilege!
    can_create_role = lighthouse_pg_access_conn.select_value(
      'SELECT rolcreaterole FROM pg_roles WHERE rolname = current_user'
    )
    return if ActiveModel::Type::Boolean.new.cast(can_create_role)

    raise "Current DB connection (#{lighthouse_pg_access_conn.select_value('SELECT current_user')}) " \
          'lacks CREATEROLE -- this needs to run as a Platform DB admin connection, not the app\'s ' \
          'normal runtime role.'
  end

  # Matches the features:setup task's production safety convention: require
  # FORCE=true (or an interactive "yes") before mutating in production.
  def lighthouse_pg_access_require_confirmation!(action)
    return unless Rails.env.production?

    # Exact match on purpose: a lenient boolean cast would treat any
    # unrecognized string (e.g. FORCE=no) as true and skip the prompt.
    return if ENV['FORCE'] == 'true'

    unless $stdin.tty?
      raise "Running lighthouse_pg_access:#{action} in production non-interactively requires FORCE=true"
    end

    puts "You are about to run lighthouse_pg_access:#{action} against PRODUCTION " \
         "(database: #{lighthouse_pg_access_conn.current_database})."
    print 'Type "yes" to proceed: '
    confirm = $stdin.gets&.strip
    raise "Aborting lighthouse_pg_access:#{action}" unless confirm&.downcase == 'yes'
  end

  # Looks up each table's id sequence dynamically via pg_get_serial_sequence
  # rather than guessing `<table>_id_seq` names -- UUID-keyed tables resolve
  # to NULL and are skipped automatically.
  def lighthouse_pg_access_sequence_grant_revoke!(verb:, preposition:)
    role = lighthouse_pg_access_conn.quote_table_name(lighthouse_pg_access_role_name)
    LIGHTHOUSE_PG_ACCESS_TABLES.each do |table|
      seq = lighthouse_pg_access_conn.select_value(
        "SELECT pg_get_serial_sequence(#{lighthouse_pg_access_conn.quote(table)}, 'id')"
      )
      next if seq.nil?

      quoted_seq = lighthouse_pg_access_conn.quote_table_name(seq)
      lighthouse_pg_access_conn.execute("#{verb} USAGE, SELECT ON SEQUENCE #{quoted_seq} #{preposition} #{role}")
    end
  end

  desc 'Grant the Lighthouse scoped read/write role (ROLE_PASSWORD, VALID_UNTIL required)'
  task grant_rw: :environment do
    role_name = lighthouse_pg_access_role_name
    database_name = ActiveRecord::Base.connection_db_config.database
    role_password = ENV.fetch('ROLE_PASSWORD') do
      raise 'ROLE_PASSWORD is required (generate with: openssl rand -base64 32)'
    end
    valid_until = ENV.fetch('VALID_UNTIL') { raise "VALID_UNTIL is required, e.g. '2026-12-31 00:00:00-00'" }
    conn = lighthouse_pg_access_conn
    role = conn.quote_table_name(role_name)

    lighthouse_pg_access_require_confirmation!('grant_rw')
    lighthouse_pg_access_require_admin_privilege!

    conn.execute(<<~SQL.squish)
      CREATE ROLE #{role}
        WITH LOGIN
        PASSWORD #{conn.quote(role_password)}
        VALID UNTIL #{conn.quote(valid_until)};
    SQL
    puts "Created role #{role_name}."

    conn.execute("GRANT CONNECT ON DATABASE #{conn.quote_table_name(database_name)} TO #{role}")
    conn.execute("GRANT USAGE ON SCHEMA public TO #{role}")
    conn.execute(<<~SQL.squish)
      GRANT SELECT, INSERT, UPDATE, DELETE ON #{lighthouse_pg_access_quoted_tables}
      TO #{role}
    SQL
    puts "Granted table privileges on #{LIGHTHOUSE_PG_ACCESS_TABLES.size} tables."

    lighthouse_pg_access_sequence_grant_revoke!(verb: 'GRANT', preposition: 'TO')
    puts 'Granted sequence privileges where applicable.'

    puts "SUCCESS: grant_rw completed for role #{role_name} on database \"#{database_name}\"."
  rescue => e
    warn "ERROR: grant_rw failed for role #{role_name} on database \"#{database_name}\": #{e.message}"
    raise
  end

  desc 'Revoke the Lighthouse scoped read/write role and drop it'
  task revoke_rw: :environment do
    role_name = lighthouse_pg_access_role_name
    database_name = ActiveRecord::Base.connection_db_config.database
    conn = lighthouse_pg_access_conn
    role = conn.quote_table_name(role_name)

    lighthouse_pg_access_require_confirmation!('revoke_rw')

    lighthouse_pg_access_sequence_grant_revoke!(verb: 'REVOKE', preposition: 'FROM')
    puts 'Revoked sequence privileges where applicable.'

    conn.execute(<<~SQL.squish)
      REVOKE ALL PRIVILEGES ON #{lighthouse_pg_access_quoted_tables}
      FROM #{role}
    SQL
    conn.execute("REVOKE USAGE ON SCHEMA public FROM #{role}")
    conn.execute("REVOKE CONNECT ON DATABASE #{conn.quote_table_name(database_name)} FROM #{role}")
    conn.execute("DROP ROLE IF EXISTS #{role}")

    puts "SUCCESS: revoke_rw completed for role #{role_name} on database \"#{database_name}\"."
  rescue => e
    warn "ERROR: revoke_rw failed for role #{role_name} on database \"#{database_name}\": #{e.message}"
    raise
  end

  desc 'Grant the Lighthouse DMS replication role (ROLE_PASSWORD, VALID_UNTIL required)'
  task grant_repl: :environment do
    role_name = lighthouse_pg_access_repl_role_name
    database_name = ActiveRecord::Base.connection_db_config.database
    role_password = ENV.fetch('ROLE_PASSWORD') do
      raise 'ROLE_PASSWORD is required (generate with: openssl rand -base64 32)'
    end
    valid_until = ENV.fetch('VALID_UNTIL') { raise "VALID_UNTIL is required, e.g. '2026-12-31 00:00:00-00'" }
    conn = lighthouse_pg_access_conn
    role = conn.quote_table_name(role_name)

    lighthouse_pg_access_require_confirmation!('grant_repl')
    lighthouse_pg_access_require_admin_privilege!

    conn.execute(<<~SQL.squish)
      CREATE ROLE #{role}
        WITH LOGIN
        PASSWORD #{conn.quote(role_password)}
        VALID UNTIL #{conn.quote(valid_until)};
    SQL
    puts "Created role #{role_name}."

    # On RDS/Aurora the REPLICATION attribute can't be set directly; CDC
    # access is granted via the rds_replication role instead. Fall back to
    # ALTER ROLE ... REPLICATION for local/self-hosted Postgres.
    if conn.select_value("SELECT 1 FROM pg_roles WHERE rolname = 'rds_replication'")
      conn.execute("GRANT rds_replication TO #{role}")
      puts 'Granted rds_replication membership.'
    else
      conn.execute("ALTER ROLE #{role} WITH REPLICATION")
      puts 'Set REPLICATION attribute (non-RDS database).'
    end

    conn.execute("GRANT CONNECT ON DATABASE #{conn.quote_table_name(database_name)} TO #{role}")
    conn.execute("GRANT USAGE ON SCHEMA public TO #{role}")
    conn.execute(<<~SQL.squish)
      GRANT SELECT ON #{lighthouse_pg_access_quoted_tables}
      TO #{role}
    SQL
    puts "Granted SELECT on #{LIGHTHOUSE_PG_ACCESS_TABLES.size} tables (DMS full load)."

    puts "SUCCESS: grant_repl completed for role #{role_name} on database \"#{database_name}\"."
    puts 'REMINDER: DMS CDC also requires rds.logical_replication=1 in the RDS parameter group.'
  rescue => e
    warn "ERROR: grant_repl failed for role #{role_name} on database \"#{database_name}\": #{e.message}"
    raise
  end

  desc 'Revoke the Lighthouse DMS replication role and drop it'
  task revoke_repl: :environment do
    role_name = lighthouse_pg_access_repl_role_name
    database_name = ActiveRecord::Base.connection_db_config.database
    conn = lighthouse_pg_access_conn
    role = conn.quote_table_name(role_name)

    lighthouse_pg_access_require_confirmation!('revoke_repl')

    conn.execute(<<~SQL.squish)
      REVOKE ALL PRIVILEGES ON #{lighthouse_pg_access_quoted_tables}
      FROM #{role}
    SQL
    conn.execute("REVOKE USAGE ON SCHEMA public FROM #{role}")
    conn.execute("REVOKE CONNECT ON DATABASE #{conn.quote_table_name(database_name)} FROM #{role}")
    conn.execute("DROP ROLE IF EXISTS #{role}")

    puts "SUCCESS: revoke_repl completed for role #{role_name} on database \"#{database_name}\"."

    slots = conn.select_all('SELECT slot_name, active FROM pg_replication_slots').to_a
    if slots.any?
      puts 'REMINDER: replication slots still exist -- an abandoned slot pins WAL and can fill the disk.'
      slots.each { |s| puts "  #{s['slot_name']} (active: #{s['active']})" }
      puts 'Drop the DMS slot once the DMS task is deleted: SELECT pg_drop_replication_slot(\'<slot_name>\');'
    end
  rescue => e
    warn "ERROR: revoke_repl failed for role #{role_name} on database \"#{database_name}\": #{e.message}"
    raise
  end

  desc 'List current grants for the Lighthouse scoped role'
  task verify: :environment do
    role_name = lighthouse_pg_access_role_name
    rows = lighthouse_pg_access_conn.select_all(<<~SQL.squish).to_a
      SELECT table_name, privilege_type
      FROM information_schema.role_table_grants
      WHERE grantee = #{lighthouse_pg_access_conn.quote(role_name)}
      ORDER BY table_name, privilege_type
    SQL

    if rows.empty?
      puts "No grants found for role #{role_name}."
    else
      rows.each { |row| puts "#{row['table_name']} | #{row['privilege_type']}" }
      puts "#{rows.size} grant(s) for role #{role_name}."
    end
  end
end
