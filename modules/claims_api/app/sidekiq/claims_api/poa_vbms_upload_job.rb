# frozen_string_literal: true

require 'bd/bd'

module ClaimsApi
  class PoaVBMSUploadJob < ClaimsApi::ServiceBase
    # Uploads a 21-22 or 21-22a form for a given POA request through Benefits Documents.
    # If successfully uploaded, it queues a job to update the POA code in BGS, as well.
    #
    # @param power_of_attorney_id [String] Unique identifier of the submitted POA
    def perform(power_of_attorney_id, action = 'post')
      power_of_attorney = ClaimsApi::PowerOfAttorney.find(power_of_attorney_id)
      # update the POA assignment before uploading to Benefits Documents
      run_update_poa_job(power_of_attorney)

      uploader = ClaimsApi::PowerOfAttorneyUploader.new(power_of_attorney_id)
      uploader.retrieve_from_store!(power_of_attorney.file_data['filename'])
      file_path = fetch_file_path(uploader)
      benefits_doc_upload(poa: power_of_attorney, pdf_path: file_path, action:, doc_type: 'L075')
    rescue Errno::ENOENT
      rescue_file_not_found(power_of_attorney)
      raise
    rescue => e
      rescue_generic_errors(power_of_attorney, e)
      raise
    end

    def fetch_file_path(uploader)
      return uploader.file.file unless Settings.evss.s3.uploads_enabled

      stream = URI.parse(uploader.file.url).open
      # stream could be a Tempfile or a StringIO https://stackoverflow.com/a/23666898
      stream.try(:path) || stream_to_temp_file(stream).path
    end

    def stream_to_temp_file(stream, close_stream: true)
      file = Tempfile.new
      file.binmode
      file.write stream.read
      file
    ensure
      file.flush
      file.close
      stream.close if close_stream
    end

    private

    def benefits_doc_upload(poa:, pdf_path:, doc_type:, action:)
      PoaDocumentService.new.create_upload(poa:, pdf_path:, action:, doc_type:)
    end

    # run job for dependent if dependent is in the auth headers
    # running sync to ensure that the POA is updated before the PDF is uploaded
    def run_update_poa_job(power_of_attorney)
      if dependent_filing?(power_of_attorney)
        ClaimsApi::PoaAssignDependentClaimantJob.new.perform(power_of_attorney.id)
      else
        ClaimsApi::PoaUpdater.new.perform(power_of_attorney.id)
      end
    end
  end
end
