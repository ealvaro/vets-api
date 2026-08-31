# frozen_string_literal: true

require 'rails_helper'
require 'ivc_champva/config_file_loader'

RSpec.describe IvcChampva::ConfigFileLoader do
  describe '.load' do
    it 'returns the parsed JSON when the file exists and is valid' do
      Tempfile.create(['config_file_loader_spec', '.json']) do |file|
        file.write({ 'statuses' => %w[foo bar] }.to_json)
        file.flush

        result = described_class.load(file.path, context: 'SpecContext')

        expect(result).to eq('statuses' => %w[foo bar])
      end
    end

    it 'logs and returns the default empty hash fallback when the file does not exist' do
      missing_path = Rails.root.join('config', 'benefits_claims', 'does_not_exist.json')

      expect(Rails.logger).to receive(:error).with(
        "SpecContext: Failed to load config file #{missing_path}",
        { message: a_string_matching(/No such file/) }
      )
      expect(StatsD).to receive(:increment)
        .with('ivc_champva.config_file_loader.silent_failure', tags: ['context:SpecContext'])

      expect(described_class.load(missing_path, context: 'SpecContext')).to eq({})
    end

    it 'logs and returns the given fallback when the file does not exist' do
      missing_path = Rails.root.join('config', 'benefits_claims', 'does_not_exist.json')
      fallback = %w[default]

      allow(Rails.logger).to receive(:error)

      expect(described_class.load(missing_path, context: 'SpecContext', fallback:)).to eq(fallback)
    end

    it 'logs and returns the fallback when the file contains invalid JSON' do
      Tempfile.create(['config_file_loader_spec', '.json']) do |file|
        file.write('not valid json')
        file.flush

        expect(Rails.logger).to receive(:error).with(
          "SpecContext: Failed to load config file #{file.path}",
          { message: a_string_matching(/unexpected token/) }
        )
        expect(StatsD).to receive(:increment)
          .with('ivc_champva.config_file_loader.silent_failure', tags: ['context:SpecContext'])

        expect(described_class.load(file.path, context: 'SpecContext', fallback: [])).to eq([])
      end
    end

    it 'strips \':\' from the context before it reaches the StatsD tag' do
      missing_path = Rails.root.join('config', 'benefits_claims', 'does_not_exist.json')
      allow(Rails.logger).to receive(:error)

      expect(StatsD).to receive(:increment)
        .with('ivc_champva.config_file_loader.silent_failure',
              tags: ['context:IvcChampvaSomeModule'])

      described_class.load(missing_path, context: 'IvcChampva::SomeModule')
    end
  end

  describe '.sanitize_tag_value' do
    it 'strips every colon from a Ruby module/class name' do
      expect(described_class.sanitize_tag_value('IvcChampva::ChampvaEligibilityService')).to eq(
        'IvcChampvaChampvaEligibilityService'
      )
    end

    it 'leaves a value with no colons unchanged' do
      expect(described_class.sanitize_tag_value('SpecContext')).to eq('SpecContext')
    end

    it 'stringifies a non-string value first' do
      expect(described_class.sanitize_tag_value(:some_symbol)).to eq('some_symbol')
    end
  end
end
