# frozen_string_literal: true

require 'json'

# Evaluates CI / Docker-build logs for cert install or verify failures and writes
# Slack / GitHub Actions outputs. No Rails or gem dependencies (bare runner).
#
#   CI_LOG_FILE=build.log WORKFLOW_RUN_URL=... ruby cert_error_alert.rb
class CertErrorAlert
  MAX_MATCHED_LINES = 5
  MAX_LINE_LENGTH = 500

  # Dockerfile / ECR install failures. Intentionally omit certs_none ⚠ warnings
  # (local builds without ECR) so those do not page.
  INSTALL_PATTERNS = [
    /✗ No VA-Internal certificates copied from CERTS_IMAGE/i,
    %r{✗ Expected VA-Internal/DigiCert anchors not found after installing certs from CERTS_IMAGE}i,
    /build cannot continue without VA certs/i,
    %r{dsva/va-certs:[^\s]+.*failed to resolve source metadata}i,
    %r{dsva/va-certs:[^\s]+: not found}i,
    %r{unexpected status from HEAD request to .*/dsva/va-certs/}i
  ].freeze

  VERIFY_PATTERNS = [
    /certificate verify failed/i,
    /unable to get local issuer certificate/i,
    /OpenSSL::SSL::SSLError/i,
    /SSL_connect returned=/i,
    /self[- ]signed certificate/i,
    /certificate has expired/i
  ].freeze

  def self.from_file(path, **)
    contents = File.exist?(path) ? File.read(path) : ''
    new(contents, **)
  end

  def initialize(log_text, workflow_run_url: nil)
    @log_text = log_text.to_s
    @workflow_run_url = workflow_run_url
  end

  def lines
    @lines ||= @log_text.each_line.map(&:rstrip)
  end

  def matched_lines(limit: MAX_MATCHED_LINES)
    lines.select { |line| cert_error_line?(line) }.first(limit).map { |line| truncate(line) }
  end

  def match_count
    matched_lines(limit: lines.length).length
  end

  def errors_found?
    match_count.positive?
  end

  def failure_categories
    categories = []
    categories << 'install' if lines.any? { |line| INSTALL_PATTERNS.any? { |pattern| pattern.match?(line) } }
    categories << 'verify' if lines.any? { |line| VERIFY_PATTERNS.any? { |pattern| pattern.match?(line) } }
    categories
  end

  def summary
    return 'No certificate install/verify failures detected in the CI logs.' unless errors_found?

    categories = failure_categories.join(' + ')
    message = "Certificate #{categories} failure(s) detected in CI " \
              "(#{match_count} matching log line(s))."
    message = "#{message} <#{@workflow_run_url}|View workflow run>" unless @workflow_run_url.to_s.empty?
    message
  end

  def slack_blocks
    header = ":rotating_light: *Vets API CI certificate failure* :rotating_light:\n#{summary}"
    blocks = [{ 'type' => 'divider' }, slack_section(header)]
    matched_lines.each { |line| blocks << slack_section("```#{line}```") }
    blocks << { 'type' => 'divider' }
    blocks
  end

  def write_github_outputs(output_path)
    File.open(output_path, 'a') do |file|
      file.puts "errors_found=#{errors_found?}"
      file.puts "match_count=#{match_count}"
      write_multiline(file, 'summary', summary)
      write_multiline(file, 'blocks', JSON.generate(slack_blocks))
    end
  end

  private

  def slack_section(text)
    { 'type' => 'section', 'text' => { 'type' => 'mrkdwn', 'text' => text } }
  end

  def cert_error_line?(line)
    INSTALL_PATTERNS.any? { |pattern| pattern.match?(line) } ||
      VERIFY_PATTERNS.any? { |pattern| pattern.match?(line) }
  end

  def truncate(text)
    return text if text.length <= MAX_LINE_LENGTH

    "#{text[0, MAX_LINE_LENGTH]}…"
  end

  # $GITHUB_OUTPUT requires heredoc delimiters for multiline values.
  def write_multiline(file, key, value)
    delimiter = "EOF_#{key.upcase}_#{rand(1_000_000)}"
    file.puts "#{key}<<#{delimiter}"
    file.puts value
    file.puts delimiter
  end
end

if __FILE__ == $PROGRAM_NAME
  log_file = ENV.fetch('CI_LOG_FILE', nil)
  alert = if log_file
            CertErrorAlert.from_file(
              log_file,
              workflow_run_url: ENV.fetch('WORKFLOW_RUN_URL', nil)
            )
          else
            CertErrorAlert.new(
              ARGF.read,
              workflow_run_url: ENV.fetch('WORKFLOW_RUN_URL', nil)
            )
          end

  puts alert.summary

  github_output = ENV.fetch('GITHUB_OUTPUT', nil)
  alert.write_github_outputs(github_output) if github_output

  # Workflow gates on errors_found output, not process exit status.
  exit 0
end
