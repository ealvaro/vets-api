# frozen_string_literal: true

require 'flipper'
require 'flipper/adapters/active_record'
require 'active_support/cache'
require 'flipper/adapters/active_support_cache_store'
require 'flipper/ui/action_patch'
require 'flipper/ui/actors_value_normalizer'
require 'flipper/instrumentation/event_subscriber'

FLIPPER_FEATURE_CONFIG = YAML.safe_load(Rails.root.join('config', 'features.yml').read)

Rails.application.configure do
  # Limit test_help behavior to test only.
  config.flipper.test_help = Rails.env.test?
  config.flipper.log = false
  config.middleware.insert_before ActionDispatch::Executor, Flipper::UI::ActorsValueNormalizer
end

Rails.application.reloader.to_prepare do
  FLIPPER_ACTOR_USER = 'user'
  FLIPPER_ACTOR_STRING = 'cookie_id'

  # Modify Flipper::UI::Action to use our custom views
  Flipper::UI::Action.prepend(Flipper::UI::ActionPatch)

  unless Rails.env.test?
    Flipper.configure do |config|
      config.default do
        activerecord_adapter = Flipper::Adapters::ActiveRecord.new
        cache = Rails.cache
        expires_in = 1.minute

        # Flipper settings will be stored in postgres and cached in memory for 1 minute in production/staging
        cached_adapter = Flipper::Adapters::ActiveSupportCacheStore.new(activerecord_adapter, cache, expires_in)
        instrumented = Flipper::Adapters::Instrumented.new(cached_adapter, instrumenter: ActiveSupport::Notifications)

        Flipper.new(instrumented, instrumenter: ActiveSupport::Notifications)
      end
    end
  end

  Flipper::UI.configure do |config|
    config.feature_creation_enabled = false
    config.feature_removal_enabled = false
    config.show_feature_description_in_list = true
    config.confirm_disable = true
    config.confirm_fully_enable = true
    config.add_actor_placeholder = 'Enter email or UUID (comma-separated for multiple)'
    config.descriptions_source = lambda do |_keys|
      FLIPPER_FEATURE_CONFIG['features'].transform_values { |value| value['description'] }
    end
  end

  Rails.application.config.after_initialize do
    # In test, Flipper::TestHelp manages adapter setup and per-example resets.
    next if Rails.env.test?

    # Skip feature initialization if using rake task setup (FLIPPER_USE_RAKE_SETUP=true)
    # When enabled, features are initialized via `rake features:setup` instead of during app boot
    if ActiveModel::Type::Boolean.new.cast(ENV.fetch('FLIPPER_USE_RAKE_SETUP', nil))
      Rails.logger.info 'Skipping Flipper feature initialization (FLIPPER_USE_RAKE_SETUP=true)'
      next
    end

    # Make sure that each feature we reference in code is present in the UI, as long as we have a Database already
    added_flippers = []
    begin
      FLIPPER_FEATURE_CONFIG['features'].each do |feature, feature_config|
        unless Flipper.exist?(feature)
          Flipper.add(feature)
          added_flippers.push(feature)

          # Default features to enabled for those explicitly set for development or staging
          if (Rails.env.development? && feature_config['enable_in_development']) ||
             (Settings.vsp_environment == 'staging' && feature_config['enable_in_staging'])
            Flipper.enable(feature)
          end
        end

        # Enable features on dev-api.va.gov if they are set to enable_in_development
        Flipper.enable(feature) if Settings.vsp_environment == 'development' && feature_config['enable_in_development']
      end

      Rails.logger.info "The following feature flippers were added: #{added_flippers}" unless added_flippers.empty?
      removed_features = Flipper.features.collect(&:name) - FLIPPER_FEATURE_CONFIG['features'].keys
      unless removed_features.empty?
        Rails.logger.warn "Consider removing features no longer in config/features.yml: #{removed_features.join(', ')}"
      end
    rescue => e
      Rails.logger.error "Error processing Flipper features: #{e.message}"
      # make sure we can still run rake tasks before table has been created
      nil
    end
  end

  if Rails.env.test? && defined?(RSpec)
    feature_keys = FLIPPER_FEATURE_CONFIG.fetch('features', {}).keys.freeze

    RSpec.configure do |config|
      config.append_before(:each) do
        # TestHelp resets Flipper state before each example, so re-enable configured
        # features to preserve legacy default-on expectations in specs.
        feature_keys.each do |feature|
          Flipper.enable(feature)
        end
      end
    end
  end
end
