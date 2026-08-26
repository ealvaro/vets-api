# frozen_string_literal: true

require 'ves_api/client'

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
  class ChampvaEligibilityService
    DOCUMENTS_REQUESTED_STATUSES_PATH =
      Rails.root.join('config', 'benefits_claims', 'ves_documents_requested_statuses.json').freeze

    DOCUMENTS_REQUESTED_CONFIG = begin
      JSON.parse(File.read(DOCUMENTS_REQUESTED_STATUSES_PATH))
    rescue => e
      Rails.logger.error(
        'ChampvaEligibilityService: Failed to load VES documents requested statuses',
        { message: e.message }
      )
      {}
    end

    DOCUMENTS_REQUESTED_STATUSES =
      DOCUMENTS_REQUESTED_CONFIG.fetch('statuses', []).to_set { |s| s.to_s.downcase.strip }.freeze
    DOCUMENTS_REQUESTED_REASONS =
      DOCUMENTS_REQUESTED_CONFIG.fetch('reasons', []).to_set { |r| r.to_s.downcase.strip }.freeze

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
      log_ves_error("application #{status}", error, level:)
      { status:, persons: [], created_count: 0, existing_count: 0, error: error.message }
    end

    # Logs a VES error against this transaction at the given severity.
    #
    # @param context [String] short description of what failed
    # @param error [StandardError]
    # @param level [Symbol] Rails logger severity (:info, :error, ...)
    def log_ves_error(context, error, level: :error)
      Rails.logger.public_send(
        level, "ChampvaEligibilityService: #{context} for #{@transaction_uuid}: #{error.message}"
      )
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
      # Another concurrent run created the applicant row first.
      existing = IvcChampvaApplicant.find_by(transaction_uuid: @transaction_uuid, applicant_icn:)
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
      log_ves_error('EE summary pending', e, level: :info)
      false
    rescue IvcChampva::VesApi::VesApiError => e
      log_ves_error('EE summary error', e)
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

    # True once VES has generated at least one mail-correspondence entry for this
    # applicant dated after the application's submission — i.e. proof a letter has
    # actually gone out for the current application. Used to let a stale-looking
    # status (per stale_prior_application_status?) through once a letter confirms
    # it, even when the letter repeats the same status/reason as before ("the status
    # may not change if the decision did not change").
    #
    # @param applicant [IvcChampvaApplicant]
    # @return [Boolean]
    def application_letter_present?(applicant)
      return false if application_submitted_at.blank?

      applicant.ivc_champva_letters.exists?(['mail_status_date > ?', application_submitted_at])
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
    # it predates the application's submission, is missing a form number, or a
    # matching letter (same applicant, form number, and mail status date) already
    # exists. Holds a Postgres advisory lock keyed on that same tuple so two
    # concurrent runs can't both pass the existence check and insert duplicates; the
    # unique index and NOT NULL constraint backing that tuple are a second line of
    # defense against the same race.
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

      lock_key = "ivc_champva_letter-#{applicant.id}-#{form_number}-#{mail_status_date.to_i}"

      IvcChampvaLetter.with_advisory_lock(lock_key) do
        next if applicant.ivc_champva_letters.exists?(form_number:, mail_status_date:)

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

    # @param mail_status_date [String, nil]
    # @return [ActiveSupport::TimeWithZone, nil]
    def parsed_mail_status_date(mail_status_date)
      return nil if mail_status_date.blank?

      Time.zone.parse(mail_status_date)
    rescue ArgumentError, TypeError
      nil
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
      return true if DOCUMENTS_REQUESTED_STATUSES.include?(normalized_status)

      normalized_status.include?('ineligible') && DOCUMENTS_REQUESTED_REASONS.include?(reason.to_s.downcase.strip)
    end

    # Digs the first CHAMPVA eligibility entry out of the EE Summary response.
    #
    # VES response 'data' shape:
    #   { "vfmpProgramsInfo": { "relationships": [
    #       { "champvaEligibilities": [
    #           { "status": ..., "reason": ...,
    #             "sponsor": { "icn": ..., "champvaStatus": ..., "champvaReason": ... } } ] } ] } }
    #
    # @param data [Hash, nil]
    # @return [Hash, nil] the first eligibility hash, or nil when none present
    def extract_champva_eligibility(data)
      return nil unless data.is_a?(Hash)

      relationships = data.dig('vfmpProgramsInfo', 'relationships')
      return nil unless relationships.is_a?(Array)

      relationships
        .flat_map { |relationship| relationship['champvaEligibilities'] || [] }
        .first
    end

    # @return [IvcChampva::MPIService]
    def mpi_service
      @mpi_service ||= IvcChampva::MPIService.new
    end
  end
end
