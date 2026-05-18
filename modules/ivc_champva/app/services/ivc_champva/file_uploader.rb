# frozen_string_literal: true

require 'datadog'
require 'ivc_champva/monitor'

module IvcChampva
  class FileUploader
    attr_reader :metadata

    ##
    # Initialize new file uploader
    #
    # @param [String] form_id The ID of the current form, e.g., 'vha_10_10d' (see FORM_NUMBER_MAP)
    # @param [Hash] metadata The metadata accompanying this form submission (see IvcChampva::VHA1010d.metadata example)
    # @param [Array] file_paths List of local file paths of all attachments to be uploaded
    # @param [Hash] options Optional arguments:
    #   - :insert_db_row [Boolean] whether to record the uploads and S3 responses in the database (default: false)
    #   - :current_user [User] The current user, used for feature flags
    #   - :parsed_form_data [Hash] Original form data for storage (when feature flag enabled)
    #
    # @return [IvcChampva::FileUploader]
    #
    def initialize(form_id, metadata, file_paths, **options)
      @form_id = form_id
      @metadata = metadata || {}
      @file_paths = Array(file_paths)
      @insert_db_row = options.fetch(:insert_db_row, false)
      @current_user = options[:current_user]
      @parsed_form_data = if options[:parsed_form_data] && Flipper.enabled?(:champva_store_request_json, @current_user)
                            options[:parsed_form_data]
                          end
    end

    ##
    # Coordinates uploading files to S3, checking response statuses, and producing the
    # metadata JSON that alerts the PEGA lambda to ingest the uploaded submission.
    #
    # The return value reflects whether or not all files were successfully uploaded.
    #
    # If successful, it will return an array containing a single HTTP status code and an
    # optional error message, e.g. [200, nil] | [400, 'No such file']
    #
    # If any uploads yield non-200 statuses when submitted to S3, it raise a StandardError.
    #
    # @return [Array<Integer, String>] An array with a status code and an optional error message string.
    def handle_uploads
      Datadog::Tracing.trace('IVC Champva Forms - FileUploader Handle Uploads') do
        results = handle_combined_or_iterative_uploads

        s3_err = nil
        all_success = results.all? do |(status, err)|
          s3_err = err if err # Collect last error present for logging purposes
          status == 200
        end

        if all_success
          if bypass_metadata_json?
            [200, nil]
          else
            generate_and_upload_meta_json
          end
        else
          monitor.track_s3_upload_error(@metadata['uuid'], s3_err)
          # Stop this submission in its tracks - entries will still be added to database
          # for these files, but user will see error on the FE saying submission failed.
          raise StandardError, "IVC ChampVa Forms - failed to upload all documents for submission: #{s3_err}"
        end
      end
    end

    private

    def bypass_metadata_json?
      return false if Flipper.enabled?(:form1010d_enhanced_flow_enabled, @current_user) &&
                      @metadata['docType']&.start_with?('10-10D-SUPPLEMENTAL')

      Flipper.enabled?(:champva_bypass_metadata_json_file_for_1010d, @current_user) && @form_id == 'vha_10_10d'
    end

    ##
    # Determines whether to handle uploads iteratively or as a combined PDF based on form type and feature flag.
    def handle_combined_or_iterative_uploads
      if Flipper.enabled?(:champva_fmp_single_file_upload, @current_user) && @form_id == 'vha_10_7959f_2'
        handle_combined_uploads
      else
        handle_iterative_uploads
      end
    end

    ##
    # Handles iterative uploading of files for standard claims (non-FMP or when feature flag is off)
    #
    # @return [Array<Array<Integer, String>>] Array of arrays containing status codes and error messages
    def handle_iterative_uploads
      bypass_ves_json_flag = Flipper.enabled?(:champva_bypass_persisting_ves_json_to_database, @current_user)
      @metadata['attachment_ids'].zip(@file_paths).map do |attachment_id, file_path|
        next if file_path.blank?

        Rails.logger.info "IVC Champva Forms - FileUploader: Starting upload with attachment_id: #{
          sanitize_for_logging(attachment_id)
        }"

        file_name = File.basename(file_path).gsub('-tmp', '')
        response_status = upload(file_name, file_path, metadata_for_s3(attachment_id, file_path))
        if bypass_ves_json_flag
          insert_form(file_name, response_status) if @insert_db_row && file_name.exclude?('_ves.json')
        else
          insert_form(file_name, response_status) if @insert_db_row # rubocop:disable Style/IfInsideElse
        end

        response_status
      end.compact
    end

    ##
    # Handles combining multiple PDFs into a single PDF for FMP claims and uploads the result to S3
    #
    # @return [Array<Array<Integer, String>>] Array of arrays containing status codes and error messages
    def handle_combined_uploads
      combined_pdf_path = File.join('tmp/', "#{@metadata['uuid']}_#{@form_id}#{IvcChampva::FileNaming::COMBINED_PDF_SUFFIX}")

      begin
        Datadog::Tracing.trace('IVC Champva Forms - Combine All PDFs into a Single File') do
          IvcChampva::PdfCombiner.combine(combined_pdf_path, @file_paths.compact, @current_user)
        end

        attachment_id = @form_id
        file_name = File.basename(combined_pdf_path)

        Rails.logger.info "IVC Champva Forms - FileUploader: Starting upload with attachment_id: #{
          sanitize_for_logging(attachment_id)
        }"

        # Upload the combined PDF
        response_status = upload(file_name, combined_pdf_path, metadata_for_s3(attachment_id))

        insert_combined_pdf_and_docs(file_name, response_status) if @insert_db_row

        [response_status]
      rescue => e
        Rails.logger.error("FMP Single File Upload: Error during PDF combining for submission #{@metadata['uuid']}:" \
                           "#{e.message}")
        raise
      ensure
        FileUtils.rm_f(combined_pdf_path)
      end
    end

    def insert_combined_pdf_and_docs(file_name, response_status)
      Datadog::Tracing.trace('IVC Champva Forms - Insert Combined PDF and Docs') do
        insert_form(file_name, response_status)

        @file_paths.each do |file_path|
          next if file_path.blank?

          original_file_name = File.basename(file_path).gsub('-tmp', '')
          insert_form(original_file_name, response_status)
        end
      end
    end

    ##
    # Creates a modified metadata hash to be attached to individual files upon upload to S3.
    # When per_file_metadata is present and a file_path is provided, merges any
    # file-specific metadata overrides for the current file.
    #
    # @param [Integer, String] attachment_id Either a number or a string describing the file,
    # e.g., 'Social Security card'
    # @param [String, nil] file_path Optional file path for per-file metadata lookup
    #
    # @return [Hash] modified metadata object
    def metadata_for_s3(attachment_id, file_path = nil)
      key = attachment_id.is_a?(Integer) ? 'claim_id' : 'attachment_id'
      result = @metadata.except('primaryContactInfo', 'attachment_ids', 'additional_file_metadata')
                        .merge({ key => attachment_id.to_s })

      if file_path && @metadata['additional_file_metadata']
        file_name = File.basename(file_path).gsub('-tmp', '')
        file_overrides = @metadata['additional_file_metadata'][file_name]
        result.merge!(file_overrides) if file_overrides
      end

      result
    end

    ##
    # Inserts a record of a particular file and its S3 upload status to the IVC database.
    # The record may later be asyncronously updated via the PEGA callback API.
    #
    # @param [String] file_name Name of file, e.g.,
    # XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXX_vha_10_10d_supporting_doc-0.pdf
    # @param [String] response_status Stringified array containing an HTTP status code and an optional error
    # message string.
    #
    # @return [IvcChampvaForm]
    def insert_form(file_name, response_status)
      Datadog::Tracing.trace('IVC Champva Forms - Insert Form') do
        pega_status = response_status.first == 200 ? 'Submitted' : nil
        IvcChampvaForm.create!(
          form_uuid: @metadata['uuid'],
          email: validate_email(@metadata&.dig('primaryContactInfo', 'email')),
          first_name: @metadata&.dig('primaryContactInfo', 'name', 'first'),
          last_name: @metadata&.dig('primaryContactInfo', 'name', 'last'),
          submitted_by_icn: @current_user&.icn,
          form_number: @metadata['docType'],
          file_name:,
          s3_status: response_status.to_s,
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
    # Creates metadata JSON for submitted files from class instance metadata. This metadata JSON
    # is what the downstream PEGA service uses to trigger a lambda job that ingests the uploads.
    # See IvcChampva::VHA1010d.metadata for an example of metadata.
    #
    # @return [Array<Integer, String, nil>] a two-item list containing an HTTP response code and an error or nil. e.g.,
    # [200, nil]
    # [400, '... No such file or directory ...']
    # [500, 'Unexpected response from S3 upload']
    def generate_and_upload_meta_json
      Datadog::Tracing.trace('IVC Champva Forms - Generate and Upload metadata.json') do
        uuid = @metadata['uuid']
        Rails.logger.info "IVC Champva Forms - FileUploader: Writing metadata.json file for form_uuid #{uuid}"

        meta_file_name = "#{uuid}_#{@form_id}_metadata.json"
        meta_file_path = "tmp/#{meta_file_name}"
        File.write(meta_file_path, @metadata.to_json)

        Rails.logger.info 'IVC Champva Forms - FileUploader: Starting upload of metadata json'
        meta_upload_status, meta_upload_error_message = upload(meta_file_name, meta_file_path)

        if meta_upload_status == 200
          FileUtils.rm_f(meta_file_path)
          [meta_upload_status, nil]
        else
          [meta_upload_status, meta_upload_error_message]
        end
      end
    end

    ##
    # Uploads a file to the S3 bucket configured in IvcChampva::FileUploader.client
    #
    # @param [String] file_name Name of file to be uploaded
    # @param [String] file_path Path of file to be uploaded
    # @param [Hash] metadata Optional file metadata hash to be associated with the file in S3
    #
    # @return [Array<Integer, String>] List containing either a single HTTP response code or a reponse
    # code and an error message.
    def upload(file_name, file_path, metadata = {})
      Datadog::Tracing.trace('IVC Champva Forms - Upload a File') do
        case client.put_object(file_name, file_path, metadata)
        in { success: true }
          [200]
        in { success: false, error_message: error_message }
          [400, error_message]
        else
          [500, 'Unexpected response from S3 upload']
        end
      end
    end

    ##
    # Provides or creates current instance method S3 client
    #
    # @return [IvcChampva::S3]
    def client
      @client ||= IvcChampva::S3.new(
        region: Settings.ivc_forms.s3.region,
        bucket: Settings.ivc_forms.s3.bucket
      )
    end

    ##
    # Checks provided email against a regex to determine if it is valid, returning nil if not.
    #
    # @param [String] email An email address to validate
    #
    # @return [String, nil] Email is returned if valid, else nil is returned
    def validate_email(email)
      return nil unless email.present? && email.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z]+)*\.[a-z]+\z/i)

      email
    end

    # Returns sanitized string that is safe for logging
    # @param [String, nil] value to sanitize
    # @return [String, nil] Sanitized value
    def sanitize_for_logging(value)
      (value || '').to_s.gsub(/[^a-zA-Z0-9\s_-]/, '').slice(0, 100)
    end

    ##
    # retreive a monitor for tracking
    #
    # @return [IvcChampva::Monitor]
    #
    def monitor
      @monitor ||= IvcChampva::Monitor.new
    end
  end
end
