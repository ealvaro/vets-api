# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::NoAttrPackageCreationInJob do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  %i[create].each do |method|
    context "when Sidekiq::AttrPackage.#{method} is called inside a Sidekiq::Job" do
      it 'registers an offense' do
        expect_offense(<<~RUBY)
          class MyJob
            include Sidekiq::Job

            def perform(user_id)
              Sidekiq::AttrPackage.#{method}(user_id: user_id)
              #{'^' * "Sidekiq::AttrPackage.#{method}(user_id: user_id)".length} Cop/NoAttrPackageCreationInJob: Do not create Sidekiq::AttrPackage inside a job. Create it at the entry point and pass only the cache_key. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
            end
          end
        RUBY
      end
    end

    context "when Sidekiq::AttrPackage.#{method} is called inside a Sidekiq::Worker" do
      it 'registers an offense' do
        expect_offense(<<~RUBY)
          class MyWorker
            include Sidekiq::Worker

            def perform(user_id)
              Sidekiq::AttrPackage.#{method}(user_id: user_id)
              #{'^' * "Sidekiq::AttrPackage.#{method}(user_id: user_id)".length} Cop/NoAttrPackageCreationInJob: Do not create Sidekiq::AttrPackage inside a job. Create it at the entry point and pass only the cache_key. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
            end
          end
        RUBY
      end
    end

    context "when Sidekiq::AttrPackage.#{method} is called in self.enqueue and passed to own perform_async" do
      it 'registers an offense' do
        expect_offense(<<~RUBY)
          class MyJob
            include Sidekiq::Job

            def self.enqueue(user_id)
              key = Sidekiq::AttrPackage.#{method}(user_id: user_id)
                    #{'^' * "Sidekiq::AttrPackage.#{method}(user_id: user_id)".length} Cop/NoAttrPackageCreationInJob: Do not create Sidekiq::AttrPackage inside a job. Create it at the entry point and pass only the cache_key. See https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines.
              perform_async(key)
            end
          end
        RUBY
      end
    end
  end

  context 'when Sidekiq::AttrPackage.create is called and key is passed to a different job' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class OrchestratorJob
          include Sidekiq::Job

          def perform(user_id)
            key = Sidekiq::AttrPackage.create(user_id: user_id)
            ChildJob.perform_async(key)
          end
        end
      RUBY
    end
  end

  context 'when Sidekiq::AttrPackage.new is called outside a Sidekiq job (e.g. a controller)' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyController
          def create
            cache_key = Sidekiq::AttrPackage.new(user_id: params[:id])
            MyJob.perform_async(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when Sidekiq::AttrPackage.find is called inside a job (read, not creation)' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform(cache_key)
            data = Sidekiq::AttrPackage.find(cache_key)
          end
        end
      RUBY
    end
  end

  context 'when a non-AttrPackage object calls .new inside a job' do
    it 'registers no offense' do
      expect_no_offenses(<<~RUBY)
        class MyJob
          include Sidekiq::Job

          def perform(id)
            MyService.new(id).call
          end
        end
      RUBY
    end
  end
end
