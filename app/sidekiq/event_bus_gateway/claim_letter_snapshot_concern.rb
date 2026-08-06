# frozen_string_literal: true

require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require_relative 'gated_claim_letters_provider'
require_relative 'constants'

module EventBusGateway
  # Shared claim-letter helpers for the letter-ready jobs that inspect Benefits
  # Documents: building a user from an ICN, resolving the provider, and snapshotting
  # the decision-letter (doc-type 184) set. Kept separate from LetterReadyJobConcern
  # (MPI/BGS lookups) so each stays cohesive.
  module ClaimLetterSnapshotConcern
    extend ActiveSupport::Concern

    private

    # Builds a minimal LOA3 user from the ICN so the claim letters providers can
    # resolve participant_id/file_number via MPI, mirroring a real page request.
    # Uses the UserAccount UUID when available so provider log lines correlate
    # back to the veteran; falls back to a random UUID when there's no account.
    def build_user_from_icn(icn, uuid: nil)
      uuid = SecureRandom.uuid if uuid.blank?
      user_identity = UserIdentity.new(
        icn:,
        uuid:,
        loa: { current: 3, highest: 3 }
      )
      user = User.new(uuid: user_identity.uuid)
      user.instance_variable_set(:@identity, user_identity)
      user
    end

    # Always uses the Lighthouse Benefits Documents provider (the strategic
    # claim-letters source) regardless of the VBMS migration flag, via the gated
    # subclass so the BD availability check is bounded by a tight Faraday read
    # timeout (see GatedClaimLettersConfiguration) — the gate runs in Sidekiq and
    # must never hold a worker on a slow BD call.
    def claim_letters_service(user)
      GatedClaimLettersProvider.new(user)
    end

    # Compact snapshot of the decision-letter (doc-type 184) set for a user.
    # Used both to log the send-time state and to compare against a later re-check.
    def decision_letter_snapshot(letters)
      letters ||= []
      decision_letters = letters.select { |d| d[:doc_type] == Constants::DECISION_LETTER_DOC_TYPE }
      most_recent_decision = most_recent_letter(decision_letters)

      {
        letter_count: letters.size,
        decision_letter_count: decision_letters.size,
        # Full id set, so the re-check can detect any new letter by set difference.
        decision_letter_document_ids: decision_letters.filter_map { |d| d[:document_id] },
        most_recent_decision_received_at: format_letter_date(most_recent_decision&.dig(:received_at)),
        most_recent_decision_document_id: most_recent_decision&.dig(:document_id)
      }
    end

    # Returns the letter with the newest received_at. Computes the max rather than
    # trusting provider sort order; falls back to the first letter if none are dated.
    def most_recent_letter(letters)
      return nil if letters.blank?

      dated = letters.select { |d| d[:received_at].present? }
      return letters.first if dated.empty?

      dated.max_by { |d| d[:received_at].to_datetime }
    end

    def format_letter_date(value)
      return nil if value.blank?

      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end

    # True when any decision letter (doc-type 184) is stamped within the recency
    # window. Used at send time to decide whether we're in a "miss" case worth
    # re-checking, and at re-check time as the recency "available" signal.
    def recent_decision_letter?(letters)
      cutoff = Time.current - Constants::CLAIM_LETTER_RECENCY_WINDOW
      Array(letters).any? do |letter|
        letter[:doc_type] == Constants::DECISION_LETTER_DOC_TYPE &&
          letter[:received_at].present? &&
          letter[:received_at].to_datetime >= cutoff
      end
    end

    # A decision letter has "appeared" when the decision-letter set changed since
    # the send-time snapshot — any document id present now that wasn't at send
    # time. Keys off the changing set rather than past-vs-future of a single
    # received_at, which is an unreliable wall-clock signal. Falls back to a rise
    # in count when ids are unavailable, and to plain presence when no snapshot was
    # carried. `current` uses symbol keys (from decision_letter_snapshot);
    # `snapshot` uses string keys (round-tripped through the Sidekiq queue).
    def new_decision_letter?(current, snapshot)
      return current[:decision_letter_count].positive? if snapshot.blank?

      prior_ids = Array(snapshot['decision_letter_document_ids'])
      current_ids = Array(current[:decision_letter_document_ids])
      return true if (current_ids - prior_ids).any?

      current[:decision_letter_count] > snapshot['decision_letter_count'].to_i
    end

    # Unified "is a decision letter available to justify sending now?" check.
    # First attempt (no prior snapshot): fall back to the recency signal — is any
    # decision letter recent enough to treat as present. Re-checks (prior snapshot
    # carried): use the trusted delta — did a new decision letter appear vs. the
    # send-time snapshot.
    def decision_letter_available?(letters, prior_snapshot)
      if prior_snapshot.present?
        new_decision_letter?(decision_letter_snapshot(letters), prior_snapshot)
      else
        recent_decision_letter?(letters)
      end
    end

    # Whole seconds elapsed since an ISO-8601 timestamp; nil if unparseable.
    def seconds_since(iso)
      return nil if iso.blank?

      (Time.current - Time.zone.parse(iso.to_s)).to_i
    rescue ArgumentError, TypeError
      nil
    end
  end
end
