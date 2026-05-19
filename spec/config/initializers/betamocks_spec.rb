# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Betamocks do
  let(:config_path) { Settings.betamocks.services_config }

  # sanity check for validating settings & betamocks
  it 'produces valid YAML after ERB evaluation' do
    rendered = ERB.new(File.read(config_path)).result
    expect { YAML.safe_load(rendered, permitted_classes: [Symbol]) }.not_to raise_error
  end

  context 'when dgi.vye.vets.url is blank' do
    before { allow(Settings.dgi.vye.vets).to receive(:url).and_return('') }

    it 'produces invalid YAML, demonstrating why a placeholder url is required' do
      rendered = ERB.new(File.read(config_path)).result
      expect { YAML.safe_load(rendered, permitted_classes: [Symbol]) }.to raise_error(Psych::SyntaxError)
    end
  end
end
