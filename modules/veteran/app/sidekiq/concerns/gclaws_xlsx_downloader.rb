# frozen_string_literal: true

require_relative './sensitive_repo_xlsx_file_fetcher'

# Shared concern for downloading XLSX files.
# Including classes must define a `log_error(message)` method.
module GCLAWSXlsxDownloader
  extend ActiveSupport::Concern

  private

  # Downloads the accreditation XLSX file content from the requested source and yields it.
  #
  # Supported sources:
  # - 'gclaws'         (default)
  # - 'sensitive_repo' (manual fail-safe path)
  #
  # @param source [String]
  # @yield [String] the binary file content
  # @raise [StandardError] when the download fails
  def with_xlsx_file_content(source: 'gclaws')
    file_content =
      case source
      when 'gclaws'
        fetch_gclaws_xlsx_file_content
      when 'sensitive_repo'
        fetch_sensitive_repo_xlsx_file_content
      else
        raise ArgumentError, "Unsupported XLSX source: #{source}"
      end

    yield file_content
  end

  def fetch_gclaws_xlsx_file_content
    RepresentationManagement::GCLAWS::XlsxClient.download_accreditation_xlsx do |result|
      return File.binread(result[:file_path]) if result[:success]

      error_msg = "GCLAWS download failed: #{result[:error]} (status: #{result[:status]})"
      log_error(error_msg)
      raise StandardError, error_msg
    end
  end

  def fetch_sensitive_repo_xlsx_file_content
    file_content = SensitiveRepoXlsxFileFetcher.new.fetch

    if file_content.blank?
      error_msg = 'Sensitive repo XLSX fetch failed or no fresh file was available'
      log_error(error_msg)
      raise StandardError, error_msg
    end

    file_content
  end
end
