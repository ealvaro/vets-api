# frozen_string_literal: true

desc 'Scan SSL certificates for upcoming expiration and notify via Slack'
task expiry_scanner: :environment do
  ExpiryScanner.scan_certs
end
