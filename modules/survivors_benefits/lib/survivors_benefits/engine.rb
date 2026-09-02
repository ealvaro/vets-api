# frozen_string_literal: true

module SurvivorsBenefits
  # @see https://api.rubyonrails.org/classes/Rails/Engine.html
  class Engine < ::Rails::Engine
    isolate_namespace SurvivorsBenefits
    config.generators.api_only = true

    initializer 'model_core.factories', after: 'factory_bot.set_factory_paths' do
      if defined?(FactoryBot)
        path = File.expand_path('../../spec/factories', __dir__)
        FactoryBot.definition_file_paths << path if Dir.exist?(path)
      end
    end

    initializer 'survivors_benefits.pdf_fill.register_form' do |app|
      app.config.to_prepare do
        require 'pdf_fill/filler'
        require 'survivors_benefits/pdf_fill/va21p534ez'

        # Register our Survivors Benefits Pdf Fill form
        ::PdfFill::Filler.register_form(SurvivorsBenefits::FORM_ID, SurvivorsBenefits::PdfFill::Va21p534ez)
      end
    end

    # The BPDS formatter is resolved by name (BPDS::Sidekiq::SubmitToBPDSJob::FORMATTERS) and lives
    # under modules/survivors_benefits/lib, which an engine puts on $LOAD_PATH but not on the
    # autoload path. Without this require the constantize raises NameError, the job's rescue
    # swallows it, and BPDS silently receives the raw parsed_form instead of structured data.
    initializer 'survivors_benefits.bpds.require_formatter' do |app|
      app.config.to_prepare do
        require 'survivors_benefits/bpds/formatter'
      end
    end

    initializer 'survivors_benefits.benefits_intake.register_handler' do |app|
      app.config.to_prepare do
        require 'lighthouse/benefits_intake/sidekiq/submission_status_job'
        require 'survivors_benefits/benefits_intake/submission_handler'

        # Register the Benefits Intake Submission Handler
        ::BenefitsIntake::SubmissionStatusJob.register_handler(SurvivorsBenefits::FORM_ID,
                                                               SurvivorsBenefits::BenefitsIntake::SubmissionHandler)
      end
    end
  end
end
