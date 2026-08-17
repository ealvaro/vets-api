# frozen_string_literal: true

namespace :representation_management do
  namespace :representative_contacts do
    desc 'Fetch representative contact CSV from GHE and POST to GCLAWS RepresentativeContacts API'
    # Usage:
    #   rails representation_management:representative_contacts:bulk_update
    #   rails "representation_management:representative_contacts:bulk_update[path/to/file.csv]"
    task :bulk_update, [:path] => :environment do |_task, args|
      csv_path = args[:path].presence || SensitiveRepoCsvFileFetcher::DEFAULT_PATH

      puts '=== GCLAWS RepresentativeContacts Bulk Update ==='
      puts "  CSV path: #{csv_path}"
      puts

      result = RepresentationManagement::RepresentativeContactsBulkUpdater.new(
        csv_path:
      ).run

      unless result[:success]
        puts "FAILED (status #{result[:status]}): #{result[:error]}"
        exit 1
      end

      puts "Submitted: #{result[:submitted]}"
      puts "Updated:   #{result[:updated]}"
      puts "Rejected:  #{result[:rejected].length}"

      if result[:rejected].any?
        puts
        puts 'Rejected records:'
        result[:rejected].each do |r|
          puts "  ##{r['number']}: #{r['errorMessage']}"
        end
      end

      puts
      puts result[:rejected].empty? ? 'All records updated successfully.' : 'Review rejected records above.'
    rescue => e
      puts "ERROR: #{e.class}: #{e.message}"
      puts e.backtrace.first(10).join("\n") if e.backtrace
      exit 1
    end
  end
end
