# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::AttrPackageDeleteOnSuccess do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  context 'when Sidekiq::AttrPackage.delete is called inside an ensure block' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        def perform(cache_key)
          do_work(cache_key)
        ensure
          Sidekiq::AttrPackage.delete(cache_key)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Cop/AttrPackageDeleteOnSuccess: Do not delete Sidekiq::AttrPackage in an ensure block. Delete on success and in sidekiq_retries_exhausted. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
        end
      RUBY
    end
  end

  # Regression test for the Copilot-flagged bug:
  # ensure body is a bare send node with no descendants — each_descendant would miss it
  context 'when the ensure block contains ONLY the AttrPackage.delete call (bare send)' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        def perform(cache_key)
          do_work
        ensure
          Sidekiq::AttrPackage.delete(cache_key)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Cop/AttrPackageDeleteOnSuccess: Do not delete Sidekiq::AttrPackage in an ensure block. Delete on success and in sidekiq_retries_exhausted. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
        end
      RUBY
    end
  end

  context 'when Sidekiq::AttrPackage.delete is in the ensure with other statements' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        def perform(cache_key)
          do_work(cache_key)
        ensure
          Rails.logger.info('done')
          Sidekiq::AttrPackage.delete(cache_key)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Cop/AttrPackageDeleteOnSuccess: Do not delete Sidekiq::AttrPackage in an ensure block. Delete on success and in sidekiq_retries_exhausted. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
        end
      RUBY
    end
  end

  context 'when Sidekiq::AttrPackage.delete is called outside an ensure block' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        def perform(cache_key)
          do_work(cache_key)
          Sidekiq::AttrPackage.delete(cache_key)
        end
      RUBY
    end
  end

  context 'when a different object calls delete inside an ensure block' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        def perform(cache_key)
          do_work(cache_key)
        ensure
          Redis.current.delete(cache_key)
        end
      RUBY
    end
  end

  context 'when sidekiq_retries_exhausted deletes AttrPackage (not in ensure)' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        sidekiq_retries_exhausted do |msg|
          Sidekiq::AttrPackage.delete(msg['args'].first)
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Job uses AttrPackage without deleting on success in perform' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform(cache_key)
              ^^^^^^^ Cop/AttrPackageDeleteOnSuccess: Jobs using Sidekiq::AttrPackage must call Sidekiq::AttrPackage.delete on the success path in perform. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
            data = Sidekiq::AttrPackage.find(cache_key)
            do_work(data)
          end
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Job deletes AttrPackage on the success path in perform' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform(cache_key)
            data = Sidekiq::AttrPackage.find(cache_key)
            do_work(data)
            Sidekiq::AttrPackage.delete(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when a Sidekiq::Job deletes AttrPackage inside a private method called from perform' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          sidekiq_retries_exhausted do |msg|
            Sidekiq::AttrPackage.delete(msg['args'].first)
          end

          def perform(cache_key, credential_method, credential_id)
            data = Sidekiq::AttrPackage.find(cache_key)
            handle_response(cache_key, data)
          end

          private

          def handle_response(cache_key, data)
            Sidekiq::AttrPackage.delete(cache_key)
          end
        end
      RUBY
    end
  end
end
