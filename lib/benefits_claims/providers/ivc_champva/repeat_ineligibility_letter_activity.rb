# frozen_string_literal: true

require 'benefits_claims/claim_status_meta/config_loader'

module BenefitsClaims
  module Providers
    module IvcChampva
      # Derives whether a not-enrolled (ineligible) CHAMPVA applicant has received an
      # additional user-facing CCL letter beyond their initial determination letter,
      # so the FE can show updated "still ineligible" content without tracking letter
      # history itself. Kept separate from ClaimBuilder so that module isn't also
      # responsible for sent-letter-status config parsing.
      module RepeatIneligibilityLetterActivity
        SENT_LETTER_STATUSES_PATH =
          Rails.root.join('config', 'benefits_claims', 'ves_sent_letter_statuses.json').freeze

        SENT_LETTER_STATUSES = begin
          JSON.parse(File.read(SENT_LETTER_STATUSES_PATH))
              .fetch('statuses', [])
              .to_set { |status| status.to_s.downcase.strip }
              .freeze
        rescue => e
          Rails.logger.error(
            '[BenefitsClaims::Providers::IvcChampva::RepeatIneligibilityLetterActivity] ' \
            'Failed to load VES sent letter statuses',
            { message: e.message }
          )
          Set.new.freeze
        end

        # @param applicant [IvcChampvaApplicant]
        # @return [Hash] 'hasRepeatIneligibilityLetter' (Boolean) and 'repeatIneligibilityLetterDate'
        #   (String, nil) for merging into the applicant response hash. Does not include the alert —
        #   see .alert_for, which needs every affected applicant on the application, not just this one.
        def self.evaluate(applicant)
          sent_letters = sent_letters_for(applicant)
          has_activity = repeat_activity?(applicant, sent_letters)

          {
            'hasRepeatIneligibilityLetter' => has_activity,
            'repeatIneligibilityLetterDate' => has_activity ? format_datetime(sent_letters.last.mail_status_date) : nil
          }
        end

        # Shared alert copy (title/description) for the FE to render as-is, built from the
        # claim_status_meta config's repeatIneligibilityAlert template with '[Name]' substituted —
        # the same substitution convention VesReasonTranslator uses for vesEligibilityReason. Takes
        # every applicant on the application who has repeat letter activity (not just one) and joins
        # their first names into a single '[Name]' substitution (e.g. "Jane and John",
        # "Jane, John, and Sam"), since the alert speaks to the application's decision as a whole, not
        # to a single applicant's card.
        #
        # @param applicants_with_activity [Array<IvcChampvaApplicant>] applicants with
        #   hasRepeatIneligibilityLetter == true, in the order they should be listed
        # @return [Hash, nil] 'title' (String), 'description' (String); nil when the list is empty
        #   or when the config template failed to load — never a hash of blank strings, which
        #   would slip past a caller's `.blank?`/`.present?` check and surface as an empty alert.
        def self.alert_for(applicants_with_activity)
          return nil if applicants_with_activity.blank?

          template = alert_template
          return nil if template.blank?

          # Not deduped by name: applicants_with_activity is already a distinct list of flagged
          # applicant records, so two different people who happen to share a first name (e.g. a
          # parent and child both named "Jane") must both be named here, even though that reads
          # as "Jane and Jane" — deduping by the string would silently drop one of them from an
          # alert whose entire purpose is to name every affected applicant.
          name_list = applicants_with_activity.filter_map { |applicant| applicant.applicant_first_name.presence }
                                              .to_sentence
                                              .presence || 'This applicant'

          {
            'title' => template['title'].to_s.gsub('[Name]', name_list),
            'description' => template['description'].to_s.gsub('[Name]', name_list)
          }
        end

        # Own ConfigLoader variant (repeat_ineligibility_alert.json), not part of default.json —
        # keeps this template out of claimStatusMeta entirely, rather than loading the whole
        # claim_status_meta config and having to strip it back out before exposing claimStatusMeta.
        def self.alert_template
          BenefitsClaims::ClaimStatusMeta::ConfigLoader.load(provider: :ivc_champva,
                                                             variant: 'repeat_ineligibility_alert')
        rescue ArgumentError => e
          Rails.logger.error(
            '[BenefitsClaims::Providers::IvcChampva::RepeatIneligibilityLetterActivity] ' \
            'Failed to load repeat ineligibility alert config',
            { message: e.message }
          )
          {}
        end

        # True only once a not-enrolled applicant has received a second (or later)
        # officially-sent letter — a single sent letter is just their initial
        # determination notice, not repeat activity. Enrolled applicants, unresolved
        # applicants, and applicants with missing/incomplete letter data all safely
        # fall back to false (the standard decision state).
        #
        # @param applicant [IvcChampvaApplicant]
        # @param sent_letters [Array<IvcChampvaLetter>] pre-computed via sent_letters_for
        # @return [Boolean]
        def self.repeat_activity?(applicant, sent_letters)
          return false if applicant.eligible?
          return false unless applicant.eligibility_resolved

          sent_letters.size > 1
        end

        # Letters whose mail status counts as officially sent to the user, per the
        # configured allowlist (see ves_sent_letter_statuses.json), oldest first.
        # Letters that predate the application's submission are never persisted in
        # the first place, so no additional submission-date filtering is needed here.
        #
        # @param applicant [IvcChampvaApplicant]
        # @return [Array<IvcChampvaLetter>]
        def self.sent_letters_for(applicant)
          applicant.ivc_champva_letters
                   .select { |letter| SENT_LETTER_STATUSES.include?(letter.mail_status.to_s.downcase.strip) }
                   .sort_by(&:mail_status_date)
        end

        # @param value [ActiveSupport::TimeWithZone, nil]
        # @return [String, nil]
        def self.format_datetime(value)
          value&.iso8601
        end
      end
    end
  end
end
