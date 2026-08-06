# frozen_string_literal: true

require 'pega_api/client'

# Helper class to retrieve PDI numbers from the Pega reporting API for one or more form UUIDs.
#
# Pega recently added the PDI number to their reporting API, which lets us look up PDI numbers
# programmatically instead of asking their team to collect them by hand. There is no swagger/docs
# for the response body, but the PDI number is surfaced under the "BatchID" key (confirmed via the
# staging console, e.g. "07/30/2026-VA1785374681051-001-001"). The full row is still logged/printed
# for each UUID so a gov engineer has the surrounding context alongside the PDI.
class PegaPdiRetriever
  # Report key that holds the PDI number (confirmed via staging console — no swagger exists).
  PDI_FIELD = 'BatchID'

  # Padding applied on either side of the anchor date to keep the reporting-API query to a day or
  # two. The Pega reporting endpoint requires a date range and struggles with very large windows,
  # so we deliberately avoid scanning years of data.
  DATE_PADDING = 1.day

  def initialize
    @pega_api_client = IvcChampva::PegaApi::Client.new
    @results = []
    @not_found = []
    @api_errors = []
  end

  def run
    puts '=' * 80
    puts 'IVC CHAMPVA PEGA PDI RETRIEVAL TASK'
    puts '=' * 80

    uuids = form_uuids
    return if uuids.empty?

    puts "UUIDs to look up: #{uuids.count}"
    puts '-' * 80

    uuids.each_with_index do |uuid, index|
      puts "\n[#{index + 1}/#{uuids.count}] Looking up UUID: #{uuid}"
      process_uuid(uuid)
    end

    print_summary(uuids)
    puts "\nTask completed!"
  end

  private

  def form_uuids
    raw = ENV['UUIDS'].presence || ENV.fetch('FORM_UUIDS', nil)

    if raw.blank?
      puts 'ERROR: No UUIDs provided. Pass one or more via UUIDS="uuid1,uuid2".'
      raise 'No UUIDs provided'
    end

    uuids = raw.split(/[,\n]/).map(&:strip).compact_blank

    if uuids.empty?
      puts 'ERROR: No valid UUIDs provided'
      raise 'No valid UUIDs provided'
    end

    uuids
  end

  def process_uuid(uuid)
    reports = fetch_reports(uuid)
    if reports.nil?
      @not_found << uuid
      return
    end

    matching = filter_matching_reports(reports, uuid)
    if matching.empty?
      puts '  No Pega report rows found for this UUID.'
      @not_found << uuid
      return
    end

    puts "  Found #{matching.count} Pega report row(s):"
    matching.each { |row| record_and_print_row(uuid, row) }
  rescue IvcChampva::PegaApi::PegaApiError => e
    handle_error(uuid, e, 'PegaApiError')
  rescue => e
    handle_error(uuid, e, 'Unexpected error')
  end

  # Anchors the reporting-API query on the local record's created_at (± DATE_PADDING). This keeps
  # the date range to a day or two — same approach as PegaApi::Client#record_has_matching_report —
  # instead of scanning a huge window that the reporting API can choke on. When there is no local
  # record we can't infer the submission date, so we require explicit DATE_START/DATE_END overrides
  # rather than guessing at a large range.
  def fetch_reports(uuid)
    date_start, date_end = date_window(uuid)
    return nil if date_start.nil? || date_end.nil?

    puts "  Querying Pega report for #{date_start} – #{date_end}"
    @pega_api_client.get_report(date_start, date_end, '', uuid) || []
  end

  def date_window(uuid)
    override_start = ENV['DATE_START'].presence
    override_end = ENV['DATE_END'].presence
    return [override_start, override_end] if override_start && override_end

    record = IvcChampvaForm.where(form_uuid: uuid).order(:created_at).first
    if record.nil?
      puts '  No local IvcChampvaForm record found and no DATE_START/DATE_END provided; skipping.'
      puts '  Re-run with DATE_START="MM/DD/YYYY" DATE_END="MM/DD/YYYY" to look this UUID up.'
      return [nil, nil]
    end

    [(record.created_at - DATE_PADDING).strftime('%m/%d/%Y'),
     (record.created_at + DATE_PADDING).strftime('%m/%d/%Y')]
  end

  # Pega truncates the UUID in report rows (e.g. "9a0e9790-...-121a0e+"), so we match on the
  # non-truncated prefix. Rows without a UUID are kept so nothing is silently dropped.
  def filter_matching_reports(reports, uuid)
    return [] unless reports.is_a?(Array)

    reports.select do |row|
      report_uuid = row['UUID'].to_s.delete('+')
      report_uuid.blank? || uuid.start_with?(report_uuid) || report_uuid == uuid
    end
  end

  def record_and_print_row(uuid, row)
    pdi = row[PDI_FIELD]

    @results << { uuid:, pdi:, row: }

    puts "    PEGA Case ID: #{row['PEGA Case ID'] || 'N/A'}"
    if pdi.present?
      puts "    PDI (#{PDI_FIELD}): #{pdi}"
    else
      puts "    PDI: no '#{PDI_FIELD}' field on this row — see full row below."
    end
    puts "    Full row: #{row.to_json}"
    Rails.logger.info("IVC CHAMPVA Pega PDI Retrieval - UUID #{uuid} row: #{row.to_json}")
  end

  def handle_error(uuid, error, error_type)
    @api_errors << { uuid:, error: error.message }
    puts "  #{error_type}: #{error.message}"
    Rails.logger.error("IVC CHAMPVA get_pega_pdi - #{error_type} for UUID #{uuid}: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n")) if error_type == 'Unexpected error'
  end

  def print_summary(uuids)
    puts "\n#{'=' * 80}\nSUMMARY\n#{'=' * 80}"
    puts "UUIDs looked up: #{uuids.count}"
    puts "UUIDs with report rows: #{@results.map { |r| r[:uuid] }.uniq.count}"
    puts "UUIDs with no report rows: #{@not_found.count}"
    puts "API errors encountered: #{@api_errors.count}"

    print_pdi_table
    print_not_found
    print_errors
  end

  def print_pdi_table
    return if @results.empty?

    puts "\n#{'-' * 80}\nPDI NUMBERS\n#{'-' * 80}"
    puts format('%-38<uuid>s %-14<case_id>s %<pdi>s',
                uuid: 'FORM_UUID', case_id: 'PEGA_CASE_ID', pdi: "PDI (#{PDI_FIELD})")
    puts '-' * 80

    @results.each do |result|
      pdi = result[:pdi].presence || "UNKNOWN (no #{PDI_FIELD}; see full row above)"
      puts format('%-38<uuid>s %-14<case_id>s %<pdi>s',
                  uuid: result[:uuid], case_id: result[:row]['PEGA Case ID'] || 'N/A', pdi:)
    end
  end

  def print_not_found
    return if @not_found.empty?

    puts "\n#{'-' * 80}\nUUIDs WITH NO REPORT ROWS\n#{'-' * 80}"
    @not_found.each { |uuid| puts "  - #{uuid}" }
  end

  def print_errors
    return if @api_errors.empty?

    puts "\n#{'-' * 80}\nAPI ERRORS\n#{'-' * 80}"
    @api_errors.each { |error| puts "  - #{error[:uuid]}: #{error[:error]}" }
  end
end

namespace :ivc_champva do
  desc 'Retrieve Pega PDI number(s) for one or more form UUIDs (UUIDS="uuid1,uuid2")'
  task get_pega_pdi: :environment do
    PegaPdiRetriever.new.run
  end
end
