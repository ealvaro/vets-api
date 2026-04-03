# frozen_string_literal: true

# Shared concern for downloading XLSX files via the GCLAWS XlsxClient.
# Including classes must define a `log_error(message)` method.
module GCLAWSXlsxDownloader
  extend ActiveSupport::Concern

  private

  # Downloads the accreditation XLSX file and yields its binary content to the caller's block.
  # On failure, logs the error and raises so Sidekiq can retry.
  #
  # @yield [String] the binary file content
  # @raise [StandardError] when the download fails
  def with_xlsx_file_content
    RepresentationManagement::GCLAWS::XlsxClient.download_accreditation_xlsx do |result|
      if result[:success]
        yield File.binread(result[:file_path])
      else
        error_msg = "GCLAWS download failed: #{result[:error]} (status: #{result[:status]})"
        log_error(error_msg)
        raise error_msg
      end
    end
  end
end
