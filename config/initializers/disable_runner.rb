# frozen_string_literal: true

if Rails.env.production? && defined?(Rails::Command::RunnerCommand)
  Rails::Command::RunnerCommand.class_eval do
    def perform(*)
      raise 'rails runner is disabled in live environments.'
    end
  end
end
