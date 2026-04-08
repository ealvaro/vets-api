# frozen_string_literal: true

namespace :remediation do
  namespace :batch_upload do
    desc 'Upload documents from S3 to Claims Evidence API via CSV manifest'
    task run: :environment do
      manifest_path = ENV.fetch('MANIFEST_PATH', nil)
      unless manifest_path
        abort 'Usage: MANIFEST_PATH=/path/to/manifest.csv rake remediation:batch_upload:run [LIMIT=N]'
      end

      raw_limit = ENV.fetch('LIMIT', nil)
      limit = raw_limit&.match?(/\A\d+\z/) ? raw_limit.to_i : nil

      Remediation::BatchUploadProcessor.new(
        manifest_path:,
        limit:
      ).run!
    end

    desc 'Show batch upload progress'
    task status: :environment do
      Remediation::BatchUploadProcessor.print_status
    end

    desc 'Dry run: validate manifest, check S3 existence, and test connectivity'
    task dry_run: :environment do
      manifest_path = ENV.fetch('MANIFEST_PATH', nil)
      abort 'Usage: MANIFEST_PATH=/path/to/manifest.csv rake remediation:batch_upload:dry_run' unless manifest_path

      Remediation::BatchUploadProcessor.new(
        manifest_path:,
        dry_run: true
      ).run!
    end
  end
end
