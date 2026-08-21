# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCovHelper do
  # simplecov >= 1.0 evaluates configuration blocks with instance_exec and no
  # lexical fallback, so these helpers must work against an explicitly passed
  # configuration context rather than relying on the enclosing class scope.
  let(:ctx) { double('SimpleCov configuration context') }

  describe '.add_filters' do
    it 'applies every filter to the given context' do
      filters = []
      allow(ctx).to receive(:add_filter) { |path| filters << path }

      described_class.add_filters(ctx)

      expect(filters).to include('lib/feature_flipper.rb', 'rakelib/', 'version.rb')
      expect(filters.size).to be > 30
    end
  end

  describe '.add_modules' do
    it 'registers every module group on the given context' do
      groups = {}
      allow(ctx).to receive(:add_group) { |name, path| groups[name] = path }

      described_class.add_modules(ctx)

      expect(groups['Mobile']).to eq('modules/mobile/')
      expect(groups['Policies']).to eq('app/policies')
      expect(groups.size).to be > 40
    end
  end

  describe '.report_coverage' do
    it 'configures filters and groups through the collate context' do
      allow(ctx).to receive(:add_filter)
      allow(ctx).to receive(:add_group)
      allow(SimpleCov).to receive(:collate) { |_files, &block| ctx.instance_exec(&block) }

      described_class.report_coverage

      expect(ctx).to have_received(:add_filter).at_least(30).times
      expect(ctx).to have_received(:add_group).at_least(40).times
    end

    it 'returns nil when collate raises a RuntimeError' do
      allow(SimpleCov).to receive(:collate).and_raise(RuntimeError)

      expect(described_class.report_coverage).to be_nil
    end
  end
end
