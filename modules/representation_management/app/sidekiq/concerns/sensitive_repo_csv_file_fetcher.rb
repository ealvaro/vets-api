# frozen_string_literal: true

require 'octokit'
require 'faraday'
require 'csv'
require 'uri'
require 'github/installation_token_generator'

# Fetches a CSV file from the va.gov-team-sensitive GHE repo.
# Unlike SensitiveRepoXlsxFileFetcher, this does NOT check for freshness --
# the file is always fetched and returned since re-submitting unchanged data is idempotent.
class SensitiveRepoCsvFileFetcher
  API_ENDPOINT = 'https://api.va.ghe.com'
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
    endpoint = api_endpoint
    @client = Octokit::Client.new(access_token: github_access_token, api_endpoint: endpoint)
  end

  def github_access_token
    generator = Github::InstallationTokenGenerator.new(
      app_id: github_app_id,
      private_key: github_private_key,
      api_endpoint:
    )

    generator.generate(org: github_org)
  end

  def github_app_id
    value = Settings.xlsx_file_fetcher.github_app.app_id.to_s.strip
    raise ArgumentError, 'GitHub app_id is missing or invalid' if value.blank?

    value
  end

  def github_private_key
    value = Settings.xlsx_file_fetcher.github_app.private_key.to_s.strip
    raise ArgumentError, 'GitHub private_key is missing or invalid' if value.blank?

    value
  end

  def github_org
    value = Settings.xlsx_file_fetcher.github_app.org.to_s.strip
    raise ArgumentError, 'GitHub org is missing or invalid' if value.blank?

    value
  end

  def github_repo
    value = Settings.xlsx_file_fetcher.github_app.repo.to_s.strip
    raise ArgumentError, 'GitHub repo is missing or invalid' if value.blank?

    value
  end

  def api_endpoint
    value = Settings.xlsx_file_fetcher.github_app.base_uri.to_s.strip
    return API_ENDPOINT if value.blank?

    value
  end

  def fetch_csv_file_info
    @client.contents(github_repo, path: @path)
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
