# frozen_string_literal: true

# Supplemental Claim (20-0995) SavedClaim lookup — drive from a Rails console.
#
# For every submission matching a form-data filter over a date range, uploads a
# summary table (veteran file-number/SSN + SavedClaim metadata) plus one JSON per
# submission (the full saved form) to S3. The saved form holds both the 0995
# (data.attributes) and, when present, the 4142 (form4142) data, so it can be
# used to validate the generated PDFs.
#
# A submission id (AppealsApi::SupplementalClaim#id) is the same UUID stored as
# SavedClaim::SupplementalClaim#guid on the VA.gov submission path, so both
# records are looked up from the same id.
#
#   ScSavedClaimLookup.run(
#     since_date: '2026-07-28',
#     limit: 5,
#     batch_size: 50,
#     filter: ScSavedClaimLookup::Filters::MIN_RETRIEVE_FROM.(4),
#     filter_label: 'scRedesign AND retrieveFrom>=4'
#   )
#
# ---------------------------------------------------------------------------
# COST MODEL — why this is structured the way it is
# ---------------------------------------------------------------------------
# SavedClaim#form and AppealsApi::SupplementalClaim#auth_headers/#form_data are
# Lockbox-encrypted with a PER-ROW KMS data key (`encrypted_kms_key`). Reading
# any of them costs one AWS KMS Decrypt round-trip for that row, and the gem
# caches the key only on the record instance. So:
#
#   wall clock ~= (KMS round-trips) x (KMS latency)
#
# The filter CANNOT be pushed into SQL, because `form` is ciphertext in the
# database: every candidate row in the window must come back and be decrypted.
# What this class does about that:
#
#   1. Decrypts each claim ONCE. The scan hands the loaded record and its parsed
#      form straight to the report, rather than re-querying by guid and parsing
#      a second time.
#   2. Overlaps the KMS calls on a thread pool (:threads, default 16). Decrypt is
#      network I/O, so MRI releases the GVL and this scales close to linearly.
#      Worker threads never touch the database, so the ActiveRecord pool
#      (default 5) is not a constraint.
#   3. Batches the AppealsApi lookup into one `where(id: [...])` per slice, with
#      the auth_headers decrypt parallelized alongside.
#   4. Uploads to S3 in parallel against one shared client.
#   5. SELECTs only the columns it reads, so the often-large `metadata` text
#      column is not dragged over the wire.
#   6. Memoizes the scan on the instance, so re-filtering costs no KMS at all
#      (see #scan / #gather below).
#
# ---------------------------------------------------------------------------
# TWO WAYS TO USE IT
# ---------------------------------------------------------------------------
# One-shot (memory-lean: the scan retains only matches):
#
#   ScSavedClaimLookup.run(since_date: '2026-07-28', filter: f, filter_label: 'f')
#
# Explore (decrypt the window once, then try thresholds for free):
#
#   lookup = ScSavedClaimLookup.new(since_date: '2026-07-28')
#   lookup.scan                                      # the expensive part, once
#   lookup.gather(filter: a, filter_label: 'a')      # no KMS cost
#   lookup.gather(filter: b, filter_label: 'b')      # no KMS cost
#
# #scan and #run own separate results, on purpose. #scan caches the window for
# #gather to re-filter; #run is narrowed by its own filter and never writes that
# cache, because doing so would silently scope every later #gather to whatever
# #run happened to match. So this is honest, not a subset of a subset:
#
#   lookup.run(filter: F::SC_REDESIGN, filter_label: 'redesign')
#   lookup.gather(filter: F::HAS_FORM4142, filter_label: 'has 4142')  # full window
#
# The second call rescans (nothing was cached), which costs KMS. Call #scan
# first when you intend to re-filter.
#
# You CAN narrow the cache deliberately, to cap memory on a wide window, but the
# label is then required and is echoed in the #gather line and recorded in the
# S3 report header, so the subset is never invisible:
#
#   lookup.scan(filter: F::SC_REDESIGN, filter_label: 'redesign')
#   lookup.gather(filter: F::MIN_RETRIEVE_FROM.(4), filter_label: 'retrieveFrom>=4')
#   #=> "12 of 40 claim(s) in the 'redesign' scan match: retrieveFrom>=4"
#
# NOTE: an unfiltered #scan holds every parsed form in memory. On a wide window
# that is large. Prefer .run, or pass :limit, if that matters.
#
# ---------------------------------------------------------------------------
# PII — NOTHING DECRYPTED IS EVER PRINTED
# ---------------------------------------------------------------------------
# A Rails console keeps everything in scrollback, and IRB echoes the value of
# every expression, so "don't print it" has to be a property of the code, not a
# habit of the caller. There is no `; nil` to remember. Specifically:
#
#   * #run / #gather return a Result (counts, S3 keys), never the claim data.
#     The hash holding file numbers, SSNs and form payloads is local to #report
#     and is unreachable once the call returns.
#   * #scan returns SELF, not the decrypted pairs. They live in @scan, which is
#     private; #scanned_count exposes only how many there are.
#   * #inspect is overridden on BOTH this class and Result, so echoing the
#     lookup object itself renders config and a count, never @scan. (Ruby's
#     default #inspect dumps every ivar, which would have printed the lot.)
#   * The summary table is built for S3 only and never echoed.
#   * Progress lines, upload lines and error paths carry counts, UUIDs, S3 keys
#     and exception classes only.
#
# The remaining exposure is deliberate circumvention (instance_variable_get, or
# a debugger). If you add a public method here, make sure it cannot return a
# parsed form.
class ScSavedClaimLookup
  # ---------------------------------------------------------------------------
  # Configuration — every key below is settable via the options hash.
  # ---------------------------------------------------------------------------
  # since_date   : REQUIRED. String ('2026-07-01'), Date, or Time. Lower bound on
  #                created_at, inclusive.
  # end_date     : upper bound on created_at, inclusive. Defaults to now.
  #                CAREFUL: a bare date parses to MIDNIGHT at the start of that
  #                day, so '2026-08-01' stops at 2026-08-01T00:00:00. Pass an
  #                end-of-day Time ('2026-08-01T23:59:59') for a full last day.
  # filter       : callable over the parsed form Hash. See Filters below. May be
  #                supplied here or per call to #run / #gather.
  # filter_label : String describing the filter; recorded in the report header
  #                (filters are lambdas and cannot describe themselves).
  # limit        : cap on retained matches. The scan stops at the first BATCH
  #                BOUNDARY past this count, so it can decrypt up to
  #                batch_size - 1 extra rows before trimming. Pair a small limit
  #                with a small batch_size.
  # threads      : pool size for KMS decrypt / JSON parse / S3 puts. I/O bound,
  #                so it can exceed core count.
  # batch_size   : rows fetched from Postgres per round, and the granularity of
  #                the limit early-exit.
  # dry_run      : true prints progress only; false uploads to S3.
  DEFAULTS = {
    since_date: nil,
    end_date: nil,
    filter: nil,
    filter_label: nil,
    limit: nil,
    threads: 16,
    batch_size: 50,
    dry_run: true
  }.freeze

  # Only the columns this class reads. `form_id` must be included: SavedClaim's
  # after_initialize assigns it, which raises on a partial select that omits it.
  # `guid` likewise (SetGuid), `type` for STI, and the two ciphertext columns for
  # the decrypt itself.
  SCAN_COLUMNS = %i[
    id guid type form_id created_at uploaded_forms form_ciphertext encrypted_kms_key
  ].freeze

  ROW_FORMAT = '%-38s  %-20s  %-11s  %-9s  %-25s  %-11s  %-16s  %s'
  ROW_HEADERS = %w[submission_id value source saved_claim created_at sc_redesign
                   should_have_4142 uploaded_forms].freeze
  S3_ROOT = 'reports/supplemental-claims/file-number-lookups'
  # How many individual upload failures to name before collapsing to a count.
  SHOWN_FAILURES = 10

  # Wraps a per-item failure inside a worker thread, so one bad record never
  # takes down the whole run.
  Failure = Struct.new(:item, :error)

  # What #run / #gather hand back. Deliberately carries COUNTS AND KEYS ONLY, no
  # claim data: it is the value IRB echoes at the prompt, so anything on it is
  # printed to the console. See the "PII" note on the class above.
  Result = Struct.new(:matched, :examined, :uploaded, :failed, :s3_prefix, :dry_run,
                      keyword_init: true) do
    def inspect
      parts = ["matched=#{matched}", "examined=#{examined}"]
      parts << (dry_run ? 'dry_run (nothing uploaded)' : "uploaded=#{uploaded}")
      parts << "failed=#{failed}" if failed.to_i.positive?
      parts << "s3=#{s3_prefix}" if s3_prefix
      "#<#{self.class.name} #{parts.join(' ')}>"
    end
    alias_method :to_s, :inspect
  end

  # ---------------------------------------------------------------------------
  # Form-data filters
  # ---------------------------------------------------------------------------
  # A filter is any callable taking the parsed form Hash and returning truthy to
  # include the claim. Plain filters are used directly; MIN_* builders are called
  # with a threshold first. (`.()` == `.call()`.) Combine with ALL_OF / ANY_OF.
  # dig / Array() are used so a missing key means "no match" rather than raising.
  #
  #   F = ScSavedClaimLookup::Filters
  #   F::ALL_OF.(F::SC_REDESIGN, F::HAS_FORM4142)
  #   F::ANY_OF.(F::MIN_RETRIEVE_FROM.(4), F::MIN_PROVIDER_FACILITIES.(6))
  module Filters
    ALL_OF = ->(*filters) { ->(form) { filters.all? { |f| f.call(form) } } }
    ANY_OF = ->(*filters) { ->(form) { filters.any? { |f| f.call(form) } } }

    # Redesign submissions (form['scRedesign'] == true).
    SC_REDESIGN = ->(form) { ActiveModel::Type::Boolean.new.cast(form['scRedesign']) }

    # A 4142 was included in the submission. Both submission paths.
    HAS_FORM4142 = ->(form) { form['form4142'].present? }

    # The next two AND in SC_REDESIGN, so they only match redesign submissions.
    # Redesign AND evidenceSubmission.retrieveFrom has >= min entries.
    MIN_RETRIEVE_FROM = lambda do |min = 3|
      ALL_OF.call(SC_REDESIGN, lambda { |form|
        Array(form.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')).size >= min
      })
    end

    # Redesign AND form4142.providerFacility has >= min entries.
    MIN_PROVIDER_FACILITIES = lambda do |min = 5|
      ALL_OF.call(SC_REDESIGN, lambda { |form|
        Array(form.dig('form4142', 'providerFacility')).size >= min
      })
    end

    # Top-level `included` (contestable issues) has >= min entries. Both paths,
    # so not tied to SC_REDESIGN.
    MIN_CONTESTABLE_ISSUES = ->(min = 9) { ->(form) { Array(form['included']).size >= min } }
  end

  attr_reader :options

  # Convenience for the one-shot case.
  def self.run(options = {})
    new(options).run
  end

  def initialize(options = {})
    opts = options.to_h.transform_keys(&:to_sym)
    unknown = opts.keys - DEFAULTS.keys
    raise ArgumentError, "unknown option(s): #{unknown.join(', ')}" if unknown.any?

    @options = DEFAULTS.merge(opts)
    raise ArgumentError, 'since_date is required' if @options[:since_date].nil?
  end

  # A copy of this lookup with some options changed.
  def with(**overrides)
    self.class.new(options.merge(overrides))
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  # One-shot: scan the window with the filter applied inline (so only matches are
  # retained), then build and deliver the report. Returns the claim data hash
  # keyed by submission id, or {} when nothing matched.
  def run(filter: options[:filter], filter_label: options[:filter_label])
    validate_filter!(filter, filter_label)
    # Deliberately does NOT populate the #scan cache. These results are narrowed
    # by `filter`, so caching them would silently scope every later #gather to
    # that subset. A #gather after a #run scans the window afresh.
    matches = perform_scan(filter)
    count = matches.size
    puts "Found #{count} matching SavedClaim(s) created #{range_description}."
    report(matches, criteria_for(filter_label, count))
  end

  # Decrypt the window once and memoize the result on this instance. Returns
  # [[saved_claim, parsed_form], ...]. Pass a filter to retain only matches;
  # omit it to keep everything so #gather can re-filter for free.
  # Returns SELF, not the pairs: the decrypted forms must never become the value
  # IRB echoes. They are held privately and consumed by #gather / #run.
  def scan(filter: nil, filter_label: nil, force: false)
    raise ArgumentError, 'filter_label is required when a filter narrows the scan' if filter && filter_label.blank?
    return self if @scan && !force

    # Remembered so #gather can say, in both the console line and the S3 report
    # header, that its results are relative to a narrowed window.
    @scan_scope = filter_label
    @scan = perform_scan(filter)
    self
  end

  # How many claims the last scan retained. The claims themselves are private.
  def scanned_count = @scan&.size

  # Re-filter the memoized scan and deliver a report. Costs no KMS calls, so this
  # is the cheap way to try different thresholds. Triggers an unfiltered #scan
  # first if none has run.
  def gather(filter: options[:filter], filter_label: options[:filter_label])
    validate_filter!(filter, filter_label)
    pairs = cached_scan
    matches = apply_limit(pairs.select { |(_saved_claim, form)| filter.call(form) })
    count = matches.size
    puts "#{count} of #{pairs.size} #{scope_noun} match: #{filter_label}"
    report(matches, criteria_for(filter_label, count, scope: @scan_scope))
  end

  # Safe to echo: never renders @scan, which holds decrypted forms.
  def inspect
    shown = options.slice(:since_date, :end_date, :limit, :threads, :batch_size, :dry_run)
    state = @scan ? "scanned=#{@scan.size}" : 'not scanned'
    "#<#{self.class.name} #{shown.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')} #{state}>"
  end
  alias to_s inspect

  def threads = options[:threads]
  def batch_size = options[:batch_size]
  def limit = options[:limit]
  def dry_run? = options[:dry_run]

  def since_time
    @since_time ||= to_time(options[:since_date])
  end

  def end_time
    @end_time ||= options[:end_date] ? to_time(options[:end_date]) : Time.current
  end

  def range_description
    "between #{since_time.utc.iso8601} and #{end_time.utc.iso8601}"
  end

  private

  def validate_filter!(filter, filter_label)
    raise ArgumentError, 'filter is required' if filter.nil?
    raise ArgumentError, 'filter_label is required' if filter_label.blank?
  end

  def apply_limit(matches)
    limit ? matches.first(limit) : matches
  end

  def to_time(value)
    value.respond_to?(:to_time) ? value.to_time : Time.zone.parse(value.to_s)
  end

  # ---------------------------------------------------------------------------
  # Scan
  # ---------------------------------------------------------------------------

  def base_scope
    ::SavedClaim::SupplementalClaim
      .where('created_at >= ?', since_time)
      .where('created_at <= ?', end_time)
  end

  def perform_scan(filter)
    scope = base_scope
    total = scope.count
    puts "Scanning #{total} SavedClaim(s) created #{range_description} " \
         "(#{threads} threads, batches of #{batch_size})..."
    return [] if total.zero?

    state = { matches: [], examined: 0, errors: 0, started: monotonic_now, total: }
    scope.select(SCAN_COLUMNS).find_in_batches(batch_size:) do |batch|
      process_batch(batch, filter, state)
      break if limit && state[:matches].size >= limit
    end
    finish_scan(state)
  end

  def process_batch(batch, filter, state)
    # The expensive part: one KMS Decrypt per record, overlapped across threads.
    forms = parallel_map(batch) { |saved_claim| parse_form(saved_claim) }
    state[:errors] += collect_matches(batch, forms, filter, state[:matches])
    state[:examined] += batch.size
    report_progress("scanned #{state[:matches].size} matched",
                    state[:examined], state[:total], state[:started])
  end

  def collect_matches(batch, forms, filter, matches)
    errors = 0
    batch.each_with_index do |saved_claim, i|
      form = forms[i]
      if form.is_a?(Failure) || !form.is_a?(Hash) || form.key?('_parse_error')
        errors += 1
        next
      end
      next if filter && !filter.call(form)

      matches << [saved_claim, form]
    end
    errors
  end

  # Triggers an unfiltered scan if none is cached. Private: the pairs hold
  # decrypted forms and must not be reachable from the console.
  def cached_scan
    scan unless @scan
    @scan
  end

  # Names what #gather just filtered over, so a narrowed cache is never silent.
  def scope_noun
    @scan_scope ? "claim(s) in the '#{@scan_scope}' scan" : 'scanned claim(s)'
  end

  def finish_scan(state)
    @examined = state[:examined]
    matches = apply_limit(state[:matches])
    puts "Scan complete in #{duration(monotonic_now - state[:started])}: " \
         "#{matches.size} retained, #{state[:errors]} unparseable, #{state[:examined]} examined."
    matches
  end

  # Decrypt + parse one SavedClaim. Never raises; a failure becomes a form hash
  # carrying '_parse_error'.
  def parse_form(saved_claim)
    saved_claim.parsed_form
  rescue => e
    { '_parse_error' => e.message }
  end

  # ---------------------------------------------------------------------------
  # Report
  # ---------------------------------------------------------------------------

  # `data` never escapes this method: it holds file numbers, SSNs and full form
  # payloads. Only the Result (counts + S3 keys) is handed back to the caller.
  def report(matches, criteria)
    return Result.new(matched: 0, examined: @examined, dry_run: dry_run?) if matches.empty?

    entries = matches.map { |(saved_claim, form)| { id: saved_claim.guid, saved_claim:, form: } }
    data = build_data(entries, resolve_identifiers(entries))
    text = summary_text(data, criteria)
    puts "\nBuilt summary table for #{entries.size} submission(s)."
    deliver(text, data)
  end

  def deliver(text, data)
    if dry_run?
      puts "\n(dry_run) Skipping S3 upload."
      return Result.new(matched: data.size, examined: @examined, dry_run: true)
    end

    upload = upload_to_s3(text, data) || { prefix: nil, uploaded: 0, failed: data.size }
    Result.new(matched: data.size, examined: @examined, dry_run: false,
               uploaded: upload[:uploaded], failed: upload[:failed], s3_prefix: upload[:prefix])
  end

  # `scope` records that the cached scan was itself narrowed, so a reader of the
  # S3 report can tell the match count is relative to a subset of the window.
  def criteria_for(filter_label, count, scope: nil)
    ["Created #{range_description}",
     *("Scan narrowed to: #{scope}" if scope),
     "Filter: #{filter_label}",
     "Matched: #{count} submission(s)"]
  end

  def build_data(entries, identifiers)
    entries.each_with_index.to_h do |entry, i|
      [entry[:id], claim_record(entry, identifiers[i])]
    end
  end

  def claim_record(entry, identifier)
    identifier = ['-', 'error'] if identifier.is_a?(Failure)
    value, source = identifier
    saved_claim = entry[:saved_claim]
    return { found: false, file_number_value: value, file_number_source: source } if saved_claim.nil?

    found_record(saved_claim, entry[:form] || {}, value, source)
  end

  def found_record(saved_claim, form, value, source)
    {
      found: true,
      file_number_value: value,
      file_number_source: source,
      saved_claim_id: saved_claim.id,
      guid: saved_claim.guid,
      created_at: saved_claim.created_at&.utc&.iso8601,
      sc_redesign: ActiveModel::Type::Boolean.new.cast(form['scRedesign']) || false,
      uploaded_forms: Array(saved_claim.uploaded_forms),
      should_have_form4142: form.key?('form4142'), # form4142 was in the payload at submission
      form: # 0995 (data.attributes) + form4142 (when present)
    }
  end

  # The table carries veteran file numbers / SSNs, so it is never echoed to the
  # console (a session keeps them in scrollback). Its only destination is S3.
  def summary_text(data, criteria)
    header = ['# SavedClaim summary',
              "# Generated (UTC): #{Time.now.utc.iso8601}",
              *criteria.map { |c| "# #{c}" },
              '',
              format(ROW_FORMAT, *ROW_HEADERS),
              '-' * 165]
    (header + data.map { |id, claim| summary_row(id, claim) }).join("\n")
  end

  def summary_row(submission_id, claim)
    unless claim[:found]
      return format(ROW_FORMAT, submission_id, claim[:file_number_value],
                    claim[:file_number_source], 'not found', '-', '-', '-', '-')
    end

    format(ROW_FORMAT, submission_id, claim[:file_number_value], claim[:file_number_source],
           'found', claim[:created_at].to_s, claim[:sc_redesign].to_s,
           claim[:should_have_form4142].to_s,
           (claim[:uploaded_forms].presence || ['-']).join(','))
  end

  # ---------------------------------------------------------------------------
  # Veteran identifiers (AppealsApi side)
  # ---------------------------------------------------------------------------

  def resolve_identifiers(entries)
    started = monotonic_now
    puts "Resolving veteran identifiers for #{entries.size} submission(s)..."
    appeals = load_appeals_submissions(entries.map { |e| e[:id] })
    identifiers = parallel_map(entries) { |entry| veteran_identifier(appeals[entry[:id]]) }
    puts "  done in #{duration(monotonic_now - started)}."
    identifiers
  end

  # One `where(id: [...])` per slice, instead of a find per submission.
  def load_appeals_submissions(ids)
    return {} if ids.empty?

    ids.each_slice(batch_size).with_object({}) do |slice, acc|
      AppealsApi::SupplementalClaim.where(id: slice).find_each { |record| acc[record.id] = record }
    end
  end

  # [value, source] for an already-loaded AppealsApi::SupplementalClaim. Prefers
  # the file number (record or auth header), then SSN. Reading .veteran /
  # .auth_headers is what triggers this record's KMS decrypt, so callers run it
  # on the thread pool.
  def veteran_identifier(submission)
    return ['-', 'not found'] if submission.nil?

    file_number = submission.veteran.file_number.presence ||
                  submission.auth_headers&.dig('X-VA-File-Number').presence
    return [file_number, 'file_number'] if file_number

    ssn = submission.veteran.ssn.presence || submission.auth_headers&.dig('X-VA-SSN').presence
    return [ssn, 'ssn'] if ssn

    ['-', 'none']
  rescue => e
    ['-', "error: #{e.class}"]
  end

  # ---------------------------------------------------------------------------
  # S3
  # ---------------------------------------------------------------------------

  def upload_to_s3(summary_text, data)
    prefix = "#{S3_ROOT}/#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}"
    bucket_name = Settings.reports.aws.bucket
    bucket = s3_bucket(bucket_name)
    bucket.object("#{prefix}/supplemental-claims-saved-claim-summary.txt").put(body: summary_text)

    started = monotonic_now
    puts "\nUploading #{data.size} saved claim file(s) to S3..."
    results = parallel_map(data.to_a) do |(submission_id, claim)|
      bucket.object("#{prefix}/saved_claims/#{submission_id}.json")
            .put(body: JSON.pretty_generate(claim))
      submission_id
    end
    report_upload(results, bucket_name, prefix, started)
    { prefix:, uploaded: results.count { |r| !r.is_a?(Failure) },
      failed: results.count { |r| r.is_a?(Failure) } }
  rescue => e
    # e.message is an AWS error (bucket/key/credentials); it carries no claim data.
    puts "\n✗ Failed to upload to S3: #{e.message}"
    puts '  (Nothing was saved locally -- fix the cause and re-run.)'
    nil
  end

  def s3_bucket(bucket_name)
    Aws::S3::Resource.new(
      region: Settings.reports.aws.region,
      access_key_id: Settings.reports.aws.access_key_id,
      secret_access_key: Settings.reports.aws.secret_access_key
    ).bucket(bucket_name)
  end

  def report_upload(results, bucket_name, prefix, started)
    failures = results.select { |r| r.is_a?(Failure) }
    failed_count = failures.size
    puts "\n✓ Output uploaded to S3 in #{duration(monotonic_now - started)}:"
    puts "  s3://#{bucket_name}/#{prefix}/  " \
         "(summary + #{results.size - failed_count} claim file(s))"
    return if failed_count.zero?

    puts "\n✗ #{failed_count} file(s) failed to upload:"
    failures.first(SHOWN_FAILURES).each { |f| puts "  #{f.item.first}: #{f.error.message}" }
    puts "  ... and #{failed_count - SHOWN_FAILURES} more" if failed_count > SHOWN_FAILURES
  end

  # ---------------------------------------------------------------------------
  # Concurrency + progress
  # ---------------------------------------------------------------------------

  # Maps items over a fixed thread pool, preserving input order. Any item that
  # raises comes back as a Failure. Blocks must NOT do database work: the AR
  # connection pool defaults to 5 and would become the bottleneck.
  def parallel_map(items, &block)
    items = items.to_a
    pool_size = [threads, items.size].min
    # Guarded here too, so failure isolation does not depend on how many items
    # happened to land in the batch.
    return items.map { |item| guarded(item, &block) } if pool_size <= 1

    results = Array.new(items.size)
    queue = Queue.new
    items.each_with_index { |item, idx| queue << [item, idx] }
    pool_size.times { queue << nil } # one stop sentinel per worker
    join_workers(Array.new(pool_size) { worker_thread(queue, results, block) })
    results
  end

  # rubocop:disable ThreadSafety/NewThread -- deliberate: overlapping the per-row
  # KMS Decrypt round-trips is the whole point of this class. These are short-lived
  # workers off a bounded queue, joined by #join_workers before anything reads the
  # results, and they touch no shared mutable state (each writes a distinct index)
  # and no database connection.
  def worker_thread(queue, results, block)
    Thread.new do
      # executor.wrap keeps autoloading thread-safe and returns anything checked out.
      Rails.application.executor.wrap do
        while (job = queue.pop)
          item, idx = job
          results[idx] = guarded(item, &block)
        end
      end
    end
  end

  # One item's worth of work, with a raise turned into a Failure so a single bad
  # record never takes down the batch.
  def guarded(item)
    yield item
  rescue => e
    Failure.new(item, e)
  end

  def join_workers(workers)
    workers.each(&:join)
    workers
  rescue Exception # rubocop:disable Lint/RescueException -- includes Interrupt (Ctrl-C)
    workers.each(&:kill)
    raise
  end
  # rubocop:enable ThreadSafety/NewThread

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def duration(seconds)
    seconds = seconds.round
    return "#{seconds}s" if seconds < 60
    return format('%<min>dm%<sec>02ds', min: seconds / 60, sec: seconds % 60) if seconds < 3600

    format('%<hr>dh%<min>02dm', hr: seconds / 3600, min: (seconds % 3600) / 60)
  end

  def report_progress(label, done, total, started)
    elapsed = monotonic_now - started
    rate = elapsed.positive? ? done / elapsed : 0.0
    parts = ["  #{label}: #{done}#{total ? "/#{total}" : ''}"]
    parts << format('%.0f/s', rate) if rate.positive?
    parts << "elapsed #{duration(elapsed)}"
    parts << "eta #{duration((total - done) / rate)}" if total && rate.positive? && done < total
    puts parts.join('  |  ')
  end
end

# ---------------------------------------------------------------------------
# Recipes — paste into a Rails console.
# ---------------------------------------------------------------------------
# MUST STAY COMMENTED OUT. This file lives in lib/tasks/support/, and the
# Rakefile does:
#
#   Rails.root.glob('lib/tasks/support/**/*.rb').each { |f| require f }
#
# so it loads on EVERY rake invocation (rake -T, db:migrate, CI, deploys). Any
# bare call left uncommented here would run a full scan on all of them.
#
# F = ScSavedClaimLookup::Filters
#
# --- One-shot, five matches, dry run ----------------------------------------
# result = ScSavedClaimLookup.run(
#   since_date: '2026-07-28',
#   limit: 5,
#   batch_size: 50,
#   filter: ScSavedClaimLookup::Filters::MIN_RETRIEVE_FROM.(4),
#   filter_label: 'scRedesign AND retrieveFrom>=4'
# )
#
# --- Two sets, one scan, no second decrypt ----------------------------------
# Scanning once and re-filtering beats two .run calls, which would each decrypt
# the window independently.
#
# lookup = ScSavedClaimLookup.new(since_date: '2026-07-28', batch_size: 50)
# lookup.scan                                     # the expensive part, once
# lookup.gather(filter: ScSavedClaimLookup::Filters::MIN_RETRIEVE_FROM.(4),
#               filter_label: 'scRedesign AND retrieveFrom>=4')
# lookup.gather(filter: ScSavedClaimLookup::Filters::MIN_PROVIDER_FACILITIES.(6),
#               filter_label: 'scRedesign AND providerFacility>=6')
#
# --- Derive a variant without re-typing the config --------------------------
# uploader = lookup.with(dry_run: false)
# uploader.gather(filter: ScSavedClaimLookup::Filters::HAS_FORM4142, filter_label: 'has form4142')
#
# --- Bounded window, full last day, upload to S3 ----------------------------
# ScSavedClaimLookup.run(
#   since_date: '2026-07-01',
#   end_date: '2026-07-31T23:59:59',
#   dry_run: false,
#   threads: 32,
#   filter: ScSavedClaimLookup::Filters::SC_REDESIGN,
#   filter_label: 'July scRedesign'
# )
#
# --- Reading the summary table ----------------------------------------------
# It is never echoed to the console (it carries file numbers / SSNs). Read it
# from S3 after a dry_run: false run. Under dry_run it is built and discarded.
#
# No `; nil` needed on any call above: see the PII note on the class. Every
# public return value is counts-and-keys only.
