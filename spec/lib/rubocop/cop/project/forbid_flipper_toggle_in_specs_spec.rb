# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::Project::ForbidFlipperToggleInSpecs, :config do
  context 'in spec files' do
    it 'registers an offense for Flipper.enable' do
      method = 'enable'
      expect_offense(<<~RUBY, 'spec/models/example_spec.rb')
        Flipper.#{method}(:some_feature)
                #{'^' * method.length} #{described_class::MSG}
      RUBY
    end

    it 'registers an offense for Flipper.disable' do
      method = 'disable'
      expect_offense(<<~RUBY, 'spec/models/example_spec.rb')
        Flipper.#{method}(:some_feature)
                #{'^' * method.length} #{described_class::MSG}
      RUBY
    end

    it 'does not register an offense for Flipper.enabled?' do
      expect_no_offenses(<<~RUBY, 'spec/models/example_spec.rb')
        allow(Flipper).to receive(:enabled?).with(:some_feature).and_return(true)
      RUBY
    end
  end

  context 'outside spec files' do
    it 'does not register an offense for Flipper.toggle outside specs' do
      method = 'enable'
      expect_no_offenses(<<~RUBY, 'app/services/example_service.rb')
        Flipper.#{method}(:some_feature)
      RUBY
    end
  end
end
