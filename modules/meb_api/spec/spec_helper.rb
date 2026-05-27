# frozen_string_literal: true

# Configure Rails Envinronment
ENV['RAILS_ENV'] = 'test'

require 'rspec/rails'

# Load shared examples
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure { |config| config.use_transactional_fixtures = true }
