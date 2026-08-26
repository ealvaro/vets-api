# frozen_string_literal: true

module BenefitsClaims
  module Providers
    module IvcChampva
      # Derives the CHAMPVA Status Tool's single application-level "last updated"
      # date (ticket #151986): the most recent of either a qualifying VES
      # eligibility statusUpdatedDate, or a qualifying user-facing CCL letter's
      # mailStatusDate, across every applicant on the application.
      #
      # Both sources are already gated against stale/prior-application activity
      # before this ever sees them, so no additional resubmission filtering is
      # needed here:
      #   - ChampvaEligibilityService#persist_eligibility withholds a stale prior-
      #     application VES determination until a post-submission letter confirms
      #     it applies to the current application -- applicant.ves_status_updated_date
      #     is only ever set once that gate passes.
      #   - ChampvaEligibilityService#persist_letter never persists a letter dated
      #     before the application's submission at all.
      # This module only needs to take the max of what's already there.
      #
      # Kept separate from ClaimBuilder for the same reason RepeatIneligibilityLetterActivity
      # is: that module isn't also responsible for this derivation's own logic.
      module LatestUpdateDate
        # @param applicants [Array<IvcChampvaApplicant>]
        # @return [String, nil] ISO8601 date of the most recent qualifying activity, or nil
        #   when no applicant has a qualifying eligibility date or CCL letter -- the frontend's
        #   documented no-date fallback applies in that case.
        def self.for(applicants)
          dates = (eligibility_dates(applicants) + letter_dates(applicants)).map(&:to_date)
          dates.max&.iso8601
        end

        # Every applicant's ves_status_updated_date is already gated (see module doc
        # above), so every non-nil value here already qualifies as current activity --
        # no additional "is this applicant decided" check is needed. Deliberately NOT
        # gated behind every applicant being resolved (unlike the claim-level
        # ves_status_updated_date field): this date means "most recent activity",
        # which one applicant's update already qualifies as, even while a sibling
        # applicant on the same application is still pending.
        #
        # @param applicants [Array<IvcChampvaApplicant>]
        # @return [Array<Date>]
        def self.eligibility_dates(applicants)
          applicants.filter_map(&:ves_status_updated_date)
        end

        # Only letters whose mail status counts as officially sent to the user (the
        # same allowlist RepeatIneligibilityLetterActivity uses) qualify as
        # user-facing mailed-letter activity -- reuses that module's own filtering
        # rather than a second copy of the same rule.
        #
        # @param applicants [Array<IvcChampvaApplicant>]
        # @return [Array<ActiveSupport::TimeWithZone>]
        def self.letter_dates(applicants)
          applicants.flat_map do |applicant|
            RepeatIneligibilityLetterActivity.sent_letters_for(applicant).map(&:mail_status_date)
          end
        end
      end
    end
  end
end
