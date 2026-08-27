#!/usr/bin/env ruby
# frozen_string_literal: true

# Warn-only check: compares the shard manifest union (every spec file assigned to a
# test group) against the spec files that actually appear in the collected JUnit XML.
# A gap here means specs were assigned but never executed -- the failure mode that
# silently dropped thousands of specs and produced a misleading "coverage below 90%"
# error. This never fails the job; it only surfaces an explicit warning.
#
# Usage: ruby script/check_shard_completeness.rb <union_manifest> <xml_glob> [dry_run_xml_glob]

# rubocop:disable Lint/RedundantRequireStatement -- explicit require since this script runs standalone, not under Rails
require 'set'
require_relative 'junit_to_runtime_log'
# rubocop:enable Lint/RedundantRequireStatement

module ShardCompleteness
  def self.assigned_files(union_manifest_path)
    File.readlines(union_manifest_path, chomp: true)
        .map { |line| line.sub(%r{^\./}, '') }
        .reject(&:empty?)
        .to_set
  end

  def self.executed_files(xml_paths)
    JunitToRuntimeLog.aggregate_times(xml_paths).keys.to_set
  end

  # Files where every top-level example group is excluded (e.g. `:skip` metadata,
  # a shared_examples-only file with no describe of its own, or a describe wrapped
  # in an `if ENV[...]` guard that's false in CI) legitimately register zero
  # examples and would otherwise show up as false-positive gaps. An RSpec --dry-run
  # pass applies the exact same filtering as a real run (e.g. `exclude {skip: true}`)
  # without executing anything, so any file with a testcase there is genuinely
  # expected to produce one for real. This must use RspecJunitFormatter (same as the
  # real run), NOT RSpec's --format json: the two formatters disagree on which file
  # `it_behaves_like` examples belong to (JSON credits the shared_examples-defining
  # file; JUnit credits the calling file), so mixing them misclassifies real gaps.
  def self.expected_files(dry_run_xml_paths)
    return nil if dry_run_xml_paths.nil? || dry_run_xml_paths.empty? # rubocop:disable Rails/Blank -- runs standalone, no ActiveSupport

    JunitToRuntimeLog.aggregate_times(dry_run_xml_paths).keys.to_set
  end

  def self.missing_files(union_manifest_path, xml_paths, dry_run_xml_paths: nil)
    gap = assigned_files(union_manifest_path) - executed_files(xml_paths)
    expected = expected_files(dry_run_xml_paths)
    gap &= expected unless expected.nil?
    gap.to_a.sort
  end

  def self.report(missing, assigned_count, summary_path: ENV.fetch('GITHUB_STEP_SUMMARY', nil))
    if missing.empty?
      message = "Shard completeness check passed: all #{assigned_count} assigned spec files were executed."
      puts message
      append_summary(summary_path) { |f| f.puts "\n#{message}\n" }
      return
    end

    warn "Possible sharding or execution gap: #{missing.size} of #{assigned_count} " \
         'assigned spec files were never executed:'
    missing.each { |file| warn "  #{file}" }

    append_summary(summary_path) do |f|
      f.puts "\n### :warning: Possible sharding or execution gap"
      f.puts "#{missing.size} of #{assigned_count} assigned spec files were never executed:\n"
      f.puts '```'
      missing.each { |file| f.puts file }
      f.puts '```'
    end
  end

  def self.append_summary(summary_path, &)
    return unless summary_path

    File.open(summary_path, 'a', &)
  end
end

if __FILE__ == $PROGRAM_NAME
  union_manifest = ARGV[0]
  xml_glob = ARGV[1]
  dry_run_xml_glob = ARGV[2]

  if union_manifest.nil? || !File.exist?(union_manifest)
    warn "Union manifest not found: #{union_manifest.inspect}; skipping completeness check"
    exit 0
  end

  assigned = ShardCompleteness.assigned_files(union_manifest)
  dry_run_xml_paths = dry_run_xml_glob.nil? ? nil : Dir.glob(dry_run_xml_glob)
  missing = ShardCompleteness.missing_files(union_manifest, Dir.glob(xml_glob), dry_run_xml_paths:)
  ShardCompleteness.report(missing, assigned.size)
end
