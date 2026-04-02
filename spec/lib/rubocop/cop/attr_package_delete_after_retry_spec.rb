# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::AttrPackageDeleteAfterRetry do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  context 'when a Sidekiq::Job uses AttrPackage without sidekiq_retries_exhausted' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        class MyJob
              ^^^^^ Cop/AttrPackageDeleteAfterRetry: Jobs using Sidekiq::AttrPackage must define sidekiq_retries_exhausted to clean up the cache key after terminal failure. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
          include Sidekiq::Job

          def perform(cache_key)
            data = Sidekiq::AttrPackage.find(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Worker uses AttrPackage without sidekiq_retries_exhausted' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        class MyWorker
              ^^^^^^^^ Cop/AttrPackageDeleteAfterRetry: Jobs using Sidekiq::AttrPackage must define sidekiq_retries_exhausted to clean up the cache key after terminal failure. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
          include Sidekiq::Worker

          def perform(cache_key)
            data = Sidekiq::AttrPackage.find(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Job uses AttrPackage with sidekiq_retries_exhausted defined' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          sidekiq_retries_exhausted do |msg|
            Sidekiq::AttrPackage.delete(msg['args'].first)
          end

          def perform(cache_key)
            data = Sidekiq::AttrPackage.find(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Job does not use AttrPackage at all' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform(id)
            User.find(id).process!
          end
        end
      RUBY
    end
  end

  context 'when a plain class uses AttrPackage (not a Sidekiq job)' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyService
          def call(cache_key)
            Sidekiq::AttrPackage.find(cache_key)
          end
        end
      RUBY
    end
  end
end
