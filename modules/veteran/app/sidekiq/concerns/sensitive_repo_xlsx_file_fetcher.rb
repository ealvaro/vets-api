# frozen_string_literal: true

require 'octokit'
require 'faraday'
require 'uri'
require 'logging/helper/data_scrubber'

# Fetches the Trexler XLSX file from the sensitive repo.
# Only returns content if the file was committed within the last 24 hours.
class SensitiveRepoXlsxFileFetcher
  ORG = 'software'
  REPO = 'va.gov-team-sensitive'
  PATH = 'products/accredited-representation-management/data/rep-org-addresses.xlsx'
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def fetch
    setup_octokit_client
    return nil unless file_recently_updated?

    file_info = fetch_xlsx_file_info
    fetch_file_content(file_info.download_url)
  rescue => e
    log_error("Error fetching sensitive repo XLSX file: #{e.message}")
    nil
  end

  private

  def setup_octokit_client
    token = github_access_token
    raise ArgumentError, 'GitHub access token is missing or invalid' if token.blank?

    @client = Octokit::Client.new(access_token: token, api_endpoint: 'https://api.va.ghe.com')
  end

  def github_access_token
    Settings.xlsx_file_fetcher.github_access_token.to_s.strip
  end

  def fetch_xlsx_file_info
    @client.contents("#{ORG}/#{REPO}", path: PATH)
  end

  def file_recently_updated?
    commits = @client.commits("#{ORG}/#{REPO}", path: PATH)
    return false if commits.empty?

    last_commit_date = commits.first.commit.author.date
    last_commit_date > 24.hours.ago
  rescue Octokit::Error => e
    log_error("Error fetching sensitive repo XLSX commits: #{e.message}")
    false
  end

  def fetch_file_content(url)
    uri = URI.parse(url)

    unless uri.is_a?(URI::HTTPS)
      log_error("Unexpected non-HTTPS URL for XLSX download: #{url}")
      return nil
    end

    response = Faraday.get(uri.to_s) do |req|
      req.options.open_timeout = OPEN_TIMEOUT
      req.options.timeout = READ_TIMEOUT
    end

    return response.body if response.success?

    log_error("Unexpected response downloading XLSX file: #{response.status}")
    nil
  rescue URI::InvalidURIError => e
    log_error("Invalid XLSX download URL: #{e.message}")
    nil
  rescue Faraday::Error => e
    log_error("Error downloading XLSX file: #{e.message}")
    nil
  end

  def log_error(message)
    Rails.logger.error("SensitiveRepoXlsxFileFetcher error: #{scrub_pii(message)}")
  end

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
