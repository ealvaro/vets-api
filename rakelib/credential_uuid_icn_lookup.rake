# frozen_string_literal: true

require 'csv'

desc 'Enrich credential UUID CSV with ICN via UserVerification lookups'
namespace :credential_uuid do
  task :enrich_with_icn, [:file_path] => :environment do |_, args|
    result = EnrichCredentialUUIDWithICN.new(args[:file_path]).perform
    puts "\n\nOutput file: #{result}"
  end
end

class EnrichCredentialUUIDWithICN
  TYPE_TO_COLUMN = {
    'idme' => :idme_uuid,
    'logingov' => :logingov_uuid,
    'mhv' => :mhv_uuid,
    'clear' => :clear_uuid
  }.freeze

  def initialize(file_path)
    @file_path = file_path
    @logger = Logger.new($stdout)
    @stats = {
      rows_read: 0,
      rows_enriched: 0,
      rows_not_found: 0
    }
  end

  def perform
    log_info('Starting credential UUID enrichment')
    log_info("Input: #{@file_path}")

    validate_input_file
    output_path = generate_output_path
    credentials_by_type = extract_credentials_by_type
    load_user_verifications_for_types(credentials_by_type)
    enrich_and_write(output_path)
    log_summary(output_path)

    output_path
  rescue => e
    log_error("Task failed: #{e.message}\n#{e.backtrace.join("\n")}")
    raise
  end

  private

  def validate_input_file
    raise 'File path cannot be blank' if @file_path.blank?
    raise "File not found: #{@file_path}" unless File.exist?(@file_path)
    raise "Input path is not a file: #{@file_path}" unless File.file?(@file_path)
  end

  def generate_output_path
    input_file = Pathname.new(@file_path)
    input_file.parent.join("#{input_file.basename('.csv')}_enriched.csv").to_s
  end

  def extract_credentials_by_type
    by_type = {}

    CSV.foreach(@file_path, headers: true) do |row|
      credential_uuid = row['Credential UUID']&.strip
      credential_type = row['Credential Type']&.strip
      next if credential_uuid.blank? || credential_type.blank?

      cred_type_key = credential_type&.downcase
      by_type[cred_type_key] ||= Set.new
      by_type[cred_type_key].add(credential_uuid)
    end

    total = by_type.values.sum(&:size)
    type_breakdown = by_type.map { |t, uuids| "#{t}: #{uuids.size}" }.join(', ')
    log_info("Found #{total} credential UUIDs (#{type_breakdown})")
    by_type
  end

  def load_user_verifications_for_types(by_type)
    log_info('Building UUID to ICN lookup...')
    @uuid_to_icn = {}

    by_type.each do |cred_type, uuids|
      next if uuids.empty?

      column = TYPE_TO_COLUMN[cred_type]
      unless column
        log_error("Unknown credential type '#{cred_type}', skipping")
        next
      end

      uuids.each_slice(5000) do |uuid_batch|
        UserVerification.where(column => uuid_batch)
                        .left_joins(:user_account)
                        .pluck(column, 'user_accounts.icn')
                        .each do |uuid, icn|
          @uuid_to_icn[[cred_type, uuid]] = icn if uuid.present?
        end
      end
    end

    log_info("Loaded #{@uuid_to_icn.size} credential type+UUID to ICN mappings")
  end

  def enrich_and_write(output_path)
    log_info("Reading from: #{@file_path}")
    log_info("Writing to: #{output_path}")

    CSV.open(output_path, 'w') do |out_csv|
      # Write header
      out_csv << ['ICN', 'Credential Type', 'Credential UUID']

      CSV.foreach(@file_path, headers: true) do |row|
        @stats[:rows_read] += 1

        credential_uuid = row['Credential UUID']&.strip
        credential_type = row['Credential Type']&.strip

        next if credential_uuid.blank? || credential_type.blank?

        icn = @uuid_to_icn[[credential_type&.downcase, credential_uuid]]

        if icn.present?
          @stats[:rows_enriched] += 1
        else
          @stats[:rows_not_found] += 1
        end

        out_csv << [icn, credential_type, credential_uuid]

        # Progress output every 1000 rows
        log_progress("Processed #{@stats[:rows_read]} rows...") if (@stats[:rows_read] % 1000).zero?
      end
    end
  end

  def log_summary(output_path)
    log_info('=' * 60)
    log_info('Enrichment Complete')
    log_info('=' * 60)
    log_info("Rows read: #{@stats[:rows_read]}")
    log_info("Rows enriched (ICN found): #{@stats[:rows_enriched]}")
    log_info("Rows not found (ICN null): #{@stats[:rows_not_found]}")
    log_info("Output file: #{output_path}")
  end

  def log_info(message)
    @logger.info(message)
  end

  def log_progress(message)
    @logger.info(message)
  end

  def log_error(message)
    @logger.error(message)
  end
end
