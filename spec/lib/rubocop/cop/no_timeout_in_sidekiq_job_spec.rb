# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::NoTimeoutInSidekiqJob do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  let(:msg) do
    'Cop/NoTimeoutInSidekiqJob: Avoid Timeout.timeout in Sidekiq jobs. It raises inside a thread and can corrupt ' \
      'shared connections, causing unrelated jobs to fail. Use per-operation timeouts ' \
      '(e.g., Net::HTTP read_timeout) instead. ' \
      'See https://www.mikeperham.com/2015/05/08/timeout-rubys-most-dangerous-api/'
  end

  context 'when Timeout.timeout is called inside a Sidekiq::Job' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform
            Timeout.timeout(30) { external_call }
            ^^^^^^^^^^^^^^^^^^^ #{msg}
          end
        end
      RUBY
    end
  end

  context 'when Timeout.timeout is called inside a Sidekiq::Worker' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        class MyWorker
          include Sidekiq::Worker

          def perform
            Timeout.timeout(30) { external_call }
            ^^^^^^^^^^^^^^^^^^^ #{msg}
          end
        end
      RUBY
    end
  end

  context 'when Timeout.timeout is called outside a Sidekiq job' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyService
          def call
            Timeout.timeout(30) { external_call }
          end
        end
      RUBY
    end
  end

  context 'when a non-Timeout receiver calls a method named timeout inside a Sidekiq job' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform
            SomeLibrary.timeout(30)
          end
        end
      RUBY
    end
  end

  context 'when Timeout.timeout is called at the top-level (no class)' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        Timeout.timeout(30) { external_call }
      RUBY
    end
  end
end
