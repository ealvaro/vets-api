# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::DangerousExceptionLogging, :config do
  # Dangerous patterns - should register offenses

  it 'registers an offense for exception: e.message in Rails.logger.error' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception: e.message)
                                     ^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      end
    RUBY
  end

  it 'registers an offense for exception: e.message in a hash argument' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.warn('failed', exception: e.message, context: { foo: 'bar' })
                                    ^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      end
    RUBY
  end

  it 'registers an offense for exception: with string interpolation' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception: "\#{e.class} - \#{e.message}")
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      end
    RUBY
  end

  it 'registers an offense for exception: e.to_s' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception: e.to_s)
                                     ^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      end
    RUBY
  end

  it 'registers an offense for exception: e.class.to_s' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception: e.class.to_s)
                                     ^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      end
    RUBY
  end

  it 'registers an offense for exception: e.class.to_s in a local variable hash passed to logger' do
    expect_offense(<<~RUBY)
      def log_it(e)
        details = { exception: e.class.to_s }
                    ^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
        Rails.logger.warn('msg', details)
      end
    RUBY
  end

  it 'registers an offense for exception: e.message in a local variable hash passed to logger' do
    expect_offense(<<~RUBY)
      def log_it(e)
        details = { exception: e.message }
                    ^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
        Rails.logger.error('msg', details)
      end
    RUBY
  end

  it 'registers an offense when exception class and message are interpolated in the logger message string' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Job failed: \#{ex.class} - \#{ex.message}")
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG_DSTR}
      end
    RUBY
  end

  it 'registers an offense when backtrace is interpolated in the logger message string' do
    expect_offense(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Job failed: \#{ex.backtrace.join('\\n')}")
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG_DSTR}
      end
    RUBY
  end

  it 'does not register an offense when only non-exception data is interpolated in the logger message string' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Job \#{job_name} failed on attempt \#{attempt}")
      end
    RUBY
  end

  it 'does not register an offense when .class and .message are on different receivers' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Job \#{job.class} failed with message \#{msg.message}")
      end
    RUBY
  end

  it 'does not register an offense for only .message interpolated in the logger message string' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Failed: \#{ex.message}")
      end
    RUBY
  end

  it 'does not register an offense for only .class interpolated in the logger message string' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => ex
        Rails.logger.error("Failed: \#{ex.class}")
      end
    RUBY
  end

  # Safe patterns - should NOT register offenses

  it 'does not register an offense for exception: e (passing Exception object)' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception: e)
      end
    RUBY
  end

  it 'does not register an offense for exception: nested inside context hash' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', context: { exception: e.message })
      end
    RUBY
  end

  it 'does not register an offense for error: e.message (different key)' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', error: e.message)
      end
    RUBY
  end

  it 'does not register an offense for exception_message: e.message (different key)' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('failed', exception_message: e.message)
      end
    RUBY
  end

  it 'does not register an offense for Rails.logger.error with safe exception: e' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Rails.logger.error('msg', exception: e)
      end
    RUBY
  end

  it 'does not register an offense for exception: e.message in a standalone hash (not a logger call)' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        log_data = { message: 'failed', exception: e.class.to_s }
      end
    RUBY
  end

  it 'does not register an offense for exception: e.message passed to a non-logger method' do
    expect_no_offenses(<<~RUBY)
      begin
        something
      rescue => e
        Messager.new(exception: e.message).notify!
      end
    RUBY
  end
end
