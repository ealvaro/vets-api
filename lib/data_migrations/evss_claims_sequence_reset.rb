# frozen_string_literal: true

module DataMigrations
  # Resets the evss_claims primary key sequence back to 1.
  #
  # This is safe because every live row sits near the top of the integer range. The
  # lowest id in production is 1,590,858,608, leaving ~1.59B free values beneath it
  #
  module EVSSClaimsSequenceReset
    TABLE = 'evss_claims'
    SEQUENCE = 'evss_claims_id_seq'

    # The lowest live id must leave at least this many free values beneath it before
    # the sequence is reset, so it cannot climb back into occupied ids.
    REQUIRED_CLEARANCE = 1_000_000_000

    module_function

    def run
      min_id = connection.select_value("SELECT min(id) FROM #{TABLE}")
      previous_value = connection.select_value("SELECT last_value FROM #{SEQUENCE}")

      unless min_id && min_id > REQUIRED_CLEARANCE
        raise "Refusing to reset #{SEQUENCE}: lowest live id is #{min_id.inspect}, which " \
              "does not clear the required #{REQUIRED_CLEARANCE} free values. This task " \
              'is intended for production only.'
      end

      connection.execute("ALTER SEQUENCE #{SEQUENCE} RESTART WITH 1")
      new_value = connection.select_value("SELECT last_value FROM #{SEQUENCE}")

      Rails.logger.info(
        'Reset evss_claims id sequence',
        { sequence: SEQUENCE, previous_value:, new_value:, min_id: }
      )

      { previous_value:, new_value:, min_id: }
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
