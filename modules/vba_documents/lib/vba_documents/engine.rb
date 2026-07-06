# frozen_string_literal: true

require 'aws-sdk-s3'

module VBADocuments
  class Engine < ::Rails::Engine
    isolate_namespace VBADocuments

    config.eager_load_paths << root.join('lib').to_s

    initializer 'vba_documents.zeitwerk_ignore' do
      loader = Rails.autoloaders.main
      loader.ignore(root.join('lib/tasks'))
      loader.ignore(root.join('lib/vba_documents/version.rb'))
      loader.ignore(root.join('lib/vba_documents/pdf_inspector.rb'))
      loader.ignore(root.join('lib/vba_documents/upload_validator.rb'))
    end

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
    initializer 'vba_documents.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = File.expand_path('../../spec/factories', __dir__)
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end
  end
end
