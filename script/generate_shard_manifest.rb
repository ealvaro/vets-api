#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a shard manifest (one spec file per line) for a given parallel_test group.
# Uses the ParallelTests Ruby API directly rather than parsing CLI output.
#
# Usage:
#   ruby script/generate_shard_manifest.rb <group> <total_groups> <output_file> [runtime_log]
#
# Example:
#   ruby script/generate_shard_manifest.rb 7 24 tmp/shard-manifest-group-7.txt tmp/parallel_runtime_rspec.log

require 'parallel_tests'
require 'parallel_tests/rspec/runner'

group        = Integer(ARGV[0])
total_groups = Integer(ARGV[1])
output_file  = ARGV[2]
runtime_log  = ARGV[3] # optional; omit to use filesize grouping

if group < 1 || group > total_groups
  warn "Group #{group} is out of range (1..#{total_groups})"
  exit 1
end

options = { group_by: :filesize }

if runtime_log && File.size?(runtime_log)
  options[:group_by] = :runtime
  options[:runtime_log] = runtime_log
  warn "Using runtime-based grouping from #{runtime_log}"
else
  warn 'No runtime log found; using filesize grouping'
end

# ['spec', 'modules'] mirrors the directories passed on the CLI
all_groups = ParallelTests::RSpec::Runner.tests_in_groups(
  %w[spec modules],
  total_groups,
  options
)

group_files = all_groups[group - 1] # groups are 0-indexed internally

# We see `undefined method: blank? for array` if we try to use blank?
# since we're not in a Rails context, so check for nil or empty instead.
if group_files.nil? || group_files.empty? # rubocop:disable Rails/Blank
  warn "No spec files found for group #{group}"
  exit 1
end

# Sanity check: parallel_tests should return plain path strings, not [path, size] pairs.
# If it ever returns arrays here, xargs would receive Ruby array literals as "file paths".
unless group_files.all? { |f| f.is_a?(String) }
  warn "Unexpected item type in group #{group}: #{group_files.first.inspect}"
  exit 1
end

File.write(output_file, "#{group_files.join("\n")}\n")
warn "Wrote #{group_files.size} files to #{output_file}"
