# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::Project::NoDirectTitleize, :config do
  it 'registers an offense for .titleize' do
    expect_offense(<<~RUBY)
      first_name.titleize
                 ^^^^^^^^ #{described_class::MSG}
    RUBY
  end

  it 'registers an offense for safe navigation &.titleize' do
    expect_offense(<<~RUBY)
      first_name&.titleize
                  ^^^^^^^^ #{described_class::MSG}
    RUBY
  end

  it 'registers an offense for .titlecase' do
    expect_offense(<<~RUBY)
      name.downcase.titlecase
                    ^^^^^^^^^ #{described_class::MSG}
    RUBY
  end

  it 'does not register an offense for StringHelpers.titlecase_name' do
    expect_no_offenses(<<~RUBY)
      StringHelpers.titlecase_name(first_name)
    RUBY
  end

  it 'does not register an offense for other string methods' do
    expect_no_offenses(<<~RUBY)
      first_name.capitalize
    RUBY
  end
end
