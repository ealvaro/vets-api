# frozen_string_literal: true

module ClaimsApi
  class Engine < ::Rails::Engine
    isolate_namespace ClaimsApi

    initializer :append_migrations do |app|
      unless app.root.to_s.match? root.to_s
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
          ActiveRecord::Migrator.migrations_paths << expanded_path
        end
      end
    end
    config.generators do |g|
      g.test_framework :rspec, view_specs: false
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end
    initializer 'claims_api.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = File.expand_path('../../spec/factories', __dir__)
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end

    # Register job tracker middleware and orphan recovery for crash resilience.
    # Keeps everything self-contained in the claims_api engine
    # no changes needed in the main app's config/initializers/sidekiq.rb.
    #
    # Controlled by Flipper :claims_api_job_tracker flag.
    # And recover_orphans!(log_only: true) controls
    # if we do the re-enqueue or just log the orphaned jobs.
    initializer 'claims_api.sidekiq_job_tracker' do
      require 'claims_api/job_tracker'
      require 'claims_api/job_tracker_middleware'

      Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.prepend ClaimsApi::JobTrackerMiddleware
        end

        config.on(:startup) do
          # 65s delay: ProcessSet entries have ~60s heartbeat TTL.
          # Waiting 65s guarantees crashed processes are fully evicted
          # before we check. Mirrors Sidekiq Pro's super_fetch approach.
          ClaimsApi::JobTrackerRecoveryJob.perform_in(65) if Flipper.enabled?(:claims_api_job_tracker)
        end
      end
    end
  end
end
