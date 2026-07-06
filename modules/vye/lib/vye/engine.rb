# frozen_string_literal: true

module Vye
  class Vye::Engine < Rails::Engine
    isolate_namespace Vye
    config.generators.api_only = true
    config.eager_load_paths << (root / 'lib').to_s

    initializer 'vye.zeitwerk_ignore' do
      Rails.autoloaders.main.ignore(root / 'lib/vye/version.rb')
    end

    initializer 'model_core.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = root / 'spec/factories'
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end
  end
end
