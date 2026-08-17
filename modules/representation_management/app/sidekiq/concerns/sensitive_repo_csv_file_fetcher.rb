# frozen_string_literal: true

require 'octokit'
require 'faraday'
require 'csv'
require 'uri'

# Fetches a CSV file from the va.gov-team-sensitive GHE repo.
# Unlike SensitiveRepoXlsxFileFetcher, this does NOT check for freshness --
# the file is always fetched and returned since re-submitting unchanged data is idempotent.
class SensitiveRepoCsvFileFetcher
  ORG = 'software'
  REPO = 'va.gov-team-sensitive'
  DEFAULT_PATH = 'products/accredited-representation-management/data/representative-contact-updates.csv'
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30

  # @param path [String] Optional custom path within the GHE repo. Defaults to DEFAULT_PATH.
  def initialize(path: DEFAULT_PATH)
    @path = path
  end

  # Fetches and parses the CSV file from the GHE repo
  #
  # @return [CSV::Table, nil] Parsed CSV table with headers, or nil on failure
  def fetch
    setup_octokit_client
    file_info = fetch_csv_file_info
    content = fetch_file_content(file_info.download_url)
    return nil if content.nil?

    CSV.parse(content, headers: true)
  rescue => e
    log_error("Error fetching sensitive repo CSV file: #{e.message}")
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

  def fetch_csv_file_info
    @client.contents("#{ORG}/#{REPO}", path: @path)
  end

  def fetch_file_content(url)
    uri = URI.parse(url)

    unless uri.is_a?(URI::HTTPS)
      log_error("Unexpected non-HTTPS URL for CSV download: #{url}")
      return nil
    end

    response = Faraday.get(uri.to_s) do |req|
      req.options.open_timeout = OPEN_TIMEOUT
      req.options.timeout = READ_TIMEOUT
    end

    return response.body if response.success?

    log_error("Unexpected response downloading CSV file: #{response.status}")
    nil
  rescue URI::InvalidURIError => e
    log_error("Invalid CSV download URL: #{e.message}")
    nil
  rescue Faraday::Error => e
    log_error("Error downloading CSV file: #{e.message}")
    nil
  end

  def log_error(message)
    Rails.logger.error("SensitiveRepoCsvFileFetcher error: #{message}")
  end
end
