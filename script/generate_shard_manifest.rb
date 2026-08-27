#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates shard manifests (one spec file per line) for parallel_test groups.
# Uses the ParallelTests Ruby API directly rather than parsing CLI output.
#
# Single-group mode (kept for local debugging / manual invocation):
#   ruby script/generate_shard_manifest.rb <group> <total_groups> <output_file> [runtime_log]
#
# All-groups mode (used by the shard_manifest CI job -- calls tests_in_groups exactly
# once so every group's manifest comes from the same partition):
#   ruby script/generate_shard_manifest.rb all <total_groups> <output_dir> [runtime_log]

require 'fileutils'
require 'parallel_tests'
require 'parallel_tests/rspec/runner'

module ShardManifest
  # ['spec', 'modules'] mirrors the directories passed on the CLI
  SPEC_DIRS = %w[spec modules].freeze

  def self.build_groups(total_groups, runtime_log)
    options = { group_by: :filesize }

    if runtime_log && File.size?(runtime_log)
      options[:group_by] = :runtime
      options[:runtime_log] = runtime_log
      warn "Using runtime-based grouping from #{runtime_log}"
    else
      warn 'No runtime log found; using filesize grouping'
    end

    ParallelTests::RSpec::Runner.tests_in_groups(SPEC_DIRS, total_groups, options)
  end

  def self.plain_path_strings?(group_files)
    group_files.all? { |f| f.is_a?(String) }
  end

  def self.fail!(message)
    warn message
    exit 1
  end

  def self.write_single_group(group, total_groups, output_file, runtime_log)
    fail!("Group #{group} is out of range (1..#{total_groups})") if group < 1 || group > total_groups

    group_files = build_groups(total_groups, runtime_log)[group - 1]

    # We see `undefined method: blank? for array` if we try to use blank?
    # since we're not in a Rails context, so check for nil or empty instead.
    fail!("No spec files found for group #{group}") if group_files.nil? || group_files.empty? # rubocop:disable Rails/Blank

    # Sanity check: parallel_tests should return plain path strings, not [path, size] pairs.
    # If it ever returns arrays here, xargs would receive Ruby array literals as "file paths".
    unless plain_path_strings?(group_files)
      fail!("Unexpected item type in group #{group}: #{group_files.first.inspect}")
    end

    File.write(output_file, "#{group_files.join("\n")}\n")
    warn "Wrote #{group_files.size} files to #{output_file}"
  end

  def self.write_all_groups(total_groups, output_dir, runtime_log)
    all_groups = build_groups(total_groups, runtime_log)

    validate_groups!(all_groups)

    FileUtils.mkdir_p(output_dir)

    all_groups.each_with_index do |group_files, index|
      File.write(File.join(output_dir, "shard-manifest-group-#{index + 1}.txt"), "#{group_files.join("\n")}\n")
    end

    union = all_groups.flatten
    File.write(File.join(output_dir, 'shard-manifest-union.txt'), "#{union.sort.join("\n")}\n")
    warn "Wrote #{total_groups} group manifests + union manifest (#{union.size} files) to #{output_dir}"
  end

  def self.validate_groups!(all_groups)
    all_groups.each_with_index do |group_files, index|
      # We see `undefined method: blank? for array` if we try to use blank?
      # since we're not in a Rails context, so check for nil or empty instead.
      fail!("No spec files found for group #{index + 1}") if group_files.nil? || group_files.empty? # rubocop:disable Rails/Blank

      unless plain_path_strings?(group_files)
        fail!("Unexpected item type in group #{index + 1}: #{group_files.first.inspect}")
      end
    end

    union = all_groups.flatten
    fail!('Duplicate spec file assigned to more than one group') if union.uniq.size != union.size
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV[0] == 'all'
    ShardManifest.write_all_groups(Integer(ARGV[1]), ARGV[2], ARGV[3])
  else
    ShardManifest.write_single_group(Integer(ARGV[0]), Integer(ARGV[1]), ARGV[2], ARGV[3])
  end
end
