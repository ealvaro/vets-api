# frozen_string_literal: true

require 'rails_helper'
require './lib/tasks/support/sc_saved_claim_lookup'

RSpec.describe ScSavedClaimLookup do
  subject(:lookup) { described_class.new(since_date:) }

  # A value planted inside a claim's form. If it ever shows up in console output
  # or in a public return value, the PII guarantee is broken.
  let(:sentinel) { 'SENTINEL-PII-VALUE' }
  let(:since_date) { '2026-07-01' }
  let(:in_window) { Time.zone.parse('2026-07-15T12:00:00') }
  let(:captured) { StringIO.new }

  # The class narrates progress to stdout across many calls per example. Swapping
  # the stream keeps the suite quiet AND lets any example assert on what a console
  # operator would have seen; the one-shot `output` matcher cannot do both.
  # rubocop:disable RSpec/ExpectOutput
  around do |example|
    original = $stdout
    $stdout = captured
    example.run
  ensure
    $stdout = original
  end
  # rubocop:enable RSpec/ExpectOutput

  def console
    captured.string
  end

  # --------------------------------------------------------------------------
  # Fixtures
  # --------------------------------------------------------------------------

  # The parsed-form shape the filters read. form4142 is only present when the
  # claim actually has provider facilities, mirroring a real submission.
  def form_hash(redesign: true, retrieve_from: 0, provider_facilities: 0, included: 0, extra: {})
    form = {
      'scRedesign' => redesign,
      'data' => { 'attributes' => { 'evidenceSubmission' => {
        'retrieveFrom' => Array.new(retrieve_from) { { 'type' => 'retrievalEvidence' } }
      } } },
      'included' => Array.new(included) { { 'type' => 'contestableIssue' } }
    }.merge(extra)
    if provider_facilities.positive?
      form['form4142'] = { 'providerFacility' => Array.new(provider_facilities) { { 'providerFacilityName' => 'X' } } }
    end
    form
  end

  # A SavedClaim inside the scan window, plus the matching AppealsApi record when
  # auth headers are supplied. A submission id is the same UUID as the
  # SavedClaim guid, which is what lets the class join the two.
  def create_claim(created_at: in_window, auth_headers: nil, **form_opts)
    guid = SecureRandom.uuid
    create(:supplemental_claim, id: guid, auth_headers:) if auth_headers
    create(:saved_claim_supplemental_claim, guid:, created_at:, form: form_hash(**form_opts).to_json)
  end

  # Filters live in a nested module and the MIN_* ones are builders, so resolve
  # them by name to keep the parameterized tables below readable. Named
  # absolutely because `described_class` is the Filters module itself inside the
  # filter example group.
  def filter_for(name, threshold = nil)
    const = ScSavedClaimLookup::Filters.const_get(name)
    threshold ? const.call(threshold) : const
  end

  def gather_with(name, threshold = nil, label: name.to_s)
    lookup.gather(filter: filter_for(name, threshold), filter_label: label)
  end

  # --------------------------------------------------------------------------
  # Configuration
  # --------------------------------------------------------------------------
  describe 'configuration' do
    { threads: 16, batch_size: 50, dry_run: true, limit: nil, end_date: nil, filter: nil }.each do |key, value|
      it "defaults #{key} to #{value.inspect}" do
        expect(lookup.options[key]).to eq(value)
      end
    end

    [
      [{}, 'since_date is required'],
      [{ since_date: '2026-07-01', treads: 4 }, 'unknown option(s): treads'],
      [{ since_date: '2026-07-01', threads: 4, batch_sizes: 10 }, 'unknown option(s): batch_sizes']
    ].each do |options, message|
      it "rejects #{options.inspect} with #{message.inspect}" do
        expect { described_class.new(options) }.to raise_error(ArgumentError, /#{Regexp.escape(message)}/)
      end
    end

    it 'accepts string keys' do
      expect(described_class.new('since_date' => since_date, 'threads' => 4).threads).to eq(4)
    end

    it 'exposes overrides through the readers' do
      configured = described_class.new(since_date:, threads: 4, batch_size: 7, limit: 3, dry_run: false)

      expect([configured.threads, configured.batch_size, configured.limit, configured.dry_run?])
        .to eq([4, 7, 3, false])
    end

    describe '#with' do
      it 'derives a copy carrying the overrides' do
        derived = lookup.with(dry_run: false, threads: 32)

        expect([derived.dry_run?, derived.threads, derived.options[:since_date]])
          .to eq([false, 32, since_date])
      end

      it 'leaves the original untouched' do
        lookup.with(dry_run: false, threads: 32)

        expect([lookup.dry_run?, lookup.threads]).to eq([true, 16])
      end
    end

    describe 'date handling' do
      it 'defaults end_time to now' do
        expect(lookup.end_time).to be_within(5.seconds).of(Time.current)
      end

      it 'honours an explicit end_date' do
        bounded = described_class.new(since_date:, end_date: Time.zone.parse('2026-07-31T23:59:59'))

        expect(bounded.end_time.utc.iso8601).to eq('2026-07-31T23:59:59Z')
      end

      # A String goes through ActiveSupport's String#to_time, which parses in the
      # SYSTEM zone rather than Time.zone. Documented here because it shifts the
      # window boundary for anyone running a console outside UTC.
      it 'parses a String end_date in the system zone' do
        bounded = described_class.new(since_date:, end_date: '2026-07-31T23:59:59')

        # rubocop:disable Rails/TimeZone -- asserting exactly the non-zone-aware parse
        expect(bounded.end_time).to eq('2026-07-31T23:59:59'.to_time)
        # rubocop:enable Rails/TimeZone
      end

      it 'describes the range for the report header' do
        expect(lookup.range_description).to match(/\Abetween \S+ and \S+\z/)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Filters
  # --------------------------------------------------------------------------
  describe described_class::Filters do
    # [filter name, threshold, form attributes, expected match]
    [
      [:SC_REDESIGN, nil, { redesign: true }, true],
      [:SC_REDESIGN, nil, { redesign: false }, false],
      [:HAS_FORM4142, nil, { provider_facilities: 1 }, true],
      [:HAS_FORM4142, nil, { provider_facilities: 0 }, false],
      [:MIN_RETRIEVE_FROM, 4, { retrieve_from: 4 }, true],
      [:MIN_RETRIEVE_FROM, 4, { retrieve_from: 5 }, true],
      [:MIN_RETRIEVE_FROM, 4, { retrieve_from: 3 }, false],
      [:MIN_RETRIEVE_FROM, 4, { retrieve_from: 9, redesign: false }, false],
      [:MIN_PROVIDER_FACILITIES, 6, { provider_facilities: 6 }, true],
      [:MIN_PROVIDER_FACILITIES, 6, { provider_facilities: 5 }, false],
      [:MIN_PROVIDER_FACILITIES, 6, { provider_facilities: 9, redesign: false }, false],
      [:MIN_CONTESTABLE_ISSUES, 9, { included: 9 }, true],
      [:MIN_CONTESTABLE_ISSUES, 9, { included: 8 }, false],
      [:MIN_CONTESTABLE_ISSUES, 9, { included: 9, redesign: false }, true]
    ].each do |name, threshold, form_opts, expected|
      it "#{name}#{threshold ? "(#{threshold})" : ''} is #{expected} for #{form_opts}" do
        expect(filter_for(name, threshold).call(form_hash(**form_opts))).to eq(expected)
      end
    end

    it 'treats a form missing every key as a non-match rather than raising' do
      filters = %i[SC_REDESIGN HAS_FORM4142].map { |name| filter_for(name) } +
                [filter_for(:MIN_RETRIEVE_FROM, 1), filter_for(:MIN_PROVIDER_FACILITIES, 1)]

      expect(filters.map { |filter| filter.call({}) }).to all(be_falsey)
    end

    describe 'combinators' do
      let(:redesign_with_form4142) { form_hash(redesign: true, provider_facilities: 1) }

      it 'ALL_OF requires every filter' do
        all_of = described_class::ALL_OF.call(filter_for(:SC_REDESIGN), filter_for(:HAS_FORM4142))

        expect([all_of.call(redesign_with_form4142), all_of.call(form_hash(redesign: true))])
          .to eq([true, false])
      end

      it 'ANY_OF requires only one' do
        any_of = described_class::ANY_OF.call(filter_for(:HAS_FORM4142), filter_for(:MIN_CONTESTABLE_ISSUES, 9))

        expect([any_of.call(redesign_with_form4142), any_of.call(form_hash(redesign: true))])
          .to eq([true, false])
      end
    end
  end

  # --------------------------------------------------------------------------
  # Scan scoping. This is the contract that broke in review: #run is narrowed by
  # its own filter, so it must never become the cache that #gather re-filters.
  # --------------------------------------------------------------------------
  describe 'scan scoping' do
    # A: redesign + 4142   B: redesign only   C: 4142 only   D: neither
    before do
      create_claim(redesign: true, provider_facilities: 1)
      create_claim(redesign: true)
      create_claim(redesign: false, provider_facilities: 1)
      create_claim(redesign: false)
    end

    it 'sees every claim in the window when nothing is cached' do
      expect(gather_with(:HAS_FORM4142).matched).to eq(2)
    end

    context 'after a narrowed #run' do
      before { lookup.run(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign') }

      it 'does not populate the cache' do
        expect(lookup.scanned_count).to be_nil
      end

      it 'reports "not scanned" when inspected' do
        expect(lookup.inspect).to include('not scanned')
      end

      it 'still evaluates a later #gather against the whole window' do
        expect(gather_with(:HAS_FORM4142).matched).to eq(2)
      end

      it 'says so in the console line' do
        gather_with(:HAS_FORM4142)

        expect(console).to include('of 4 scanned claim(s)')
      end
    end

    context 'when the cache is deliberately narrowed' do
      before { lookup.scan(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign') }

      it 'scopes later gathers to the subset' do
        expect(gather_with(:HAS_FORM4142).matched).to eq(1)
      end

      it 'names the narrowing in the console line' do
        gather_with(:HAS_FORM4142)

        expect(console).to include("claim(s) in the 'redesign' scan")
      end

      it 'records the narrowing in the report criteria' do
        criteria = lookup.send(:criteria_for, 'has 4142', 1, scope: 'redesign')

        expect(criteria).to include('Scan narrowed to: redesign')
      end
    end

    it 'refuses to narrow the cache without a label' do
      expect { lookup.scan(filter: filter_for(:SC_REDESIGN)) }
        .to raise_error(ArgumentError, /filter_label is required/)
    end

    it 'omits the narrowing note when the cache is whole' do
      expect(lookup.send(:criteria_for, 'has 4142', 1)).not_to include(a_string_matching(/Scan narrowed/))
    end

    it 'decrypts once no matter how many gathers follow' do
      lookup.scan
      gather_with(:SC_REDESIGN)
      gather_with(:HAS_FORM4142)

      # The scan is the only thing that narrates "Scanning N SavedClaim(s)".
      expect(console.scan('SavedClaim(s) created').size).to eq(1)
    end

    it 'caches the whole window' do
      lookup.scan

      expect(lookup.scanned_count).to eq(4)
    end
  end

  # --------------------------------------------------------------------------
  # Scan mechanics
  # --------------------------------------------------------------------------
  describe '#scan' do
    it 'returns self so the decrypted pairs never become the console value' do
      create_claim

      expect(lookup.scan).to be(lookup)
    end

    it 'excludes claims outside the window' do
      create_claim(created_at: in_window)
      create_claim(created_at: Time.zone.parse('2026-06-01T12:00:00'))

      expect(lookup.scan.scanned_count).to eq(1)
    end

    it 'honours an end_date upper bound' do
      create_claim(created_at: Time.zone.parse('2026-07-15T12:00:00'))
      create_claim(created_at: Time.zone.parse('2026-08-15T12:00:00'))
      bounded = described_class.new(since_date:, end_date: '2026-07-31T23:59:59')

      expect(bounded.scan.scanned_count).to eq(1)
    end

    it 'skips unparseable forms instead of failing the run' do
      create_claim
      corrupt = create(:saved_claim_supplemental_claim, created_at: in_window)
      # rubocop:disable Rails/SkipsModelValidations -- deliberately planting an undecryptable row
      corrupt.update_column(:form_ciphertext, 'not-json')
      # rubocop:enable Rails/SkipsModelValidations

      expect(lookup.scan.scanned_count).to eq(1)
      expect(console).to include('1 unparseable')
    end

    it 'reports zero without scanning when the window is empty' do
      expect(lookup.scan.scanned_count).to eq(0)
    end

    describe 'limit' do
      before { 5.times { create_claim } }

      it 'caps what is retained' do
        limited = described_class.new(since_date:, limit: 2, batch_size: 1)

        expect(limited.scan.scanned_count).to eq(2)
      end

      it 'caps matches on the one-shot path' do
        limited = described_class.new(since_date:, limit: 2, batch_size: 1)

        expect(limited.run(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign').matched).to eq(2)
      end
    end
  end

  # --------------------------------------------------------------------------
  # PII
  # --------------------------------------------------------------------------
  describe 'PII containment' do
    before do
      create_claim(extra: { 'veteranSecret' => sentinel })
      lookup.scan
    end

    it 'keeps the decrypted form out of every callable public method' do
      leaky = described_class.public_instance_methods(false).select do |method|
        next false if described_class.instance_method(method).parameters.any? { |type, _| type == :req }

        begin
          lookup.public_send(method).inspect.include?(sentinel)
        rescue ArgumentError
          false # needs a filter (#run / #gather); covered by their own examples
        end
      end

      expect(leaky).to be_empty
    end

    it 'keeps it out of #inspect, which would otherwise dump every ivar' do
      expect(lookup.inspect).not_to include(sentinel)
    end

    it 'summarises the cache as a count' do
      expect(lookup.inspect).to include('scanned=1')
    end

    it 'returns a Result rather than the claim data' do
      expect(gather_with(:SC_REDESIGN)).to be_a(described_class::Result)
    end

    %i[inspect to_s].each do |method|
      it "keeps it out of Result##{method}" do
        expect(gather_with(:SC_REDESIGN).public_send(method)).not_to include(sentinel)
      end
    end

    it 'keeps it out of the console narration' do
      gather_with(:SC_REDESIGN)

      expect(console).not_to include(sentinel)
    end
  end

  # --------------------------------------------------------------------------
  # Result
  # --------------------------------------------------------------------------
  describe described_class::Result do
    [
      [{ matched: 5, examined: 12, dry_run: true }, 'dry_run (nothing uploaded)'],
      [{ matched: 5, examined: 12, dry_run: false, uploaded: 6 }, 'uploaded=6'],
      [{ matched: 5, examined: 12, dry_run: false, uploaded: 4, failed: 2 }, 'failed=2'],
      [{ matched: 5, examined: 12, dry_run: false, s3_prefix: 'reports/x' }, 's3=reports/x']
    ].each do |attributes, fragment|
      it "renders #{fragment.inspect}" do
        expect(described_class.new(**attributes).inspect).to include(fragment)
      end
    end

    it 'omits the failure count when nothing failed' do
      expect(described_class.new(matched: 1, examined: 1, dry_run: false, uploaded: 1, failed: 0).inspect)
        .not_to include('failed=')
    end
  end

  # --------------------------------------------------------------------------
  # Veteran identifiers
  # --------------------------------------------------------------------------
  describe 'veteran identifiers' do
    # [description, auth headers, expected value, expected source]
    [
      ['prefers the file number', { 'X-VA-File-Number' => '796123456' }, '796123456', 'file_number'],
      ['falls back to the SSN', { 'X-VA-SSN' => '123456789' }, '123456789', 'ssn'],
      ['reports none when neither is present', {}, '-', 'none']
    ].each do |description, headers, value, source|
      it description do
        submission = build(:supplemental_claim, auth_headers: headers, form_data: nil)

        expect(lookup.send(:veteran_identifier, submission)).to eq([value, source])
      end
    end

    it 'reports "not found" when there is no AppealsApi record' do
      expect(lookup.send(:veteran_identifier, nil)).to eq(['-', 'not found'])
    end

    it 'resolves against real records in one batched query' do
      create_claim(auth_headers: { 'X-VA-File-Number' => '796123456' })

      expect(gather_with(:SC_REDESIGN).matched).to eq(1)
    end
  end

  # --------------------------------------------------------------------------
  # Summary table
  # --------------------------------------------------------------------------
  describe 'summary table' do
    let(:found) do
      {
        found: true, file_number_value: '796123456', file_number_source: 'file_number',
        saved_claim_id: 1, guid: 'guid-1', created_at: '2026-07-15T12:00:00Z',
        sc_redesign: true, uploaded_forms: ['21-4142'], should_have_form4142: true, form: {}
      }
    end
    let(:missing) { { found: false, file_number_value: '-', file_number_source: 'not found' } }

    it 'renders a header, a divider and one row per claim' do
      text = lookup.send(:summary_text, { 'guid-1' => found, 'guid-2' => missing }, ['Filter: x'])

      expect(text.lines.size).to eq(6 + 2)
    end

    [
      ['the identifier', '796123456'],
      ['its source', 'file_number'],
      ['the found marker', 'found'],
      ['the uploaded forms', '21-4142']
    ].each do |description, fragment|
      it "includes #{description} in a found row" do
        expect(lookup.send(:summary_row, 'guid-1', found)).to include(fragment)
      end
    end

    it 'marks a claim with no SavedClaim as not found' do
      expect(lookup.send(:summary_row, 'guid-2', missing)).to include('not found')
    end

    it 'is never written to the console' do
      create_claim(auth_headers: { 'X-VA-File-Number' => '796123456' })

      gather_with(:SC_REDESIGN)

      expect(console).not_to include('796123456')
    end
  end

  # --------------------------------------------------------------------------
  # Concurrency helpers
  # --------------------------------------------------------------------------
  describe '#parallel_map' do
    it 'preserves input order' do
      expect(lookup.send(:parallel_map, (1..40).to_a) { |item| item * 2 }).to eq((1..40).map { |i| i * 2 })
    end

    it 'isolates a failing item instead of aborting the batch' do
      results = lookup.send(:parallel_map, (1..10).to_a) do |item|
        raise 'boom' if item == 5

        item
      end

      expect(results[4]).to be_a(described_class::Failure)
      expect(results.reject { |r| r.is_a?(described_class::Failure) }).to eq([1, 2, 3, 4, 6, 7, 8, 9, 10])
    end

    it 'carries the offending item and error on the Failure' do
      failure = lookup.send(:parallel_map, [:boom]) { raise ArgumentError, 'nope' }.first

      expect([failure.item, failure.error.message]).to eq([:boom, 'nope'])
    end

    [[], [7]].each do |items|
      it "handles #{items.size} item(s) without a pool" do
        expect(lookup.send(:parallel_map, items, &:itself)).to eq(items)
      end
    end
  end

  describe '#duration' do
    { 0 => '0s', 45 => '45s', 59 => '59s', 60 => '1m00s', 90 => '1m30s',
      3599 => '59m59s', 3600 => '1h00m', 3661 => '1h01m', 86_399 => '23h59m' }.each do |seconds, expected|
      it "formats #{seconds}s as #{expected}" do
        expect(lookup.send(:duration, seconds)).to eq(expected)
      end
    end
  end

  # --------------------------------------------------------------------------
  # S3
  # --------------------------------------------------------------------------
  describe 'S3 upload' do
    subject(:uploader) { described_class.new(since_date:, dry_run: false) }

    let(:bucket) { instance_double(Aws::S3::Bucket) }
    let(:object) { instance_double(Aws::S3::Object) }

    before do
      allow(Settings).to receive(:reports).and_return(
        double(aws: double(region: 'us-east-1', access_key_id: 'k', secret_access_key: 's', bucket: 'test-bucket'))
      )
      resource = instance_double(Aws::S3::Resource)
      allow(Aws::S3::Resource).to receive(:new).and_return(resource)
      allow(resource).to receive(:bucket).and_return(bucket)
      allow(bucket).to receive(:object).and_return(object)
      allow(object).to receive(:put)
      create_claim
    end

    it 'uploads the summary plus one file per claim' do
      uploader.gather(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign')

      expect(object).to have_received(:put).twice
    end

    it 'reports the prefix and counts on the Result' do
      result = uploader.gather(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign')

      expect([result.uploaded, result.failed, result.dry_run]).to eq([1, 0, false])
      expect(result.s3_prefix).to start_with('reports/supplemental-claims/file-number-lookups/')
    end

    it 'prints the prefix rather than each file name' do
      uploader.gather(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign')

      expect(console).to include('s3://test-bucket/reports/supplemental-claims/file-number-lookups/')
    end

    it 'swallows an upload failure and still returns a Result' do
      allow(object).to receive(:put).and_raise(StandardError, 'bucket gone')

      result = uploader.gather(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign')

      expect(result.uploaded).to eq(0)
      expect(console).to include('Failed to upload to S3: bucket gone')
    end

    it 'uploads nothing under dry_run' do
      lookup.gather(filter: filter_for(:SC_REDESIGN), filter_label: 'redesign')

      expect(object).not_to have_received(:put)
    end
  end

  describe '#report_upload' do
    let(:ok) { ->(n) { "id-#{n}" } }
    let(:bad) { ->(n) { described_class::Failure.new(["id-#{n}", {}], RuntimeError.new("boom #{n}")) } }

    # [failure count, expected fragments, forbidden fragments]
    [
      [0, ['summary + 5 claim file(s)'], ['failed to upload']],
      [3, ['summary + 5 claim file(s)', '3 file(s) failed to upload', 'id-6'], ['more']],
      [12, ['12 file(s) failed to upload', '... and 2 more'], []]
    ].each do |failure_count, expected, forbidden|
      it "narrates #{failure_count} failure(s)" do
        successes = failure_count == 12 ? [] : (1..5).map(&ok)
        results = successes + (6..(5 + failure_count)).map(&bad)

        lookup.send(:report_upload, results, 'bkt', 'pre/fix', 0.0)

        expected.each { |fragment| expect(console).to include(fragment) }
        forbidden.each { |fragment| expect(console).not_to include(fragment) }
      end
    end

    it 'names at most SHOWN_FAILURES individual failures' do
      lookup.send(:report_upload, (1..12).map(&bad), 'bkt', 'pre/fix', 0.0)

      expect(console.scan(/^ {2}id-\d+:/).size).to eq(described_class::SHOWN_FAILURES)
    end
  end

  # --------------------------------------------------------------------------
  # Guard rails
  # --------------------------------------------------------------------------
  describe 'filter validation' do
    [
      [{ filter: nil, filter_label: 'x' }, 'filter is required'],
      [{ filter: -> { true }, filter_label: nil }, 'filter_label is required'],
      [{ filter: -> { true }, filter_label: '' }, 'filter_label is required']
    ].each do |arguments, message|
      %i[run gather].each do |method|
        it "##{method} rejects #{arguments.inspect}" do
          expect { lookup.public_send(method, **arguments) }.to raise_error(ArgumentError, /#{message}/)
        end
      end
    end
  end

  describe '.run' do
    it 'builds and runs in one call' do
      create_claim

      result = described_class.run(since_date:, filter: described_class::Filters::SC_REDESIGN,
                                   filter_label: 'redesign')

      expect(result.matched).to eq(1)
    end
  end

  describe 'empty results' do
    it 'returns a zeroed Result without building a report' do
      create_claim(redesign: false)

      result = gather_with(:SC_REDESIGN)

      expect([result.matched, result.dry_run]).to eq([0, true])
      expect(console).not_to include('Built summary table')
    end
  end
end
