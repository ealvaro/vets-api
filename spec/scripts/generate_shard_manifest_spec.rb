# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../script/generate_shard_manifest'

RSpec.describe ShardManifest do
  let(:temp_dir) { Dir.mktmpdir }
  let(:groups) do
    [
      %w[spec/a_spec.rb spec/b_spec.rb],
      %w[spec/c_spec.rb],
      []
    ]
  end

  after { FileUtils.rm_rf(temp_dir) }

  describe '.build_groups' do
    it 'uses runtime-based grouping when a non-empty runtime log is present' do
      runtime_log = File.join(temp_dir, 'runtime.log')
      File.write(runtime_log, "spec/a_spec.rb:1.0\n")
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups[0..1])

      described_class.build_groups(2, runtime_log)

      expect(ParallelTests::RSpec::Runner).to have_received(:tests_in_groups).with(
        %w[spec modules], 2, hash_including(group_by: :runtime, runtime_log:)
      )
    end

    it 'falls back to filesize grouping when no runtime log is given' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups[0..1])

      described_class.build_groups(2, nil)

      expect(ParallelTests::RSpec::Runner).to have_received(:tests_in_groups).with(
        %w[spec modules], 2, hash_including(group_by: :filesize)
      )
    end
  end

  describe '.write_single_group' do
    it 'writes the files for the requested group to the output file' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups)
      output_file = File.join(temp_dir, 'group1.txt')

      described_class.write_single_group(1, 3, output_file, nil)

      expect(File.read(output_file)).to eq("spec/a_spec.rb\nspec/b_spec.rb\n")
    end

    it 'exits with an error when the group is out of range' do
      expect { described_class.write_single_group(4, 3, File.join(temp_dir, 'out.txt'), nil) }
        .to raise_error(SystemExit)
    end

    it 'exits with an error when the group has no files' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups)

      expect { described_class.write_single_group(3, 3, File.join(temp_dir, 'out.txt'), nil) }
        .to raise_error(SystemExit)
    end

    it 'exits with an error when parallel_tests returns non-string entries' do
      # Simulates parallel_tests returning [path, size] pairs instead of plain path strings
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return([[['spec/a_spec.rb', 123]]])

      expect { described_class.write_single_group(1, 1, File.join(temp_dir, 'out.txt'), nil) }
        .to raise_error(SystemExit)
    end
  end

  describe '.write_all_groups' do
    it 'writes one manifest per group plus a sorted union manifest' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups[0..1])
      output_dir = File.join(temp_dir, 'manifests')

      described_class.write_all_groups(2, output_dir, nil)

      expect(File.read(File.join(output_dir, 'shard-manifest-group-1.txt'))).to eq("spec/a_spec.rb\nspec/b_spec.rb\n")
      expect(File.read(File.join(output_dir, 'shard-manifest-group-2.txt'))).to eq("spec/c_spec.rb\n")
      expect(File.read(File.join(output_dir, 'shard-manifest-union.txt')))
        .to eq("spec/a_spec.rb\nspec/b_spec.rb\nspec/c_spec.rb\n")
    end

    it 'exits with an error if any group is empty' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(groups)

      expect { described_class.write_all_groups(3, File.join(temp_dir, 'manifests'), nil) }
        .to raise_error(SystemExit)
    end

    it 'exits with an error if the same file is assigned to more than one group' do
      duped = [%w[spec/a_spec.rb], %w[spec/a_spec.rb]]
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(duped)

      expect { described_class.write_all_groups(2, File.join(temp_dir, 'manifests'), nil) }
        .to raise_error(SystemExit)
    end

    it 'exits with an error if any group contains non-string entries' do
      allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups).and_return(
        [%w[spec/a_spec.rb], [['spec/b_spec.rb', 42]]]
      )

      expect { described_class.write_all_groups(2, File.join(temp_dir, 'manifests'), nil) }
        .to raise_error(SystemExit)
    end
  end
end
