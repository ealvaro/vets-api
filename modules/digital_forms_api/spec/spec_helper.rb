# frozen_string_literal: true

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require 'rspec/rails'

# Fuzz / randomized-data helpers
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.include DigitalFormsApi::SubmissionFuzzHelpers, type: :controller
end
