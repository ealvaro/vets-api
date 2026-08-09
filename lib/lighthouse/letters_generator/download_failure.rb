# frozen_string_literal: true

require 'common/exceptions/unprocessable_entity'
require 'source_app_middleware'

module Lighthouse
  module LettersGenerator
    # Lighthouse rejects a letter download with a 422 and a free-text `detail`, e.g.
    # "The following errors are present: Missing Identifier Data". vets-api passed that string
    # straight through, so the failure was neither measurable nor actionable: the reason lived
    # only in the generic upstream error log and the veteran saw upstream jargon with no next
    # step, then retried an average of 13 times on a letter that could never generate.
    #
    # This maps the upstream text onto a small set of stable reason codes so download failures
    # can be counted by cause, and replaces the jargon with a message that says whether waiting
    # will help and what to do when it won't.
    module DownloadFailure
      STATSD_KEY = 'api.letters_generator.download.failure'
      UNKNOWN_SOURCE_APP = 'unknown'

      # A reason is a plain string: it is the StatsD tag value, the `reason` key clients read off
      # the error, and the i18n key suffix its copy is stored under. Veteran-facing copy lives in
      # config/locales/exceptions.en.yml under lighthouse.letters_generator.download_failure, so
      # content changes don't need a code change — see .message_for.

      # Durable: the veteran's record is missing identifiers the letter needs. Retrying never
      # succeeds, so the message has to point somewhere other than the download button.
      MISSING_IDENTIFIER_DATA = 'missing_identifier_data'

      # Durable: military service history the letter needs is missing from BIRLS. Kept separate
      # from MISSING_IDENTIFIER_DATA so the two upstream causes stay countable apart, even though
      # the veteran's next step is the same.
      MISSING_SERVICE_HISTORY = 'missing_service_history'

      # Durable, but the veteran can clear it themselves.
      NO_VALID_ADDRESS = 'no_valid_address'

      # Transient: a dependency of the letter generator was down for this request.
      VA_PROFILE_UNAVAILABLE = 'va_profile_unavailable'

      # Transient: BGS/MPI and other upstream connection failures the generator reports as a 422.
      BACKEND_SERVICE_ERROR = 'backend_service_error'

      UNKNOWN = 'unknown'

      # The published set of `reason` values a client can branch on, and the contract this class
      # owes them. Nothing in here reads it at runtime — it exists so the set is enumerable, which
      # is what lets a spec prove every reason has copy behind it. Don't prune it as unused.
      REASONS = [
        MISSING_IDENTIFIER_DATA,
        MISSING_SERVICE_HISTORY,
        NO_VALID_ADDRESS,
        VA_PROFILE_UNAVAILABLE,
        BACKEND_SERVICE_ERROR,
        UNKNOWN
      ].freeze

      # Matched in order, first hit wins. Lighthouse sends prose, not codes, so each pattern is
      # kept tight enough to only match text we have actually seen. Anything unmatched falls
      # through to UNKNOWN, whose copy is safe whether the cause turns out to be durable or
      # transient, and shows up under `reason:unknown` in StatsD — the signal that this list
      # needs another entry. Guessing wide is worse than falling through: misfiling a durable
      # cause as transient tells a veteran to retry something that can never succeed, which is
      # the exact behavior this class exists to stop.
      PATTERNS = [
        [/missing identifier/i, MISSING_IDENTIFIER_DATA],
        [/birls|releasedactivedutydate|branchofservice/i, MISSING_SERVICE_HISTORY],
        [/no valid address/i, NO_VALID_ADDRESS],
        [/contact info service unavailable/i, VA_PROFILE_UNAVAILABLE],
        [/backend service|connection error|\bbgs\b|\bmpi\b/i, BACKEND_SERVICE_ERROR]
      ].freeze

      class << self
        # Records the cause of a rejected download and returns a replacement exception carrying a
        # veteran-facing message plus a stable `reason` clients can branch on.
        #
        # @param error [Common::Exceptions::UnprocessableEntity] raised by Lighthouse::ServiceException
        # @param letter_type [String] the requested letter type
        # @return [Common::Exceptions::UnprocessableEntity]
        def enrich(error, letter_type:)
          details = upstream_details(error)
          reason = classify(details.join(' '))

          record(reason, letter_type)

          Common::Exceptions::UnprocessableEntity.new(errors: rebuilt_errors(error, reason))
        end

        # @param detail [String] the free-text reason Lighthouse returned
        # @return [String] one of REASONS
        def classify(detail)
          text = detail.to_s
          _, reason = PATTERNS.find { |pattern, _| pattern.match?(text) }

          reason || UNKNOWN
        end

        # @param reason [String] one of REASONS
        # @return [String] the veteran-facing copy for that reason
        def message_for(reason)
          I18n.t("lighthouse.letters_generator.download_failure.#{reason}")
        end

        private

        def upstream_details(error)
          Array(error.errors).filter_map do |e|
            e.is_a?(Hash) ? e[:detail] || e['detail'] : e.detail
          end
        end

        def record(reason, letter_type)
          StatsD.increment(STATSD_KEY, tags: tags_for(reason, letter_type))

          # Deliberately logs the classified reason and not the upstream free text. The generator
          # echoes submitted field values back in `detail` (its 400s quote the ICN), and
          # DataScrubber does not catch ICNs today — `ICN` is defined in its REGEX map but is
          # absent from PATTERN_ORDER, so scrub_string never applies it. The raw body is still
          # logged for this same request by Lighthouse::ServiceException, so nothing is lost for
          # debugging; this line just doesn't add a second copy of untrusted text.
          Rails.logger.warn(
            'Lighthouse letters generator rejected a letter download',
            reason:,
            letter_type: normalized_letter_type(letter_type)
          )
        end

        def tags_for(reason, letter_type)
          [
            "reason:#{reason}",
            "letter_type:#{normalized_letter_type(letter_type)}",
            "source_app:#{source_app}"
          ]
        end

        # Bounded by the callers: both download controllers reject anything outside the letter
        # type allowlist before reaching the service.
        def normalized_letter_type(letter_type)
          letter_type.to_s.downcase.presence || 'unknown'
        end

        # Mirrors VAProfile::Stats.source_app: validate against the middleware allowlist so a
        # spoofed Source-App-Name header can't blow up StatsD tag cardinality.
        def source_app
          raw = RequestStore.store.dig('additional_request_attributes', 'source')
          return UNKNOWN_SOURCE_APP if raw.blank?

          SourceAppMiddleware::SOURCE_APP_NAMES.include?(raw) ? raw : UNKNOWN_SOURCE_APP
        end

        # Keeps every field Lighthouse sent (title, status, code, type...) and swaps only the
        # veteran-facing detail, so clients reading the existing keys are unaffected.
        def rebuilt_errors(error, reason)
          errors = Array(error.errors).map do |e|
            base = e.is_a?(Hash) ? e.symbolize_keys : e.attributes.symbolize_keys.compact
            base.merge(detail: message_for(reason), reason:)
          end

          errors.presence || [{ title: 'Unprocessable Entity', status: '422', code: '422',
                                detail: message_for(reason), reason: }]
        end
      end
    end
  end
end
