# frozen_string_literal: true

require 'ves_api/client'
require 'ivc_champva/monitor'
require 'ivc_champva/config_file_loader'
require 'benefits_claims/providers/ivc_champva/repeat_ineligibility_letter_activity'

module IvcChampva
  # Fetches and processes eligibility data from VES for a single CHAMPVA application.
  #
  # Step 1: Call VES to retrieve all persons (SPONSOR, BENEFICIARY) and their ICNs
  #         for the given transaction_uuid, and persist applicant records.
  #         When applicant records with ICNs already exist, VES is not re-queried.
  #
  # Step 2: For each applicant missing a name, look the ICN up in MPI and persist
  #         the first/last name on the applicant record. Applicants that already
  #         have a name are skipped.
  #
  # Step 3: For each applicant, call the VES EE Summary service (CSTChampvaEligibility)
  #         to sync mail-correspondence letter history, since VES may mail new
  #         correspondence even after an applicant is confirmed eligible. CHAMPVA
  #         status/reason and the sponsor's ICN and status/reason are only persisted
  #         for applicants not yet marked eligible, since their status and reason can
  #         change over time; the controller's rate limit guards against excessive
  #         requests.
  #
  # The class methods are a separate, read-only concern: they build the CHAMPVA benefits
  # card from a single EE Summary lookup and persist nothing. They live here for the shared
  # eligibility parsing rather than in their own service.
  # rubocop:disable Metrics/ClassLength
  class ChampvaEligibilityService
    STATS_KEY = 'ivc_champva.eligibility'
    # Terminal outcome of a single #call, tagged status:success/pending/error -- 'pending'
    # and 'error' are VES call failures that #call already rescues and turns into a normal
    # response hash, so without this metric they're invisible outside the logs.
    CALL_OUTCOME_METRIC = "#{STATS_KEY}.call".freeze
    # Tagged eligible:true/false whenever an applicant's VES eligibility is persisted.
    APPLICANT_RESOLVED_METRIC = "#{STATS_KEY}.applicant_resolved".freeze
    # Every individual VES API call failure, tagged operation:icn_lookup/ee_summary and
    # status:pending/error -- fires from #log_ves_error, the single point every VES rescue
    # in this service routes through, so a per-applicant EE Summary failure (caught and
    # skipped inside #sync_applicant_eligibility, never bubbling up to #call's rescue) is
    # just as visible as the top-level ICN lookup failure that becomes the whole call's
    # result. CALL_OUTCOME_METRIC only reflects the latter -- this metric is what to alert
    # on for "a VES call failed", including failures the service otherwise absorbs and
    # continues past.
    VES_API_ERROR_METRIC = "#{STATS_KEY}.ves_api_error".freeze
    # Incremented once per applicant flagged as needing additional documents.
    DOCUMENTS_REQUESTED_METRIC = "#{STATS_KEY}.documents_requested".freeze
    # Incremented on a successful #call when the application is older than
    # STUCK_APPLICATION_THRESHOLD but still has an unresolved applicant. Piggybacks on
    # this service's normal request-driven flow (the FE already calls this on-demand,
    # e.g. whenever a user views their CST/MyVA card) rather than a separate scheduled
    # sweep job, so a stuck application is only reported when someone actually checks
    # it -- no added background/DB overhead for applications nobody is looking at.
    STUCK_APPLICATION_METRIC = "#{STATS_KEY}.stuck_application".freeze
    STUCK_APPLICATION_THRESHOLD = 30.days

    DOCUMENTS_REQUESTED_STATUSES_PATH =
      Rails.root.join('config', 'benefits_claims', 'ves_documents_requested_statuses.json').freeze

    DOCUMENTS_REQUESTED_CONFIG = begin
      JSON.parse(File.read(DOCUMENTS_REQUESTED_STATUSES_PATH))
    rescue => e
      Rails.logger.error(
        'ChampvaEligibilityService: Failed to load VES documents requested statuses',
        { message: e.message }
      )
      StatsD.increment(IvcChampva::ConfigFileLoader::SILENT_FAILURE_METRIC,
                       tags: ["context:#{IvcChampva::ConfigFileLoader.sanitize_tag_value(name)}"])
      {}
    end

    DOCUMENTS_REQUESTED_STATUSES =
      DOCUMENTS_REQUESTED_CONFIG.fetch('statuses', []).to_set { |s| s.to_s.downcase.strip }.freeze
    DOCUMENTS_REQUESTED_REASONS =
      DOCUMENTS_REQUESTED_CONFIG.fetch('reasons', []).to_set { |r| r.to_s.downcase.strip }.freeze

    # Card enrollment verdicts. ELIGIBLE is the only one a card is issued for; the rest
    # tell the frontend why one was not.
    ENROLLMENT_ELIGIBLE = 'eligible'
    ENROLLMENT_INELIGIBLE = 'ineligible'
    ENROLLMENT_EXPIRED = 'expired'
    ENROLLMENT_NOT_YET_EFFECTIVE = 'not_yet_effective'

    # VES writes addressTypeCode as a single letter on submit and as a full word on read,
    # and only one read sample exists, so both spellings are matched. Permanent is the
    # mailing address; residential is the fallback the physical card can still reach.
    MAILING_ADDRESS_TYPE_CODES = %w[p permanent].freeze
    RESIDENTIAL_ADDRESS_TYPE_CODES = %w[r residential].freeze

    class << self
      # Builds CHAMPVA card attributes for a logged-in user from EE Summary.
      #
      # The attributes carry a `beneficiary_infos` array rather than a single card so one
      # frontend call serves both the digital and physical card flows. The array holds one
      # entry today; the sponsor flow will return one per beneficiary.
      #
      # @param user [User]
      # @param ves_client [IvcChampva::VesApi::Client]
      # @param as_of [Date]
      # @return [Hash] { status: :ok, attributes: }, { status: :ineligible, enrollment_status:, attributes: },
      #   or { status: :not_enrolled|:upstream_timeout|:upstream_error }
      def benefits_card_for(user, ves_client: IvcChampva::VesApi::Client.new, as_of: Date.current)
        data = ves_client.get_ee_summary(icn: user.icn, dataset: 'ChampvaDigitalCardData')
        role = determine_role(data)
        # The sponsor flow needs a roster endpoint VES has not delivered yet, so a
        # non-beneficiary is reported as not enrolled for now. When that endpoint lands,
        # this branch calls it and maps its beneficiaries through beneficiary_info instead.
        return { status: :not_enrolled } unless role == :beneficiary

        info = beneficiary_info(data, identity: session_identity(user), as_of:)
        attributes = { role: role.to_s, beneficiary_infos: [info] }
        return { status: :ok, attributes: } if info[:enrollment_status] == ENROLLMENT_ELIGIBLE

        # Reported separately from :ok so the controller decides the HTTP shape rather than
        # this method. The attributes still come back, so surfacing them later is a controller
        # change only. One entry means one verdict; the sponsor flow will filter its array
        # instead, since a mixed one has no single verdict to report this way.
        { status: :ineligible, enrollment_status: info[:enrollment_status], attributes: }
      rescue IvcChampva::VesApi::VesApplicationPendingError
        { status: :not_enrolled }
      rescue IvcChampva::VesApi::VesApiTimeoutError => e
        ves_call_failed(:upstream_timeout, e)
      rescue IvcChampva::VesApi::VesApiError => e
        ves_call_failed(:upstream_error, e)
      end

      # Whether the person the EE Summary was queried for is a CHAMPVA beneficiary or the
      # veteran they claim through. VES returns champvaEligibilities only for a
      # beneficiary; a veteran querying their own ICN gets an empty `{"data":{}}`.
      #
      # A person with no CHAMPVA record is indistinguishable from a veteran here, since
      # both come back empty, so :veteran means only "not a beneficiary". The sponsor flow
      # will need a positive signal from the roster endpoint rather than this inference.
      #
      # @param data [Hash, nil]
      # @return [Symbol] :beneficiary or :veteran
      def determine_role(data)
        champva_relationship(data).present? ? :beneficiary : :veteran
      end

      # Digs the first CHAMPVA eligibility entry out of the EE Summary response.
      #
      # @param data [Hash, nil]
      # @return [Hash, nil]
      def extract_champva_eligibility(data)
        champva_relationship(data)&.fetch(:eligibility)
      end

      private

      # The card's enrollment verdict: eligible requires both an eligible VES status and a
      # date window covering today. A window that does not cover today reports why (expired
      # or not yet effective) even when VES also calls the person ineligible, since those
      # dates are the more specific explanation; the raw VES status travels alongside as
      # eligibility_status.
      #
      # @param eligibility [Hash, nil] a single CHAMPVA eligibility entry
      # @param as_of [Date]
      # @return [String] one of the ENROLLMENT_* values
      def enrollment_status(eligibility, as_of:)
        window = window_status(eligibility, as_of:)
        return window unless window == ENROLLMENT_ELIGIBLE
        return ENROLLMENT_INELIGIBLE unless eligible_ves_status?(eligibility['status'])

        ENROLLMENT_ELIGIBLE
      end

      # The mailing address for the physical card, or nil when the dataset carries none.
      # VES returns one address per type rather than a history, so selection is by type:
      # undeliverable and ended entries are dropped, permanent is preferred over
      # residential, and any remaining tie goes to the most recently changed entry.
      #
      # @param data [Hash, nil]
      # @param as_of [Date]
      # @return [Hash, nil]
      def mailing_address(data, as_of:)
        usable = usable_addresses(data, as_of:)
        return nil if usable.empty?

        address = preferred_addresses(usable)
                  .max_by { |entry| parse_address_change_time(entry['addressChangeDateTime']) || Time.zone.at(0) }
        formatted_address(address)
      end

      # Whether VES has flagged this record as sensitive. Absent stays nil rather than
      # false: defaulting an unknown flag to "not sensitive" is the unsafe direction, and
      # the sponsor flow filters beneficiaries on this value.
      #
      # @param data [Hash, nil]
      # @return [Boolean, nil]
      def sensitive_record(data)
        return nil unless data.is_a?(Hash)

        flag = data.dig('sensitivityInfo', 'sensitivityFlag')
        return nil if flag.nil?

        ActiveModel::Type::Boolean.new.cast(flag)
      end

      # Records the VES failure and builds the result for it. Tracked as a VES-level failure
      # rather than a card-level one because the same EE Summary call backs the eligibility sync
      # and, later, the sponsor roster lookup, so its health is worth watching per operation
      # instead of per endpoint. The controller tracks the card-level outcome separately, and
      # error_class rides along so it can tag that metric too.
      def ves_call_failed(code, error)
        monitor.track_ves_call_failure('ee_summary', code, error)
        { status: code, error_class: error.class.name }
      end

      # Not memoized: these are class methods, so an ivar here would live on the singleton and be
      # shared across threads. The monitor is stateless and cheap to build.
      def monitor
        IvcChampva::Monitor.new
      end

      # The first CHAMPVA eligibility entry paired with the relationship it came from,
      # since the card renders the relationship descriptor next to the eligibility.
      #
      # @param data [Hash, nil]
      # @return [Hash, nil] { relationship:, eligibility: }
      def champva_relationship(data)
        return nil unless data.is_a?(Hash)

        relationships = data.dig('vfmpProgramsInfo', 'relationships')
        return nil unless relationships.is_a?(Array)

        relationships.each do |relationship|
          eligibility = eligibility_entries(relationship).first
          return { relationship:, eligibility: } if eligibility.present?
        end

        nil
      end

      # One beneficiary_infos entry. The enrollment verdict is settled before any
      # enrichment runs, so name, date of birth, and address stay nil for anyone the
      # frontend will not offer a card to.
      #
      # @param data [Hash] the EE Summary response
      # @param identity [Hash] { icn:, full_name:, date_of_birth: }
      # @param as_of [Date]
      # @return [Hash]
      def beneficiary_info(data, identity:, as_of:)
        pair = champva_relationship(data)
        eligibility = pair[:eligibility]
        status = enrollment_status(eligibility, as_of:)
        period = display_period(eligibility, as_of:)

        info = {
          icn: identity[:icn],
          full_name: nil,
          date_of_birth: nil,
          mailing_address: nil,
          enrollment_status: status,
          eligibility_status: eligibility['status'],
          eligibility_reason: eligibility['reason'],
          sensitive_record: sensitive_record(data),
          relationship_type: pair[:relationship]['relationshipType'],
          effective_date: format_card_date(period['startDate']),
          expiration_date: format_card_date(period['endDate'])
        }
        return info unless status == ENROLLMENT_ELIGIBLE

        info.merge(enrich(data, identity:, as_of:))
      end

      # The fields only an eligible beneficiary's card needs. This costs nothing extra in
      # the beneficiary flow, where the identity is already resolved for the session, but
      # it is where the sponsor flow's per-beneficiary MPI call will land — hence keeping
      # it behind the eligibility gate now rather than restructuring later.
      #
      # @param identity [Hash] { icn:, full_name:, date_of_birth: }
      # @return [Hash]
      def enrich(data, identity:, as_of:)
        {
          full_name: identity[:full_name],
          date_of_birth: identity[:date_of_birth],
          mailing_address: mailing_address(data, as_of:)
        }
      end

      # The beneficiary flow's identity source. EE Summary carries no name, date of birth,
      # or subject ICN, so these come from the session — which resolves them from the MPI
      # profile UserLoader already fetched and cached, costing no upstream call. The
      # sponsor flow will build the same hash from an explicit MPI lookup per beneficiary.
      #
      # @param user [User]
      # @return [Hash]
      def session_identity(user)
        {
          icn: user.icn,
          full_name: [user.first_name, user.last_name].compact.join(' ').presence,
          date_of_birth: user.birth_date
        }
      end

      # The date-window half of the enrollment verdict. An entry with no parseable window
      # is ineligible rather than expired, since we cannot say which.
      #
      # @return [String] one of the ENROLLMENT_* values
      def window_status(eligibility, as_of:)
        return ENROLLMENT_ELIGIBLE if covering_period(eligibility, as_of:).present?

        start_dates = eligibility_date_periods(eligibility)
                      .select { |period| period.is_a?(Hash) }
                      .filter_map { |period| parse_card_date(period['startDate']) }
        return ENROLLMENT_INELIGIBLE if start_dates.empty?
        return ENROLLMENT_NOT_YET_EFFECTIVE if start_dates.min > as_of

        ENROLLMENT_EXPIRED
      end

      # Exact match, not a substring one: "Ineligible" contains "eligible".
      def eligible_ves_status?(status)
        status.to_s.downcase.strip == ENROLLMENT_ELIGIBLE
      end

      # The window whose dates the card shows: the one covering today when there is one,
      # otherwise the most recent, so an expired or future beneficiary still sees the dates
      # behind their verdict. Always a Hash so callers can read it unconditionally.
      #
      # @return [Hash]
      def display_period(eligibility, as_of:)
        covering_period(eligibility, as_of:) || latest_period(eligibility) || {}
      end

      def latest_period(eligibility)
        eligibility_date_periods(eligibility)
          .select { |period| period.is_a?(Hash) }
          .max_by { |period| parse_card_date(period['startDate']) || Date.new(0) }
      end

      def eligibility_entries(relationship)
        return [] unless relationship.is_a?(Hash)

        Array(relationship['champvaEligibilities'])
      end

      def covering_period(eligibility, as_of:)
        periods = eligibility_date_periods(eligibility)
        covering = periods.select { |period| period_covers?(period, as_of) }
        covering.max_by { |period| parse_card_date(period['startDate']) || Date.new(0) }
      end

      def eligibility_date_periods(eligibility)
        return [] unless eligibility.is_a?(Hash)

        dates = eligibility['eligibilityDates']
        case dates
        when Array then dates
        when Hash then [dates]
        else []
        end
      end

      def period_covers?(period, as_of)
        return false unless period.is_a?(Hash)

        start_date = parse_card_date(period['startDate'])
        return false if start_date.nil? || start_date > as_of

        end_date = parse_card_date(period['endDate'])
        end_date.nil? || end_date >= as_of
      end

      def parse_card_date(value)
        return value if value.is_a?(Date)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def format_card_date(value)
        parse_card_date(value)&.strftime('%Y/%m/%d')
      end

      def usable_addresses(data, as_of:)
        return [] unless data.is_a?(Hash)

        Array(data.dig('demographics', 'contactInfo', 'addresses'))
          .select { |address| usable_address?(address, as_of:) }
      end

      # Drops addresses the physical card could not reach: VES marks known-undeliverable
      # ones with a badAddressReason, and an entry whose window has closed is stale.
      # endDate has no documented format and is absent from real data, so an unparseable
      # value keeps the address rather than discarding a usable one.
      def usable_address?(address, as_of:)
        return false unless address.is_a?(Hash)
        return false if address['badAddressReason'].present?

        end_date = parse_card_date(address['endDate'])
        end_date.nil? || end_date >= as_of
      end

      def preferred_addresses(addresses)
        addresses_of_type(addresses, MAILING_ADDRESS_TYPE_CODES).presence ||
          addresses_of_type(addresses, RESIDENTIAL_ADDRESS_TYPE_CODES).presence ||
          addresses
      end

      def addresses_of_type(addresses, codes)
        addresses.select { |address| codes.include?(address['addressTypeCode'].to_s.downcase.strip) }
      end

      def formatted_address(address)
        {
          line1: address['line1'],
          line2: address['line2'],
          line3: address['line3'],
          city: address['city'],
          state: address['state'],
          province_code: address['provinceCode'],
          zip_code: address['zipCode'],
          zip_plus4: address['zipPlus4'],
          postal_code: address['postalCode'],
          country: address['country']
        }
      end

      def parse_address_change_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end

    # @param transaction_uuid [String] the CHAMPVA application transaction UUID
    def initialize(transaction_uuid)
      @transaction_uuid = transaction_uuid
      @ves_client = IvcChampva::VesApi::Client.new
      @created_count = 0
      @existing_count = 0
      @letters_created_count = 0
      @cached = false
    end

    # Runs the three eligibility-sync steps for this application's transaction UUID:
    # Step 1 (ICN lookup), Step 2 (MPI name backfill), Step 3 (EE Summary eligibility).
    #
    # @return [Hash] result with :status, :persons, :created_count, :existing_count,
    #   :names_updated_count, :eligibility_updated_count, :letters_created_count, and
    #   :cached keys
    #   :status — 'success' | 'pending' | 'error'
    #   :persons — Array of { icn:, person_uuid:, person_type: } hashes
    #   :cached — true when applicant records already existed and VES was not re-queried
    def call
      applicants = sync_applicants
      names_updated_count = backfill_applicant_names(applicants)
      eligibility_updated_count = resolve_eligibility(applicants)
      success_result(applicants, names_updated_count, eligibility_updated_count)
    rescue IvcChampva::VesApi::VesApplicationPendingError => e
      failure_result('pending', e, level: :info)
    rescue IvcChampva::VesApi::VesApiError => e
      failure_result('error', e)
    end

    private

    # Builds the success response hash from the synced applicants and per-step counts.
    #
    # @return [Hash]
    def success_result(applicants, names_updated_count, eligibility_updated_count)
      StatsD.increment(CALL_OUTCOME_METRIC, tags: ['status:success'])
      track_if_stuck(applicants)
      {
        status: 'success',
        persons: applicants.map { |applicant| person_hash(applicant) },
        created_count: @created_count,
        existing_count: @existing_count,
        names_updated_count:,
        eligibility_updated_count:,
        letters_created_count: @letters_created_count,
        cached: @cached
      }
    end

    # Logs and builds the failure response hash for a terminal VES error.
    #
    # @param status [String] 'pending' or 'error'
    # @param error [StandardError]
    # @return [Hash]
    def failure_result(status, error, level: :error)
      log_ves_error("application #{status}", error, operation: 'icn_lookup', level:)
      StatsD.increment(CALL_OUTCOME_METRIC, tags: ["status:#{status}"])
      { status:, persons: [], created_count: 0, existing_count: 0, error: error.message }
    end

    # Logs a VES error against this transaction at the given severity, and increments
    # VES_API_ERROR_METRIC -- the single point every VES rescue in this service routes
    # through, so every VES call failure is tracked the same way regardless of whether
    # it terminates the whole #call (icn_lookup) or is caught and skipped per-applicant
    # (ee_summary, see #sync_applicant_eligibility).
    #
    # @param context [String] short description of what failed, for the log message
    # @param error [StandardError]
    # @param operation [String] which VES call failed -- 'icn_lookup' or 'ee_summary'
    # @param level [Symbol] Rails logger severity (:info, :error, ...) -- also determines
    #   the metric's status:pending/error tag (:info => pending, anything else => error)
    def log_ves_error(context, error, operation:, level: :error)
      Rails.logger.public_send(
        level, "ChampvaEligibilityService: #{context} for #{@transaction_uuid}: #{error.message}"
      )
      status = level == :info ? 'pending' : 'error'
      StatsD.increment(VES_API_ERROR_METRIC, tags: ["operation:#{operation}", "status:#{status}"])
    end

    # Returns the applicant records for this transaction (Step 1), querying VES only
    # when no records with ICNs exist yet. Updates @cached and @existing_count as a
    # side effect for the response counts.
    #
    # @return [Array<IvcChampvaApplicant>]
    def sync_applicants
      existing_records = existing_applicant_records.to_a
      if existing_records.any?
        @cached = true
        @existing_count = existing_records.size
        return existing_records
      end

      persist_person_records(fetch_persons_from_ves)
    end

    # Applicant records already persisted for this transaction that carry an ICN.
    # Their presence means VES has already been queried for this application, so
    # we can skip the network call entirely.
    #
    # @return [ActiveRecord::Relation]
    def existing_applicant_records
      IvcChampvaApplicant
        .where(transaction_uuid: @transaction_uuid)
        .where.not(applicant_icn_ciphertext: nil)
    end

    # Normalizes an applicant record into the person response shape.
    #
    # @param applicant [IvcChampvaApplicant]
    # @return [Hash]
    def person_hash(applicant)
      { icn: applicant.applicant_icn, person_uuid: nil, person_type: applicant.person_type }
    end

    # Calls VES to get the list of persons for this transaction and normalizes the response.
    #
    # VES client returns an Array of person hashes:
    #   [{ "icn" => "...", "personUUID" => "...", "personType" => "SPONSOR|BENEFICIARY" }]
    #
    # @return [Array<Hash>]
    def fetch_persons_from_ves
      raw = @ves_client.get_icns_for_transaction(@transaction_uuid)
      raw.map do |person|
        {
          icn: person['icn'],
          person_uuid: person['personUUID'],
          person_type: person['personType']
        }
      end
    end

    # Finds or creates an applicant record per person, never duplicating an existing
    # transaction + ICN. Increments @created_count / @existing_count.
    #
    # @param persons [Array<Hash>]
    # @return [Array<IvcChampvaApplicant>]
    def persist_person_records(persons)
      existing_by_icn = IvcChampvaApplicant.where(transaction_uuid: @transaction_uuid).to_a.index_by(&:applicant_icn)

      persons.map do |person|
        sync_applicant_record(person, existing_by_icn)
      end.uniq(&:id)
    end

    # Creates or reuses a single applicant record using the database uniqueness
    # key (transaction_uuid + applicant_icn). Logs if a conflicting person_type
    # is seen for the same ICN.
    #
    # @param person [Hash]
    # @return [IvcChampvaApplicant]
    def sync_applicant_record(person, existing_by_icn)
      existing = existing_by_icn[person[:icn]]
      return create_applicant_record(person, existing_by_icn) unless existing

      @existing_count += 1
      log_conflicting_person_type(existing, person)
      existing
    end

    def create_applicant_record(person, existing_by_icn)
      applicant_icn = person[:icn]

      applicant = IvcChampvaApplicant.create!(
        transaction_uuid: @transaction_uuid,
        applicant_icn:,
        person_type: person[:person_type]
      )
      existing_by_icn[applicant_icn] = applicant
      @created_count += 1
      applicant
    rescue ActiveRecord::RecordNotUnique
      # Another concurrent run created the applicant row first. applicant_icn is a
      # Lockbox-encrypted attribute (see the class-level has_encrypted declaration), not a
      # real column -- only applicant_icn_ciphertext is -- so find_by/where can't query it
      # directly (PG::UndefinedColumn). Fetch by the indexed transaction_uuid instead and
      # match the decrypted value in Ruby, same as persist_person_records' own
      # existing_by_icn lookup does.
      existing = IvcChampvaApplicant.where(transaction_uuid: @transaction_uuid)
                                    .find { |a| a.applicant_icn == applicant_icn }
      # A nil here means the unique-constraint violation wasn't actually the concurrent-
      # insert race this rescue assumes (e.g. the other process's row was deleted before
      # we could re-fetch it, or a decrypt mismatch) -- re-raise so that fails loud and
      # local, instead of writing nil into existing_by_icn, where persist_person_records'
      # own .uniq(&:id) would raise a NoMethodError on nil.id far from the real cause, and
      # @existing_count would be incremented for a record that doesn't actually exist.
      raise if existing.nil?

      existing_by_icn[applicant_icn] = existing
      @existing_count += 1
      existing
    end

    # @param applicant [IvcChampvaApplicant]
    # @param person [Hash]
    # @return [void]
    def log_conflicting_person_type(applicant, person)
      return if applicant.person_type == person[:person_type]

      Rails.logger.warn(
        'ChampvaEligibilityService: conflicting person_type for applicant ICN',
        transaction_uuid: @transaction_uuid,
        existing_person_type: applicant.person_type,
        incoming_person_type: person[:person_type]
      )
    end

    # For each applicant missing a name, looks the ICN up in MPI and persists the
    # first/last name. Applicants that already have both names are skipped so MPI
    # is not re-queried.
    #
    # @param applicants [Array<IvcChampvaApplicant>]
    # @return [Integer] number of applicant records updated with a name
    def backfill_applicant_names(applicants)
      applicants.count do |applicant|
        next false if applicant.applicant_first_name.present? && applicant.applicant_last_name.present?

        name = mpi_service.lookup_name_by_icn(applicant.applicant_icn)
        next false if name.blank?

        applicant.update!(
          applicant_first_name: name[:first_name],
          applicant_last_name: name[:last_name]
        )
        true
      end
    end

    # For every applicant, calls the VES EE Summary service to sync mail-correspondence
    # letter history (VES may mail new correspondence even after an applicant is
    # confirmed eligible, so this always runs). CHAMPVA status/reason and the sponsor's
    # ICN and status/reason are only persisted for applicants not yet confirmed
    # eligible; applicants with any other status (including ineligible) are re-queried
    # on every call because their status and reason can change over time. A pending or
    # errored lookup for one applicant leaves that record unchanged without aborting
    # the others.
    #
    # @param applicants [Array<IvcChampvaApplicant>]
    # @return [Integer] number of applicant records updated with eligibility data
    def resolve_eligibility(applicants)
      applicants.count { |applicant| sync_applicant_eligibility(applicant) }
    end

    # Fetches EE Summary data for a single applicant, syncs its letter history, and
    # persists eligibility/sponsor data unless the applicant is already confirmed
    # eligible. A pending or errored lookup is logged and skipped without raising.
    #
    # @param applicant [IvcChampvaApplicant]
    # @return [Boolean] true when eligibility data was persisted
    def sync_applicant_eligibility(applicant)
      data = @ves_client.get_ee_summary(icn: applicant.applicant_icn)
      persist_letters(applicant, data)
      return false if applicant.eligible?

      persist_eligibility(applicant, data)
    rescue IvcChampva::VesApi::VesApplicationPendingError => e
      log_ves_error('EE summary pending', e, operation: 'ee_summary', level: :info)
      false
    rescue IvcChampva::VesApi::VesApiError => e
      log_ves_error('EE summary error', e, operation: 'ee_summary')
      false
    end

    # Persists CHAMPVA eligibility data for a single applicant, then records the
    # transaction's sponsor (once) from the same EE Summary payload. Skipped when
    # the determination looks like it's carried over from a prior application (see
    # stale_prior_application_status?) and no letter has yet confirmed it applies
    # to this one.
    #
    # @param applicant [IvcChampvaApplicant]
    # @param data [Hash] the EE Summary response for this applicant
    # @return [Boolean] true when eligibility data was persisted
    def persist_eligibility(applicant, data)
      eligibility = extract_champva_eligibility(data)
      return false if eligibility.blank?
      return false if stale_prior_application_status?(eligibility) && !application_letter_present?(applicant)

      applicant.update!(eligibility_attributes(eligibility))
      persist_sponsor(eligibility)
      StatsD.increment(APPLICANT_RESOLVED_METRIC, tags: ["eligible:#{applicant.eligible?}"])
      true
    end

    # True when VES's statusUpdatedDate for this determination clearly predates the
    # application's submission — i.e. this looks like a decision from a PRIOR CHAMPVA
    # application under the same ICN that VES hasn't reprocessed yet (e.g. a Veteran
    # denied months ago who has since reapplied), not a fresh determination for the
    # current application. Absent/unparseable dates are treated as not stale, so
    # applicants are still resolved immediately when VES doesn't supply this field.
    #
    # @param eligibility [Hash] a single CHAMPVA eligibility entry from the EE Summary
    # @return [Boolean]
    def stale_prior_application_status?(eligibility)
      return false if application_submitted_at.blank?

      status_updated_date = parsed_mail_status_date(eligibility['statusUpdatedDate'])
      return false if status_updated_date.blank?

      status_updated_date < application_submitted_at
    end

    # True once VES has generated at least one *officially sent, allowlisted* mail-correspondence
    # entry for this applicant dated after the application's submission — i.e. proof a letter has
    # actually gone out for the current application, not merely a queued/pending entry that
    # hasn't been mailed yet, and not correspondence outside CHAMPVA's scope. Used to let a
    # stale-looking status (per stale_prior_application_status?) through once a letter confirms
    # it, even when the letter repeats the same status/reason as before ("the status may not
    # change if the decision did not change"). Delegates to
    # RepeatIneligibilityLetterActivity.sent_letters_for for the allowlist/sent-status filtering,
    # so this check can't drift from what that method (and ClaimBuilder.letters_for) considers a
    # real, relevant, sent letter.
    #
    # @param applicant [IvcChampvaApplicant]
    # @return [Boolean]
    def application_letter_present?(applicant)
      return false if application_submitted_at.blank?

      BenefitsClaims::Providers::IvcChampva::RepeatIneligibilityLetterActivity
        .sent_letters_for(applicant)
        .any? { |letter| letter.mail_status_date.present? && letter.mail_status_date > application_submitted_at }
    end

    # Persists any new VES mail-correspondence letters for this applicant. VES may
    # not have letter history yet on the initial request, so a missing/empty
    # array is a no-op.
    #
    # @param applicant [IvcChampvaApplicant]
    # @param data [Hash] the EE Summary response for this applicant
    # @return [void]
    def persist_letters(applicant, data)
      Array(data['mailCorrespondences']).each do |correspondence|
        persist_letter(applicant, correspondence)
      end
    end

    # Persists a single VES mail-correspondence entry as a new letter record, unless
    # it predates the application's submission, is missing a form number, isn't on
    # the CHAMPVA Status Tool's approved-letter allowlist (see
    # IvcChampva::ChampvaLetterAllowlist -- VES returns many correspondence types
    # unrelated to CHAMPVA, and only approved ones should affect recent-activity,
    # repeat-ineligibility, or Last Updated date logic), or a matching letter (same
    # applicant, form number, and mail status date) already exists. Holds a
    # Postgres advisory lock keyed on that same tuple so two concurrent runs can't
    # both pass the existence check and insert duplicates; the unique index and NOT
    # NULL constraint backing that tuple are a second line of defense against the
    # same race.
    #
    # @param applicant [IvcChampvaApplicant]
    # @param correspondence [Hash]
    # @return [void]
    def persist_letter(applicant, correspondence)
      mail_status_date = parsed_mail_status_date(correspondence['mailStatusDate'])
      return if mail_status_date.blank? || application_submitted_at.blank?
      return if mail_status_date <= application_submitted_at

      template = correspondence['letterTemplate'] || {}
      form_number = template['formNumber']
      return if form_number.blank?
      return unless IvcChampva::ChampvaLetterAllowlist.approved?(form_number)

      lock_form_number = form_number.to_s.downcase
      lock_key = "ivc_champva_letter-#{applicant.id}-#{lock_form_number}-#{mail_status_date.to_i}"
      IvcChampvaLetter.with_advisory_lock(lock_key) do
        next if duplicate_letter?(applicant, form_number, mail_status_date)

        applicant.ivc_champva_letters.create!(
          letter_name: template['name'],
          form_number:,
          mail_status: correspondence['mailStatus'],
          mail_status_date:
        )
        @letters_created_count += 1
      end
    rescue ActiveRecord::RecordNotUnique
      # Already persisted by this same call or a concurrent run.
    end

    # Case-insensitive on form_number to match IvcChampva::ChampvaLetterAllowlist's own
    # comparison (which normalizes/downcases) -- otherwise the same letter returned by VES
    # with different casing across calls would pass the allowlist as "the same approved
    # letter" both times, but slip past this dedup check as if it were two different ones,
    # inserting a duplicate row.
    #
    # @param applicant [IvcChampvaApplicant]
    # @param form_number [String]
    # @param mail_status_date [ActiveSupport::TimeWithZone]
    # @return [Boolean]
    def duplicate_letter?(applicant, form_number, mail_status_date)
      applicant.ivc_champva_letters
               .exists?(['LOWER(form_number) = LOWER(?) AND mail_status_date = ?', form_number, mail_status_date])
    end

    # @param mail_status_date [String, nil]
    # @return [ActiveSupport::TimeWithZone, nil]
    def parsed_mail_status_date(mail_status_date)
      return nil if mail_status_date.blank?

      Time.zone.parse(mail_status_date)
    rescue ArgumentError, TypeError
      nil
    end

    # Increments STUCK_APPLICATION_METRIC when this application was submitted longer
    # ago than STUCK_APPLICATION_THRESHOLD but still has at least one applicant with
    # eligibility_resolved: false -- i.e. it still shows 'claimReceived' rather than
    # 'complete' (see BenefitsClaims::Providers::IvcChampva::ClaimBuilder.status_for).
    #
    # @param applicants [Array<IvcChampvaApplicant>]
    # @return [void]
    def track_if_stuck(applicants)
      return if applicants.blank?
      # Reuses the same "fully resolved" definition ClaimBuilder uses to derive the
      # FE-visible status ('complete' vs 'claimReceived'), rather than an independent
      # copy of that check, so this metric can't silently drift from what the FE shows.
      return if IvcChampvaApplicant.all_resolved_for?(@transaction_uuid)
      return if application_submitted_at.blank? || application_submitted_at > STUCK_APPLICATION_THRESHOLD.ago

      StatsD.increment(STUCK_APPLICATION_METRIC)
    end

    # Earliest CHAMPVA form creation time for this transaction, used as a proxy
    # for the application's submission date (no explicit submitted_at exists).
    #
    # @return [ActiveSupport::TimeWithZone, nil]
    def application_submitted_at
      return @application_submitted_at if defined?(@application_submitted_at)

      @application_submitted_at = IvcChampvaForm.where(transaction_uuid: @transaction_uuid).minimum(:created_at)
    end

    # Persists the sponsor record for this transaction from the EE Summary sponsor
    # data, but only when no sponsor record exists yet for the transaction. The
    # sponsor's ICN, eligibility status, and reason come from the EE Summary; the
    # sponsor's name is looked up in MPI by that ICN.
    #
    # @param eligibility [Hash] a single CHAMPVA eligibility entry from the EE Summary
    # @return [void]
    def persist_sponsor(eligibility)
      sponsor = eligibility['sponsor'] || {}
      sponsor_icn = sponsor['icn']
      return if sponsor_icn.blank?

      existing_sponsor = IvcChampvaSponsor.find_by(transaction_uuid: @transaction_uuid)
      return existing_sponsor if existing_sponsor

      name = mpi_service.lookup_name_by_icn(sponsor_icn) || {}
      IvcChampvaSponsor
        .create_with(
          sponsor_icn:,
          first_name: name[:first_name],
          last_name: name[:last_name],
          eligibility_status: sponsor['champvaStatus'],
          reason: sponsor['champvaReason']
        )
        .find_or_create_by!(transaction_uuid: @transaction_uuid)
    rescue ActiveRecord::RecordNotUnique
      # Another concurrent run created the sponsor row first.
      IvcChampvaSponsor.find_by(transaction_uuid: @transaction_uuid)
    end

    # Maps a VES eligibility entry to IvcChampvaApplicant column values.
    #
    # @param eligibility [Hash]
    # @return [Hash] applicant attributes to persist
    def eligibility_attributes(eligibility)
      sponsor = eligibility['sponsor'] || {}
      {
        ves_eligibility_status: eligibility['status'],
        ves_eligibility_reason: eligibility['reason'],
        ves_status_updated_date: eligibility['statusUpdatedDate'],
        sponsor_icn: sponsor['icn'],
        sponsor_eligibility_status: sponsor['champvaStatus'],
        sponsor_eligibility_reason: sponsor['champvaReason'],
        documents_requested: documents_requested?(eligibility['status'], eligibility['reason']),
        eligibility_resolved: true
      }
    end

    # Returns true when the given VES status is in the configured list of statuses
    # that require additional documents from the applicant, or when the applicant
    # is ineligible for one of the configured reasons (some reason codes, like
    # AUTO-CALC OFF, are also used on eligible rows, so the reason check only
    # applies while the status itself is ineligible).
    #
    # @param status [String, nil]
    # @param reason [String, nil]
    # @return [Boolean]
    def documents_requested?(status, reason)
      normalized_status = status.to_s.downcase.strip
      requested = DOCUMENTS_REQUESTED_STATUSES.include?(normalized_status) ||
                  (normalized_status.include?('ineligible') &&
                   DOCUMENTS_REQUESTED_REASONS.include?(reason.to_s.downcase.strip))
      StatsD.increment(DOCUMENTS_REQUESTED_METRIC) if requested
      requested
    end

    # Digs the first CHAMPVA eligibility entry out of the EE Summary response.
    #
    # @param data [Hash, nil]
    # @return [Hash, nil] the first eligibility hash, or nil when none present
    def extract_champva_eligibility(data)
      self.class.extract_champva_eligibility(data)
    end

    # @return [IvcChampva::MPIService]
    def mpi_service
      @mpi_service ||= IvcChampva::MPIService.new
    end
  end
  # rubocop:enable Metrics/ClassLength
end
