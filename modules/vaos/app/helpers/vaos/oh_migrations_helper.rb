# frozen_string_literal: true

module VAOS
  module OhMigrationsHelper
    # Retrieves and builds a hash of migrations from the configured settings.
    #
    # Reads Settings.mhv.oh_facility_checks.oh_migrations_list, which is expected to be
    # a semicolon-separated list of migration entry strings. If the setting is nil,
    # empty, or only whitespace, the method returns an empty Hash.
    #
    # @return [Hash] the constructed migrations hash, or an empty hash if no valid entries.
    # @example
    # {
    #   '987': {
    #     migration_days: 30,
    #     migration_date: '2026-02-11',
    #     disable_eligibility: true,
    #     cancellation_disabled: true
    #   },
    #   '123': {
    #     migration_days: 30,
    #     migration_date: '2026-05-01',
    #     disable_eligibility: false,
    #     cancellation_disabled: false
    #   }
    # }
    def self.get_migrations(user: nil)
      return {} if user && Flipper.enabled?(:mhv_oh_migration_trusted_user_bypass, user)

      raw_value = Settings.mhv.oh_facility_checks.oh_migrations_list

      return {} if raw_value.to_s.strip.blank?

      migrations = {}
      today = Time.use_zone('Eastern Time (US & Canada)') { Date.current }

      raw_value.to_s.split(';').filter_map do |migration_entry_string|
        migration_entry_string = migration_entry_string.strip
        next if migration_entry_string.blank?

        migration_entry = MigrationUtils.parse_single_migration_entry(migration_entry_string)

        MigrationUtils.build_migrations(migrations, migration_entry, today, user)
      end

      migrations
    end

    module MigrationUtils
      ELIGIBILITY_START_DAYS = -30
      ELIGIBILITY_END_DAYS = 47
      ELIGIBILITY_DARK_DEPLOY_END_DAYS = 45
      CANCELLATION_START_DAYS = -10
      CANCELLATION_END_DAYS = 10
      CANCELLATION_DARK_DEPLOY_END_DAYS = 5

      def self.build_migrations(migrations, migration_entry, today, user)
        migration_entry[:facilities].each do |facility|
          parent_facility = facility[:facility_id][0, 3]
          migration_days = (today - migration_entry[:migration_date]).to_i

          migration = {
            migration_days:,
            migration_date: migration_entry[:migration_date]
          }

          check_eligibility_override(migration, migration_days, user)
          check_cancellation_override(migration, migration_days, user)

          migrations[parent_facility] = migration
        end
      end

      def self.cancellation_end_days(user)
        if user && Flipper.enabled?(:mhv_oh_migration_dark_deploy_appointments,
                                    user)
          CANCELLATION_DARK_DEPLOY_END_DAYS
        else
          CANCELLATION_END_DAYS
        end
      end

      def self.eligibility_end_days(user)
        if user && Flipper.enabled?(:mhv_oh_migration_dark_deploy_appointments,
                                    user)
          ELIGIBILITY_DARK_DEPLOY_END_DAYS
        else
          ELIGIBILITY_END_DAYS
        end
      end

      def self.check_eligibility_override(migration, migration_days, user)
        is_minus30 = migration_days >= ELIGIBILITY_START_DAYS
        is_past_cutoff = migration_days >= eligibility_end_days(user)

        # eligibility is disabled from 30 days before migration until the cutoff
        migration[:disable_eligibility] = is_minus30 && !is_past_cutoff
      end

      def self.check_cancellation_override(migration, migration_days, user)
        is_minus10 = migration_days >= CANCELLATION_START_DAYS
        is_past_cutoff = migration_days >= cancellation_end_days(user)

        # appointment cancellation is disabled from 10 days before migration until the cutoff
        migration[:cancellation_disabled] = is_minus10 && !is_past_cutoff
      end

      def self.parse_single_migration_entry(entry)
        date_part, facilities_part = entry.split(':', 2)
        return nil if date_part.blank? || facilities_part.blank?

        facilities = parse_facilities_from_string(facilities_part)
        return nil if facilities.empty?

        {
          migration_date: Time.use_zone('Eastern Time (US & Canada)') { Date.parse(date_part.strip) },
          facilities:
        }
      end

      # Parses facilities from bracket-delimited string like "[123,Facility A],[456,Facility B]"
      def self.parse_facilities_from_string(facilities_string)
        facilities_string.scan(/\[([^\]]+)\]/).filter_map do |match|
          parts = match[0].split(',', 2)
          next if parts.length < 2 || parts[0].blank?

          {
            facility_id: parts[0].strip,
            facility_name: parts[1]&.strip || ''
          }
        end
      end
    end
  end
end
