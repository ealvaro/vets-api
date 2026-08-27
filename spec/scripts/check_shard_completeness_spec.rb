# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../script/check_shard_completeness'

RSpec.describe ShardCompleteness do
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(temp_dir) }

  def write_manifest(*files)
    path = File.join(temp_dir, 'union.txt')
    File.write(path, "#{files.join("\n")}\n")
    path
  end

  def write_xml(*executed_files)
    path = File.join(temp_dir, "results-#{SecureRandom.hex(4)}.xml")
    testcases = executed_files.map { |f| %(<testcase file="#{f}" name="test" time="1.0"/>) }.join("\n")
    File.write(path, "<testsuite>\n#{testcases}\n</testsuite>")
    path
  end

  describe '.missing_files' do
    it 'returns an empty array when every assigned file was executed' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/b_spec.rb')
      xml = write_xml('spec/a_spec.rb', 'spec/b_spec.rb')

      expect(described_class.missing_files(manifest, [xml])).to eq([])
    end

    it 'returns assigned files that never appear in the JUnit XML' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/b_spec.rb', 'spec/c_spec.rb')
      xml = write_xml('spec/a_spec.rb')

      expect(described_class.missing_files(manifest, [xml])).to eq(%w[spec/b_spec.rb spec/c_spec.rb])
    end

    it 'normalizes leading ./ in the manifest' do
      manifest = write_manifest('./spec/a_spec.rb')
      xml = write_xml('spec/a_spec.rb')

      expect(described_class.missing_files(manifest, [xml])).to eq([])
    end

    it 'excludes files a dry-run report shows never register an example (e.g. :skip, shared_examples-only)' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/skipped_spec.rb')
      xml = write_xml('spec/a_spec.rb')
      dry_run = write_xml('spec/a_spec.rb')

      expect(described_class.missing_files(manifest, [xml], dry_run_xml_paths: [dry_run])).to eq([])
    end

    it 'still reports a genuine gap even when dry-run reports are provided' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/b_spec.rb', 'spec/skipped_spec.rb')
      xml = write_xml('spec/a_spec.rb')
      dry_run = write_xml('spec/a_spec.rb', 'spec/b_spec.rb')

      expect(described_class.missing_files(manifest, [xml],
                                           dry_run_xml_paths: [dry_run])).to eq(['spec/b_spec.rb'])
    end

    it 'merges examples across multiple dry-run reports (one per shard group)' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/b_spec.rb', 'spec/skipped_spec.rb')
      xml = write_xml('spec/a_spec.rb')
      dry_run_a = write_xml('spec/a_spec.rb')
      dry_run_b = write_xml('spec/b_spec.rb')

      result = described_class.missing_files(manifest, [xml], dry_run_xml_paths: [dry_run_a, dry_run_b])

      expect(result).to eq(['spec/b_spec.rb'])
    end

    it 'ignores an empty dry-run path list and falls back to unfiltered gaps' do
      manifest = write_manifest('spec/a_spec.rb', 'spec/b_spec.rb')
      xml = write_xml('spec/a_spec.rb')

      result = described_class.missing_files(manifest, [xml], dry_run_xml_paths: [])

      expect(result).to eq(['spec/b_spec.rb'])
    end
  end

  describe '.report' do
    it 'writes a passing message to the step summary when nothing is missing' do
      summary_path = File.join(temp_dir, 'summary.md')

      described_class.report([], 2, summary_path:)

      expect(File.read(summary_path)).to include('Shard completeness check passed: all 2 assigned spec files')
    end

    it 'writes a warning to the step summary when files are missing' do
      summary_path = File.join(temp_dir, 'summary.md')

      described_class.report(['spec/missing_spec.rb'], 3, summary_path:)

      contents = File.read(summary_path)
      expect(contents).to include('Possible sharding or execution gap')
      expect(contents).to include('spec/missing_spec.rb')
    end

    it 'does not raise when no summary path is set' do
      expect { described_class.report(['spec/missing_spec.rb'], 1, summary_path: nil) }.not_to raise_error
    end
  end
end
