# frozen_string_literal: true

require 'data_migrations/evss_claims_sequence_reset'

namespace :data_migration do
  desc 'Reset the evss_claims primary key sequence to 1'
  task evss_claims_sequence_reset: :environment do
    result = DataMigrations::EVSSClaimsSequenceReset.run

    puts "#{DataMigrations::EVSSClaimsSequenceReset::SEQUENCE} reset"
    puts "  previous value: #{result[:previous_value]}"
    puts "  new value:      #{result[:new_value]}"
    puts "  lowest live id: #{result[:min_id]}"
  end
end
