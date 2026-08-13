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
      @merge_map = {}
      @parsed_form_data = if options[:parsed_form_data] && Flipper.enabled?(:champva_store_request_json, @current_user)
                            options[:parsed_form_data]
                          end
      @form_recorder = IvcChampva::FormRecorder.new(
        @metadata, @form_id,
        current_user: @current_user,
        parsed_form_data: @parsed_form_data
      )
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
        apply_document_combining
        handle_iterative_uploads
      end
    end

    ##
    # Pre-processes files through DocumentMerger to combine eligible documents by type.
    # Updates @file_paths, @metadata['attachment_ids'], and @merge_map in place.
    # No-op when feature flags are off or no merge rules match the current form.
    def apply_document_combining
      merge_result = IvcChampva::DocumentMerger.new(
        @form_id, @file_paths, @metadata['attachment_ids'],
        @current_user, { uuid: @metadata['uuid'] }
      ).process
      @file_paths = merge_result[:merged_file_paths]
      @metadata['attachment_ids'] = merge_result[:updated_attachment_ids]
      @merge_map = merge_result[:merge_map]
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
        response_status = upload(file_name, file_path,
                                 IvcChampva::DataTransformations.metadata_for_s3(@metadata, attachment_id, file_path))
        # When bypassing, VES/OHI JSON files are ingested by VES (not Pega) and must not be
        # persisted, otherwise they linger without a Pega status and skew reconciliation.
        skip_ves_json = bypass_ves_json_flag && IvcChampva::FileNaming.ves_json?(file_name)
        @form_recorder.insert_form(file_name, response_status) if @insert_db_row && !skip_ves_json

        @form_recorder.insert_combined_docs(file_path, @merge_map, insert_db_row: @insert_db_row)

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
          IvcChampva::PdfCombiner.combine(combined_pdf_path, @file_paths.compact)
        end

        [upload_combined_pdf(combined_pdf_path)]
      rescue => e
        Rails.logger.error("FMP Single File Upload: Error during PDF combining for submission #{@metadata['uuid']}:" \
                           "#{e.message}")
        raise
      ensure
        FileUtils.rm_f(combined_pdf_path)
      end
    end

    def upload_combined_pdf(combined_pdf_path)
      file_name = File.basename(combined_pdf_path)

      Rails.logger.info "IVC Champva Forms - FileUploader: Starting upload with attachment_id: #{
        sanitize_for_logging(@form_id)
      }"

      response_status = upload(file_name, combined_pdf_path,
                               IvcChampva::DataTransformations.metadata_for_s3(@metadata, @form_id))

      @form_recorder.insert_combined_pdf_and_docs(file_name, response_status, @file_paths) if @insert_db_row

      response_status
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
