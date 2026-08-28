# frozen_string_literal: true

# Staging-only VES stub that walks a single CHAMPVA Status Tool demo application through a
# fixed sequence of review scenarios, one step per refresh, for the staging walkthrough
# covering test cases T-001 through T-013 (see PR discussion for the full list).
#
# Gated at boot by Settings.vsp_environment == 'staging' (Rails.env is 'production' on
# staging infra -- vsp_environment is this app's established way to distinguish the two,
# see e.g. app/models/va_profile_redis/v2/contact_information.rb) -- OR, for exercising this
# exact code path locally before it ever reaches staging, Rails.env.development? with
# ENV['CHAMPVA_STAGING_SCENARIO_STUB'] == 'true' (same opt-in-ENV-var-at-boot shape as
# config/initializers/ivc_champva_dev_ves_stub.rb, and deliberately NOT wired through
# Settings.vsp_environment locally -- overriding that setting to 'staging' in
# settings.local.yml has real side effects elsewhere in the app, e.g.
# SignIn::ClientConfig#appropriate_mock_environment? no longer treating your session as a
# mock-auth-eligible environment and breaking local login). Either way this file is always
# prepended once its gate is true, and each stubbed method checks the *same* Flipper flag as
# the rate limit bypass -- :champva_eligibility_rate_limit_disabled -- at call time (no
# actor, so a single global Flipper toggle controls it for the whole review session). Flag
# off: falls through to the real VES client (super), completely inert. Flag on: bypasses the
# rate limit (see ChampvaEligibilityController#rate_limit_disabled?) AND returns this file's
# canned data. One flag, one demo-mode toggle, safe to leave permanently off in production
# (this file never even loads there) and off by default on staging until a reviewer is ready.
#
# The flag being global (no actor) means this can't tell "the demo application" apart from
# any other CHAMPVA application on staging by the flag alone -- so StagingScenarioStub pins
# itself to the FIRST transaction_uuid it sees while active (see #for_transaction?) and
# leaves every other application's VES/MPI calls untouched for as long as that pin holds.
# This protects real Veterans' applications from being swapped for Jon/Jane's canned data
# during a review window, and means a second reviewer's own (different) application doesn't
# corrupt the first reviewer's walkthrough step counter -- it just gets real VES/MPI calls
# instead. It does NOT make this multi-reviewer-safe in the sense of supporting several
# *concurrent* walkthroughs -- only one demo application can be actively stepped through at
# a time; #reset_for! releases the pin so a new one can be armed.
#
# ── Testing locally before staging ──────────────────────────────────────────────────────
#   CHAMPVA_STAGING_SCENARIO_STUB=true bin/rails server (or foreman start, however you
#   normally run vets-api locally) -- then follow the review-session steps below exactly as
#   written, on your local CST page instead of staging's. No vsp_environment override, no
#   local login side effects. The old dev VES stub (CHAMPVA_STUB_VES/CHAMPVA_STUB_MPI) and
#   this one can't both be active in the same process in a meaningful way -- don't set both.
#
# ── Setup for a review session ──────────────────────────────────────────────────────────
#   1. On staging, enable the :champva_eligibility_rate_limit_disabled flag (Flipper UI,
#      global/boolean enable -- do not scope it to a specific actor, since the VES-client
#      side of this checks Flipper.enabled?(flag) with no actor).
#   2. Manually create a fresh CHAMPVA 10-10D application (however you'd normally do this
#      on staging -- through the real form, or a console-created IvcChampvaForm row), OR
#      reuse an existing demo application -- see step 4 below before reusing one that's
#      already been through this walkthrough.
#   3. Load the application's CST page. That first load is "free" -- it arms the
#      walkthrough but does not advance it, since the page fires this same POST
#      automatically on mount and there'd otherwise be no way to tell that automatic call
#      apart from a reviewer's own first refresh. Every refresh *after* that first load (a
#      real browser refresh, or the tool's own refresh control -- whatever triggers
#      POST /ivc_champva/v1/forms/champva_eligibility) advances exactly one step:
#
#        Refresh 1 → Step 1 Received            (T-002 – T-005)
#        Refresh 2 → Step 2 Decided / mixed      (T-006 – T-010)
#        Refresh 3 → Step 3 Repeat ineligibility (T-011)
#        Refresh 4 → Step 4 All not-enrolled     (T-013)
#        Refresh 5 → Step 5 All enrolled         (T-012)
#        Refresh 6+ stays at Step 5 (no further advancement).
#
#      T-012/T-013 are intentionally visited in this order (not the original 12-then-13
#      numbering) -- see "Why T-012 and T-013 swap positions" below for why.
#   4. To restart the walkthrough from Step 1 on the SAME application (whether it's fresh
#      or was already stepped through before), call
#      IvcChampva::StagingScenarioStub.reset_for!(transaction_uuid) from a console/runner
#      on staging -- NOT the bare .reset! by itself. .reset! only rewinds this stub's own
#      step counter, which is global, not tied to any one application; the application's
#      own IvcChampvaApplicant rows can still be stuck showing a later step's eligibility
#      from before (VES/the stub never un-confirms an already-eligible applicant -- see
#      .reset_for!'s own doc for the full explanation). Calling .reset! alone looks like it
#      worked and then the walkthrough is right back to appearing frozen/broken. To check
#      where the sequence currently is without resetting, call .current_step.
#   5. When the review session is done, turn the flag back off.
#
# ── Why T-012 (All enrolled) and T-013 (All not-enrolled) swap positions ───────────────
# ChampvaEligibilityService#persist_eligibility permanently stops updating an applicant's
# eligibility_status/reason once IvcChampvaApplicant#eligible? is true (any status starting
# with "Eligible") -- real production behavior, not a stub limitation: once VES confirms
# someone enrolled, that determination doesn't get re-checked. That makes "walk the same
# beneficiary from enrolled back to not-enrolled" structurally impossible, so All enrolled
# has to be the final step, not the second-to-last one.
#
# ── Why one beneficiary (Jane), not two ─────────────────────────────────────────────────
# The sponsor is Eligible-Active from Step 2 onward (matches real VES data and this app's
# existing dev stub -- sponsors are essentially always already-resolved) and, per the
# eligible?-freeze above, can never appear "not enrolled" again after that. So "All
# not-enrolled" (T-013) and "All enrolled" (T-012) are necessarily about the beneficiary
# population being reviewed, not a literal 100% including the sponsor's own row -- a second
# beneficiary who became eligible back at Step 2 (to satisfy T-007's "one enrolled/one not
# enrolled") would hit the exact same freeze and be unable to ever show "not enrolled" at
# Step 4. Using a single beneficiary (Jane) for the whole "not enrolled" narrative, with the
# sponsor standing in as T-007's "one enrolled" party, avoids the conflict entirely while
# still satisfying every test case as written. If the intent was for T-013 to require a
# beneficiary who was never enrolled at any earlier step, add a second, independent
# beneficiary ICN below that skips Steps 2-3 and only appears starting at Step 4.
#
# T-001 (MyVA card links to CST) and T-009's "click the applicant card link" sub-question
# aren't stub concerns -- T-001 already works for any CHAMPVA application via the existing
# My VA card logic, and the applicant-card link (if it exists) is pure FE navigation.

module IvcChampva
  # rubocop:disable Metrics/ModuleLength
  module StagingScenarioStub
    STUB_ICN_SPONSOR = '0000001200603260V008079000000'
    STUB_ICN_BENEFICIARY = '0000001200603261V181504000000'

    # Fake ICNs have no real MPI record on staging any more than they do locally, so
    # backfill_applicant_names would otherwise leave every card blank/"The applicant" --
    # see IvcChampva::MPIService prepend below.
    STUB_NAME_BY_ICN = {
      STUB_ICN_SPONSOR => { first_name: 'Jon', last_name: 'Doe' },
      STUB_ICN_BENEFICIARY => { first_name: 'Jane', last_name: 'Doe' }
    }.freeze

    CACHE_KEY = 'ivc_champva:staging_scenario_state'
    CACHE_EXPIRY = 24.hours
    MAX_STEP = 5

    FLIPPER_FLAG = :champva_eligibility_rate_limit_disabled

    # @return [Boolean] whether the demo-mode stub should be active for this call --
    #   checked with no actor, so only a global (not per-user) Flipper enable drives it.
    #   ChampvaEligibilityController#rate_limit_disabled? checks this SAME flag WITH an
    #   actor (@current_user) -- that's intentional, not a bug to fix here, but it does mean
    #   the two checks can disagree: a per-actor-only enable bypasses that one reviewer's
    #   rate limit while leaving this stub inert (real VES/MPI calls, no error, walkthrough
    #   silently doesn't happen), while a global enable does both at once for everyone. See
    #   config/features.yml's description for FLIPPER_FLAG, and always use a global/boolean
    #   enable (not scoped to an actor) per step 1 of "Setup for a review session" below.
    def self.active?
      Flipper.enabled?(FLIPPER_FLAG)
    end

    # { step:, armed:, letter_dates:, transaction_uuid: } --
    #   letter_dates memoizes each letter's mailStatusDate the first time it's introduced
    #     (see #letter_date) so it stays exactly the same on every later refresh;
    #     ChampvaEligibilityService's persist_letter only treats a (form_number,
    #     mail_status_date) tuple as "already exists" when the date matches exactly, so a
    #     letter recomputed fresh on every call would look like a brand new one each time
    #     and duplicate endlessly instead of persisting once.
    #   armed: false until the walkthrough's first POST, then true forever after -- see
    #     #advance!'s doc for why this exists.
    #   transaction_uuid: nil until #for_transaction? first pins it -- this is CACHE_KEY's
    #     single global piece of state, so this is what makes exactly one demo application
    #     "the" walkthrough at a time; see #for_transaction?'s own doc for why.
    #
    # @return [Hash]
    def self.state
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY) do
        { step: 0, armed: false, letter_dates: {}, transaction_uuid: nil }
      end
    end

    # @return [Integer] the current step (0 before the first refresh, capped at MAX_STEP)
    def self.current_step
      state[:step]
    end

    # Advances to the next step (capped at MAX_STEP) and returns the new value. Called once
    # per POST /ivc_champva/v1/forms/champva_eligibility request -- see the
    # ChampvaEligibilityController prepend below -- not once per applicant, so a single
    # refresh (which syncs every applicant on the application) only advances once.
    #
    # The CST page fires this same POST automatically on page load, before a reviewer gets
    # to do their own first intentional refresh -- from the backend's side there's no way
    # to tell that automatic on-mount call apart from a real one, they're identical
    # requests. Without accounting for that, page load itself silently consumes Step 1,
    # throwing off the documented "one refresh = one step" mapping before the walkthrough
    # even starts. So the very first call after a reset only "arms" the walkthrough (sets
    # armed: true, leaves step at 0) rather than advancing -- meaning page load is always
    # free, and the reviewer's first real refresh after that is what shows Step 1.
    #
    # @return [Integer]
    def self.advance!
      return write_state(state.merge(armed: true))[:step] unless state[:armed]

      write_state(state.merge(step: [current_step + 1, MAX_STEP].min))[:step]
    end

    # Whether the given transaction_uuid is (or becomes) this process's single pinned demo
    # application. Pins to the FIRST transaction_uuid seen after a reset -- CACHE_KEY's
    # step/armed/letter_dates state is one global counter, not tracked per application, so
    # without this, enabling the FLIPPER_FLAG would silently swap EVERY CHAMPVA
    # application's VES/MPI data for Jon/Jane's, not just the one demo application a
    # reviewer means to step through -- including any real Veteran's application refreshed
    # on staging during that same window. Once pinned, a different transaction_uuid always
    # returns false here, so a concurrent reviewer's own (different) application falls
    # through to the real VES/MPI services (see the client/service prepends below) instead
    # of being folded into -- or advancing -- someone else's walkthrough. Cleared together
    # with the rest of #state by #reset!/#reset_for!.
    #
    # @param transaction_uuid [String]
    # @return [Boolean]
    def self.for_transaction?(transaction_uuid)
      current = state
      return true if current[:transaction_uuid] == transaction_uuid
      return false if current[:transaction_uuid].present?

      write_state(current.merge(transaction_uuid:))
      true
    end

    # Calls #advance! only when at least one of the given transaction_uuids is (or becomes,
    # via #for_transaction?) this process's pinned demo application -- see the
    # ChampvaEligibilityController prepend below, which calls this once per request with
    # that request's resolved transaction_uuids instead of calling #advance! unconditionally.
    # A request that turns out to be for a different application is a no-op here: it neither
    # advances this walkthrough's step counter nor is advanced by it.
    #
    # @param transaction_uuids [Array<String>]
    # @return [Integer] the current step (unchanged when this call didn't advance)
    def self.advance_for!(transaction_uuids)
      return current_step unless Array(transaction_uuids).any? { |uuid| for_transaction?(uuid) }

      advance!
    end

    # Resets the walkthrough back to before Step 1 -- including every memoized letter date
    # -- for reusing the same demo application across multiple review sessions instead of
    # creating a new one each time.
    #
    # Only clears this stub's own state (step/armed/letter_dates). It does NOT touch any
    # IvcChampvaApplicant/IvcChampvaSponsor/IvcChampvaLetter rows already persisted for a
    # given application -- see .reset_for! below for why calling this alone is usually the
    # wrong tool for restarting a walkthrough on an *existing* demo application.
    #
    # @return [void]
    def self.reset!
      Rails.cache.delete(CACHE_KEY)
    end

    # Use this, not the bare .reset! above, to restart the walkthrough on an existing demo
    # application. .reset! alone only rewinds this stub's own step counter -- it's a single
    # piece of global state, not tied to any one application. ChampvaEligibilityService
    # permanently freezes an applicant's eligibility once VES (or, here, the stub) confirms
    # them enrolled -- real production behavior, not a stub limitation -- so if the
    # application already advanced past Step 1 before, its IvcChampvaApplicant rows are
    # stuck showing that old, later state no matter what the stub's own counter says
    # afterward. The very first POST against a freshly-reset stub would otherwise persist
    # against those stale rows and the walkthrough would look broken/frozen again, exactly
    # as if nothing had been reset at all. This clears both pieces together: the stub's own
    # counter, and every IvcChampvaApplicant/IvcChampvaSponsor row (and their letters, which
    # cascade-delete automatically) for the given application -- so the next page load
    # starts genuinely clean.
    #
    # @param transaction_uuid [String] the demo application's transaction_uuid (same value
    #   IvcChampvaForm#transaction_uuid holds -- find it via
    #   IvcChampvaForm.find_by(form_uuid: '<the CST URL's claim id>')&.transaction_uuid if
    #   you only have the CST page URL handy)
    # @return [void]
    def self.reset_for!(transaction_uuid)
      # This is meant to be typed by hand into a staging console -- fail fast instead of
      # silently scoping the destroy_all calls below to every row with a NULL
      # transaction_uuid if it's ever called with a blank/missing argument by mistake.
      raise ArgumentError, 'transaction_uuid required' if transaction_uuid.blank?

      reset!
      IvcChampvaApplicant.where(transaction_uuid:).destroy_all
      IvcChampvaSponsor.where(transaction_uuid:).destroy_all
    end

    # The mailStatusDate for a given letter, computed and cached the first time it's asked
    # for (see the #state doc for why this must stay stable across calls) and reused as-is
    # after that.
    #
    # @param key [String] stable identifier for this particular letter
    # @param minutes_from_now [Integer] how far into the future to date it, the first time
    #   only -- see #letters_for's doc for why "from now" rather than a fixed past date
    # @return [String] ISO-8601 timestamp
    def self.letter_date(key, minutes_from_now:)
      current = state
      return current[:letter_dates][key] if current[:letter_dates][key]

      date = minutes_from_now.minutes.from_now.iso8601
      write_state(current.merge(letter_dates: current[:letter_dates].merge(key => date)))
      date
    end

    # @return [Hash] the state just written
    def self.write_state(new_state)
      Rails.cache.write(CACHE_KEY, new_state, expires_in: CACHE_EXPIRY)
      new_state
    end

    # @param icn [String]
    # @return [Boolean]
    def self.sponsor?(icn)
      icn == STUB_ICN_SPONSOR
    end

    # Whether icn is one of this stub's own two fixed demo identities, as opposed to a real
    # applicant's ICN. get_ee_summary below must check this (not just .active?) before
    # routing to canned data -- unlike get_icns_for_transaction, it's only ever called with
    # an ICN already resolved earlier in the request (from a real MPI/VES lookup or from
    # .persons above), so it has no transaction_uuid of its own to pin against. Without this
    # guard, a real Veteran's ICN reaching this method while the flag is globally enabled
    # would still get routed into beneficiary_eligibility and have canned
    # status/reason/letters persisted onto their actual IvcChampvaApplicant row.
    #
    # @param icn [String]
    # @return [Boolean]
    def self.stub_icn?(icn)
      [STUB_ICN_SPONSOR, STUB_ICN_BENEFICIARY].include?(icn)
    end

    # Looks up this applicant/sponsor's real submitted name on the demo application itself
    # (its earliest IvcChampvaForm#request_json), so the CST cards show whatever name a
    # reviewer actually typed into the demo 10-10D rather than the fixed "Jon Doe"/"Jane
    # Doe" placeholders below -- reviewers routinely reuse one demo application across
    # many review sessions with a different real name filled in each time. Falls back to the
    # fixed placeholder name whenever the real submission can't be found or doesn't parse
    # (e.g. the ICN hasn't been persisted to an IvcChampvaApplicant row yet, or the demo
    # application isn't a 10-10D shaped the way this expects).
    #
    # @param icn [String] STUB_ICN_SPONSOR or STUB_ICN_BENEFICIARY
    # @return [Hash, nil] { first_name:, last_name: }
    def self.name_for(icn)
      real_name_from_application(icn) || STUB_NAME_BY_ICN[icn]
    end

    # @param icn [String]
    # @return [Hash, nil]
    def self.real_name_from_application(icn)
      # applicant_icn is a Lockbox-encrypted attribute (see IvcChampvaApplicant's
      # has_encrypted declaration), not a real column -- only applicant_icn_ciphertext is --
      # so find_by/where can't query it directly (raises PG::UndefinedColumn). This table
      # only ever holds rows for the two fixed stub ICNs plus whatever a reviewer's own
      # testing has added, so scanning and matching the decrypted value in Ruby is cheap
      # enough here, same pattern ChampvaEligibilityService itself uses for the same reason.
      transaction_uuid = IvcChampvaApplicant.all.find { |a| a.applicant_icn == icn }&.transaction_uuid
      return nil if transaction_uuid.blank?

      sponsor?(icn) ? sponsor_name_from_forms(transaction_uuid) : beneficiary_name_from_forms(transaction_uuid)
    end

    # The sponsor is the 10-10D's own 'veteran' -- the person filling out/certifying the
    # application -- not one of the 'applicants' being enrolled.
    #
    # @param transaction_uuid [String]
    # @return [Hash, nil]
    def self.sponsor_name_from_forms(transaction_uuid)
      name_hash_from_forms(transaction_uuid) do |data|
        data.dig('veteran', 'full_name') || data.dig('veteran', 'fullName')
      end
    end

    # Only the first applicant entered on the form -- this walkthrough only ever tracks one
    # beneficiary (see file header, "Why one beneficiary (Jane), not two"), so a demo
    # application with several applicants listed still needs exactly one name here.
    #
    # @param transaction_uuid [String]
    # @return [Hash, nil]
    def self.beneficiary_name_from_forms(transaction_uuid)
      name_hash_from_forms(transaction_uuid) do |data|
        applicant = Array(data['applicants']).first
        next nil unless applicant.is_a?(Hash)

        applicant['applicantName'] || applicant['applicant_name']
      end
    end

    # Tries every form record for the transaction, NEWEST first, until one yields a usable
    # name -- a supplemental/file-upload row has no request_json of its own (see
    # ClaimBuilder.transaction_uuid_for's own comment on this), so the most recent 10-10D
    # submission isn't guaranteed to be the very last row depending on upload order, and this
    # needs to keep scanning past those instead of assuming the newest row is always it.
    # Newest-first (not oldest-first) specifically so that reusing one demo application
    # across review sessions with a different real name resubmitted each time (see this
    # module's own real_name_from_application doc) actually picks up the latest name, rather
    # than permanently locking onto whatever name that transaction_uuid's very first
    # submission ever had.
    #
    # @param transaction_uuid [String]
    # @yieldparam data [Hash] the parsed request_json for one form record
    # @yieldreturn [Hash, nil] a raw { 'first' =>, 'last' => } (or *_name-suffixed) name hash
    # @return [Hash, nil] { first_name:, last_name: }, or nil once no record yields a name
    def self.name_hash_from_forms(transaction_uuid)
      IvcChampvaForm.where(transaction_uuid:).order(created_at: :desc).each do |form|
        name = yield(parse_request_json(form.request_json))
        return normalized_name(name) if name.is_a?(Hash)
      end
      nil
    end

    # @param name [Hash] a raw name hash off request_json, in either camelCase or snake_case
    # @return [Hash] { first_name:, last_name: }
    def self.normalized_name(name)
      {
        first_name: name['first'] || name['first_name'] || name[:first] || name[:first_name],
        last_name: name['last'] || name['last_name'] || name[:last] || name[:last_name]
      }
    end

    # @param request_json [String, Hash, nil]
    # @return [Hash]
    def self.parse_request_json(request_json)
      return request_json if request_json.is_a?(Hash)
      return {} if request_json.blank?

      JSON.parse(request_json)
    rescue JSON::ParserError
      {}
    end

    # Sponsor and beneficiary persons for the demo transaction. Identity doesn't change
    # across steps, only eligibility/letters do, so this ignores the current step.
    #
    # @return [Array<Hash>]
    def self.persons
      [
        { 'icn' => STUB_ICN_SPONSOR, 'personUUID' => '682', 'personType' => 'SPONSOR' },
        { 'icn' => STUB_ICN_BENEFICIARY, 'personUUID' => '638', 'personType' => 'BENEFICIARY' }
      ]
    end

    # Builds the get_ee_summary response for the given ICN at the current step.
    #
    # @param icn [String]
    # @return [Hash]
    def self.ee_summary_for(icn)
      step = current_step
      {
        'vfmpProgramsInfo' => { 'relationships' => [{ 'champvaEligibilities' => eligibilities_for(icn, step) }] },
        'mailCorrespondences' => letters_for(icn, step)
      }
    end

    # @param icn [String]
    # @param step [Integer]
    # @return [Array<Hash>] zero or one champvaEligibilities entries, per get_ee_summary's shape
    def self.eligibilities_for(icn, step)
      eligibility = sponsor?(icn) ? sponsor_eligibility(step) : beneficiary_eligibility(step)
      return [] if eligibility.nil?

      [
        {
          'statusUpdatedDate' => status_updated_date_for(step),
          'status' => eligibility[:status],
          'reason' => eligibility[:reason],
          'sponsor' => {
            'icn' => STUB_ICN_SPONSOR,
            'champvaStatus' => 'ELIGIBLE',
            'champvaReason' => 'P&T'
          }
        }
      ]
    end

    # Sponsor is resolved starting at Step 2 (Decided) and never changes after that --
    # see the file header for why. nil at Step 1 (Received -- nothing decided yet).
    #
    # @return [Hash, nil]
    def self.sponsor_eligibility(step)
      return nil if step < 2

      { status: 'Eligible-Active', reason: 'auto-calc off' }
    end

    # Jane's eligibility across the walkthrough:
    #   Step 1 -- nil (Received, nothing decided yet)
    #   Steps 2-3 -- Ineligible / "no current school letter" (an actionable reason --
    #     documents_requested: true, file uploader open)
    #   Step 4 -- Ineligible / "disenrolled" (a final, non-actionable reason -- file
    #     uploader closes)
    #   Step 5 -- Eligible-Active (All enrolled, the walkthrough's final state)
    #
    # @return [Hash, nil]
    def self.beneficiary_eligibility(step)
      case step
      when 0, 1 then nil
      when 2, 3 then { status: 'Ineligible', reason: 'no current school letter' }
      when 4 then { status: 'Ineligible', reason: 'disenrolled' }
      else { status: 'Eligible-Active', reason: 'auto-calc off' }
      end
    end

    # A couple weeks before "today" for every step once a determination exists -- relative
    # to whenever the walkthrough actually runs, rather than a fixed calendar date, so this
    # doesn't go on looking more and more obviously fake as real time passes (this was
    # previously hardcoded to a fixed '2025-02-01', which -- as of whenever you're reading
    # this well after that date -- was sitting there looking like a determination from over
    # a year ago). Letter activity (below) is what actually drives "most recent activity"
    # across this walkthrough, same as the local dev stub's default (see
    # ivc_champva_dev_ves_stub.rb), so this only needs to read as a plausible past decision
    # date, not a precise one -- it's fine (and expected, for a freshly-created demo
    # application) for this to land before application_submitted_at and rely on
    # ChampvaEligibilityService's application_letter_present? fallback to let it through
    # anyway, same as before.
    #
    # @return [String, nil]
    def self.status_updated_date_for(step)
      return nil if step < 2

      14.days.ago.to_date.iso8601
    end

    # Letters for the given ICN at the current step. Each one is dated via #letter_date --
    # a little INTO THE FUTURE the first time it's introduced (matching
    # config/initializers/ivc_champva_dev_ves_stub.rb's own 1.minute.from_now pattern and its
    # comment on why: ChampvaEligibilityService#persist_letter rejects anything dated
    # at-or-before the application's created_at, and iso8601's whole-second truncation means
    # even "now" can round down to <= a form created moments earlier), then memoized so it
    # stays the exact same tuple on every later refresh -- see #state's doc for why that
    # matters. Increasing offsets per letter keep them chronologically ordered.
    #
    # @param icn [String]
    # @param step [Integer]
    # @return [Array<Hash>]
    def self.letters_for(icn, step)
      return [] if step < 2

      letters = [acceptance_letter(icn)]
      letters << repeat_ineligibility_letter(icn) if !sponsor?(icn) && step >= 3
      letters << final_reason_letter(icn) if !sponsor?(icn) && step >= 4
      letters << welcome_letter(icn) if step >= 5
      letters
    end

    def self.acceptance_letter(icn)
      {
        'letterTemplate' => {
          'name' => sponsor?(icn) ? 'CHAMPVA Sponsor Eligibility Confirmation' : 'CHAMPVA Decision Letter',
          'formNumber' => 'CCL-A43a.ENC'
        },
        'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
        'mailStatusDate' => letter_date("acceptance:#{icn}", minutes_from_now: 1)
      }
    end

    def self.repeat_ineligibility_letter(icn)
      {
        'letterTemplate' => { 'name' => 'CHAMPVA Ineligibility Letter (decision unchanged)',
                              'formNumber' => 'CCL-A43a.ENC' },
        'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
        'mailStatusDate' => letter_date("repeat_ineligibility:#{icn}", minutes_from_now: 2)
      }
    end

    def self.final_reason_letter(icn)
      {
        'letterTemplate' => { 'name' => 'CHAMPVA Ineligibility Letter (final)', 'formNumber' => 'CCL-A43a.ENC' },
        'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
        'mailStatusDate' => letter_date("final_reason:#{icn}", minutes_from_now: 3)
      }
    end

    def self.welcome_letter(icn)
      {
        'letterTemplate' => { 'name' => 'CHAMPVA Acceptance Letter and ID Card with Enclosures',
                              'formNumber' => 'CCL-A43a.ENC' },
        'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
        'mailStatusDate' => letter_date("welcome:#{icn}", minutes_from_now: 4)
      }
    end
  end
  # rubocop:enable Metrics/ModuleLength

  module VesApi
    module StagingScenarioClientMethods
      def get_icns_for_transaction(transaction_uuid)
        return super unless IvcChampva::StagingScenarioStub.active?
        return super unless IvcChampva::StagingScenarioStub.for_transaction?(transaction_uuid)

        IvcChampva::StagingScenarioStub.persons
      end

      def get_ee_summary(icn:, region_id_or_offset: nil)
        return super unless IvcChampva::StagingScenarioStub.active?
        return super unless IvcChampva::StagingScenarioStub.stub_icn?(icn)

        IvcChampva::StagingScenarioStub.ee_summary_for(icn)
      end
    end
  end

  module StagingScenarioMPIServiceMethods
    def lookup_name_by_icn(icn)
      return super unless IvcChampva::StagingScenarioStub.active?

      IvcChampva::StagingScenarioStub.name_for(icn) || super
    end
  end

  module V1
    module StagingScenarioControllerMethods
      # Overrides this private method (not #update) specifically so advance_for! runs with
      # the request's already-resolved transaction_uuid_map -- see
      # StagingScenarioStub.advance_for!'s doc for why the walkthrough's step counter needs
      # to know which application(s) a request is actually for. This also means advancing
      # only happens once #update has already passed its feature-flag/validation/rate-limit
      # checks (all of which run before this is reached), rather than unconditionally on
      # every POST regardless of outcome.
      def eligibility_results(transaction_uuid_map)
        if IvcChampva::StagingScenarioStub.active?
          IvcChampva::StagingScenarioStub.advance_for!(transaction_uuid_map.keys)
        end
        super
      end
    end
  end
end

module IvcChampva
  module StagingScenarioStubActivation
    # This file's boot-time gate -- see the file header for the full explanation of why
    # these two conditions (and only these two) open it. Extracted into its own method
    # (rather than a bare top-level local variable) so a spec can exercise it directly
    # against different Settings/Rails.env combinations without re-loading this whole file.
    #
    # @return [Boolean]
    def self.enabled_by_environment?
      Settings.vsp_environment.to_s == 'staging' ||
        (Rails.env.development? && ENV['CHAMPVA_STAGING_SCENARIO_STUB'] == 'true')
    end

    # Prepends this file's stub modules onto the VES client, MPI service, and eligibility
    # controller when #enabled_by_environment? is true; a complete no-op otherwise
    # (production-style settings never reach the prepend calls at all). Safe to call more
    # than once -- e.g. every class-reload in development re-runs initializers, and
    # Rails.application.config.to_prepare's own block can itself run multiple times -- since
    # each prepend below is individually guarded by its own `unless klass < Module` check,
    # so re-calling this never stacks a duplicate prepend into a class's ancestor chain.
    #
    # @return [Boolean] whether activation happened (i.e. #enabled_by_environment?)
    def self.call
      return false unless enabled_by_environment?

      Rails.logger.info('IVC CHAMPVA: staging scenario stub loaded (inert unless the ' \
                        "#{StagingScenarioStub::FLIPPER_FLAG} flag is enabled)")

      require 'ves_api/client'
      prepend_once(VesApi::Client, VesApi::StagingScenarioClientMethods)

      require 'ivc_champva/mpi_service'
      prepend_once(MPIService, StagingScenarioMPIServiceMethods)

      Rails.application.config.to_prepare { IvcChampva::StagingScenarioStubActivation.prepend_controller_stub! }

      true
    end

    # Split out from #call only so Rails.application.config.to_prepare has a plain method to
    # invoke -- to_prepare's own block runs via instance_exec against the Reloader, not
    # against this module, so the block above calls this fully-qualified rather than as a
    # bare method name (a bare call raised NoMethodError at boot: self inside the block isn't
    # StagingScenarioStubActivation). to_prepare's block can also run more than once per boot
    # (every class-reload in development re-registers/re-runs it), so this relies on the same
    # #prepend_once guard.
    #
    # @return [void]
    def self.prepend_controller_stub!
      prepend_once(IvcChampva::V1::ChampvaEligibilityController, IvcChampva::V1::StagingScenarioControllerMethods)
    end

    # Prepends mod onto klass unless it's already there. Safe to call more than once for the
    # same (klass, mod) pair -- e.g. every class-reload in development re-runs this whole
    # initializer -- without stacking a duplicate prepend into klass's ancestor chain.
    #
    # @param klass [Class]
    # @param mod [Module]
    # @return [void]
    def self.prepend_once(klass, mod)
      return if klass < mod

      klass.prepend(mod)
    end
  end
end

IvcChampva::StagingScenarioStubActivation.call
