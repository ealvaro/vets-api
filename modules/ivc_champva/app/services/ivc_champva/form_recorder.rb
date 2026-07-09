# frozen_string_literal: true

require 'datadog'
require 'ivc_champva/monitor'

module IvcChampva
  class FormRecorder
    ##
    # Initialize a new form recorder for persisting upload records to the database.
    #
    # @param metadata [Hash] The metadata accompanying this form submission
    # @param form_id [String] The ID of the current form, e.g., 'vha_10_10d'
    # @param current_user [User] The current user
    # @param parsed_form_data [Hash, nil] Original form data for encrypted storage
    #
    # @return [IvcChampva::FormRecorder]
    def initialize(metadata, form_id, current_user:, parsed_form_data: nil)
      @metadata = metadata || {}
      @form_id = form_id
      @current_user = current_user
      @parsed_form_data = parsed_form_data
    end

    ##
    # Inserts a record of a particular file and its S3 upload status to the IVC database.
    # The record may later be asynchronously updated via the PEGA callback API.
    #
    # @param file_name [String] Name of file, e.g.,
    #   XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXX_vha_10_10d_supporting_doc-0.pdf
    # @param response_status [Array, nil] Array containing an HTTP status code and an optional error
    #   message string.
    #
    # @return [IvcChampvaForm]
    def insert_form(file_name, response_status)
      Datadog::Tracing.trace('IVC Champva Forms - Insert Form') do
        pega_status = response_status&.first == 200 ? 'Submitted' : nil
        IvcChampvaForm.create!(
          form_uuid: @metadata['uuid'],
          email: validate_email(@metadata&.dig('primaryContactInfo', 'email')),
          first_name: @metadata&.dig('primaryContactInfo', 'name', 'first'),
          last_name: @metadata&.dig('primaryContactInfo', 'name', 'last'),
          submitted_by_icn: @current_user&.icn,
          form_number: @metadata['docType'],
          file_name:,
          s3_status: response_status&.to_s,
          pega_status:,
          request_json: @parsed_form_data&.to_json
        )

        monitor.track_insert_form(@metadata['uuid'], @form_id)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Database Insertion Error for #{@metadata['uuid']}: #{e.message}")
      raise
    end

    ##
    # Inserts DB records for each original file that was combined into the given PDF.
    # These records exist for email counting (file_name contains 'supporting_doc')
    # but have nil s3_status since they were not individually uploaded to S3.
    # No-op when DB insertion is disabled or the file wasn't produced by combining.
    #
    # @param file_path [String] Path to the combined file (key in merge_map)
    # @param merge_map [Hash] Map of combined paths to original file info arrays
    # @param insert_db_row [Boolean] Whether DB insertion is enabled
    def insert_combined_docs(file_path, merge_map, insert_db_row:)
      return unless insert_db_row && merge_map.key?(file_path)

      merge_map[file_path].each do |file_info|
        original_name = File.basename(file_info[:file_path]).gsub('-tmp', '')
        insert_form(original_name, nil)
      end
    end

    ##
    # Inserts a DB record for the combined PDF and shadow records for each original file.
    #
    # @param file_name [String] Name of the combined PDF file
    # @param response_status [Array] Upload response status
    # @param file_paths [Array<String>] Original file paths that were combined
    def insert_combined_pdf_and_docs(file_name, response_status, file_paths)
      Datadog::Tracing.trace('IVC Champva Forms - Insert Combined PDF and Docs') do
        insert_form(file_name, response_status)

        file_paths.each do |file_path|
          next if file_path.blank?

          original_file_name = File.basename(file_path).gsub('-tmp', '')
          insert_form(original_file_name, nil)
        end
      end
    end

    private

    ##
    # Checks provided email against a regex to determine if it is valid, returning nil if not.
    #
    # @param email [String] An email address to validate
    # @return [String, nil] Email is returned if valid, else nil is returned
    def validate_email(email)
      return nil unless email.present? && email.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z]+)*\.[a-z]+\z/i)

      email
    end

    def monitor
      @monitor ||= IvcChampva::Monitor.new
    end
  end
end
