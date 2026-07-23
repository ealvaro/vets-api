# frozen_string_literal: true

module Pensions
  # @see https://api.rubyonrails.org/classes/Rails/Engine.html
  class Engine < ::Rails::Engine
    isolate_namespace Pensions
    config.generators.api_only = true

    initializer 'pensions.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = File.expand_path('../../spec/factories', __dir__)
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end

    initializer 'pensions.zero_silent_failures' do |app|
      app.config.to_prepare do
        require_all "#{__dir__}/zero_silent_failures"
      end
    end

    initializer 'pensions.military_information' do |app|
      app.config.to_prepare do
        require 'pensions/military_information'
      end
    end

    initializer 'pensions.pdf_fill.register_form' do |app|
      app.config.to_prepare do
        require 'pdf_fill/filler'
        require 'pensions/pdf_fill/va21p527ez'

        # Register our Pension Pdf Fill form
        ::PdfFill::Filler.register_form(Pensions::FORM_ID, Pensions::PdfFill::Va21p527ez)
      end
    end

    initializer 'pensions.benefits_intake.register_handler' do |app|
      app.config.to_prepare do
        require 'lighthouse/benefits_intake/sidekiq/submission_status_job'
        require 'pensions/benefits_intake/submission_handler'

        # Register our Pension Benefits Intake Submission Handler
        ::BenefitsIntake::SubmissionStatusJob.register_handler(Pensions::FORM_ID,
                                                               Pensions::BenefitsIntake::SubmissionHandler)
      end
    end

    initializer 'pensions.pdf_stamper.register_stamp_sets' do |app|
      app.config.to_prepare do
        require 'pdf_utilities/pdf_stamper'
        require 'pensions/pdf_stamper'

        # Only register stamps if database exists and is connected
        # This is happening because stamp_sets calls Pensions.pdf_path which checks a Flipper flag
        # During the CI creation of the vets_api_test database
        begin
          ActiveRecord::Base.connection.verify!

          stamp_sets = Pensions::PDFStamper.stamp_sets
          stamp_sets.each do |identifier, stamps|
            ::PDFUtilities::PDFStamper.register_stamps(identifier, stamps)
          end
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
          # Skip registration when database is not available (e.g., during db:create)
          Rails.logger.debug('Skipping Pensions PDF stamper registration - database not available')
        end
      end
    end
  end
end
