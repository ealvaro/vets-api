# frozen_string_literal: true

module RepresentationManagement
  class Engine < ::Rails::Engine
    isolate_namespace RepresentationManagement
    config.generators.api_only = true

    initializer 'model_core.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = File.expand_path('../../spec/factories', __dir__)
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end

    config.eager_load_paths << root.join('lib').to_s

    initializer 'representation_management.zeitwerk_ignore' do
      loader = Rails.autoloaders.main
      loader.ignore(root.join('lib/fonts'))
      loader.ignore(root.join('lib/tasks'))
      loader.ignore(root.join('lib/representation_management/version.rb'))
    end
  end
end
