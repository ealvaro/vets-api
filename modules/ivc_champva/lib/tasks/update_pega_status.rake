# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :ivc_champva do
  desc 'Update pega_status for forms with specified UUIDs (auto-detects if none provided)'
  task update_pega_status: :environment do
    form_uuids = ENV['FORM_UUIDS']&.split(/[,\n]/)&.map(&:strip)&.compact_blank || []
    dry_run = ENV['DRY_RUN'] == 'true'
    batch_size = ENV['BATCH_SIZE']&.to_i.then { |v| v&.positive? ? v : nil } || 10

    if form_uuids.empty?
      puts 'No FORM_UUIDS provided — auto-detecting forms with missing pega_status...'
      cleanup_util = IvcChampva::ProdSupportUtilities::MissingStatusCleanup.new
      batches = cleanup_util.get_missing_statuses(silent: true, ignore_last_minute: true)
      form_uuids = batches.keys

      if form_uuids.empty?
        puts 'No forms found with missing pega_status. Nothing to do.'
        next
      end

      puts "Auto-detected #{form_uuids.count} form UUIDs with missing pega_status"
    end

    total_batches = (form_uuids.count.to_f / batch_size).ceil

    puts '=' * 80, 'IVC CHAMPVA PEGA STATUS UPDATE TASK', '=' * 80
    puts "Mode: #{dry_run ? 'DRY RUN (no changes will be made)' : 'LIVE UPDATE'}"
    puts 'New Status: Manually Processed'
    puts "Form UUIDs: #{form_uuids.count} (#{total_batches} batch#{'es' if total_batches > 1} of #{batch_size})"
    puts '-' * 80

    cleanup_util = IvcChampva::ProdSupportUtilities::MissingStatusCleanup.new
    missing_statuses = IvcChampva::ProdSupportUtilities::MissingStatusCleanup::MISSING_PEGA_STATUSES
    total_updated = 0
    total_forms_found = 0
    processed_uuids = []
    failed_uuids = []

    form_uuids.each_slice(batch_size).with_index do |uuid_batch, batch_index|
      if batch_index.positive? && !dry_run
        batch_uuids_so_far = processed_uuids + failed_uuids.map { |f| f[:uuid] }
        verified_count = IvcChampvaForm.where(form_uuid: batch_uuids_so_far, pega_status: 'Manually Processed').count
        missing_remaining = IvcChampvaForm.where(form_uuid: batch_uuids_so_far, pega_status: missing_statuses).count

        puts "\n#{'=' * 80}"
        puts "BATCH #{batch_index + 1}/#{total_batches} ready"
        puts '  Verification of previous batches:'
        puts "    Records confirmed 'Manually Processed': #{verified_count}"
        puts "    Records still missing (nil or 'Submitted'): #{missing_remaining}"
        puts '  Press ENTER to continue, or Ctrl+C to abort...'
        puts '=' * 80
        $stdin.gets
      end

      uuid_batch.each_with_index do |form_uuid, index_in_batch|
        overall_index = (batch_index * batch_size) + index_in_batch
        puts "\n[#{overall_index + 1}/#{form_uuids.count}] Processing UUID: #{form_uuid}"
        begin
          forms = IvcChampvaForm.where(form_uuid:)
          if forms.empty?
            puts "  WARNING: No forms found for UUID: #{form_uuid}"
            failed_uuids << { uuid: form_uuid, reason: 'No forms found' }
            next
          end

          total_forms_found += forms.count
          puts "  Found #{forms.count} form record(s)"
          puts "  Current status distribution: #{forms.group(:pega_status).count}"

          forms_missing_status = forms.where(pega_status: missing_statuses)
          forms_with_status = forms.where.not(pega_status: missing_statuses)

          forms_with_status.each do |f|
            puts "    SKIPPED form ID #{f.id} (#{f.file_name}) - already has status '#{f.pega_status}'"
          end

          updated_count = forms_missing_status.count
          if updated_count.positive?
            if dry_run
              forms_missing_status.each do |f|
                puts "    [DRY RUN] Would update form ID #{f.id} (#{f.file_name}) from '#{f.pega_status || 'nil'}' to \
                'Manually Processed'"
              end
            else
              forms_to_update = forms_missing_status.map do |f|
                { id: f.id, file_name: f.file_name, status: f.pega_status || 'nil' }
              end
              cleanup_util.manually_process_batch(forms_missing_status)
              forms_to_update.each do |f|
                puts "    Updated form ID #{f[:id]} (#{f[:file_name]}) from " \
                     "'#{f[:status]}' to 'Manually Processed'"
              end
            end
          end

          total_updated += updated_count
          processed_uuids << form_uuid
          puts "  Processed #{updated_count} forms for UUID: #{form_uuid}"
        rescue => e
          puts "  ERROR processing UUID #{form_uuid}: #{e.message}"
          Rails.logger.error "IVC CHAMPVA Pega Status Update Error for UUID #{form_uuid}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          failed_uuids << { uuid: form_uuid, reason: e.message }
        end
      end
    end

    # Summary
    puts "\n#{'=' * 80}\nSUMMARY\n#{'=' * 80}"
    puts "Total UUIDs processed: #{processed_uuids.count}/#{form_uuids.count}"
    puts "Total forms found: #{total_forms_found}"
    puts "Total forms #{dry_run ? 'that would be updated' : 'updated'}: #{total_updated}"
    puts "Failed UUIDs: #{failed_uuids.count}"

    if failed_uuids.any?
      puts "\nFAILED UUIDS:"
      failed_uuids.each { |failure| puts "  - #{failure[:uuid]}: #{failure[:reason]}" }
    end
    if processed_uuids.any?
      puts "\nSUCCESSFULLY PROCESSED UUIDS:"
      processed_uuids.each { |uuid| puts "  - #{uuid}" }
    end
    puts "\nTask completed #{dry_run ? '(DRY RUN)' : 'successfully'}!"
  end
end
# rubocop:enable Metrics/BlockLength
