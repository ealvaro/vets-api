# frozen_string_literal: true

require 'common/models/resource'

module Mobile
  module V0
    class Letter < Common::Resource
      LETTER_TYPE = Types::String.enum(
        'benefit_summary',
        'benefit_summary_dependent',
        'benefit_verification',
        'certificate_of_eligibility',
        'certificate_of_eligibility_home_loan',
        'civil_service',
        'commissary',
        'foreign_medical_program',
        'medicare_partd',
        'minimum_essential_coverage',
        'proof_of_service',
        'service_verification'
      )

      VISIBLE_TYPES = %w[
        benefit_summary
        benefit_verification
        certificate_of_eligibility_home_loan
        civil_service
        commissary
        foreign_medical_program
        medicare_partd
        minimum_essential_coverage
        proof_of_service
        service_verification
      ].freeze

      # Minimum mobile app version that receives the updated letters content. Below this version,
      # both the letters API payload and the cstLettersContentUpdates authorized service fall back
      # to legacy content.
      CONTENT_UPDATES_APP_VERSION = '2.78.0'

      # Minimum mobile app version that can render the typed `content` array description format.
      # Below this version, letter descriptions fall back to the legacy `paragraphs/lists` shape
      # (descriptions_legacy.yml) and the medicare_partd → minimum_essential_coverage consolidation
      # (plus the CONSOLIDATED_COVERAGE_NAME name override) are suppressed.
      DESCRIPTION_CONTENT_FORMAT_APP_VERSION = '2.80.0'

      attribute :name, Types::String
      attribute :letter_type, LETTER_TYPE
      attribute :description, Types::Hash.optional.default(nil)
      attribute :reference_number, Types::String.optional.default(nil) # only for COE home loan letters
      attribute :coe_status, Types::String.optional.default(nil) # only for COE home loan letters

      def displayable?(user = nil)
        return false unless self.class::VISIBLE_TYPES.include?(letter_type)

        # Hide foreign_medical_program behind mobile-specific user feature flag
        if letter_type == 'foreign_medical_program'
          return Flipper.enabled?(:fmp_benefits_authorization_letter_mobile) if user.nil?

          return Flipper.enabled?(:fmp_benefits_authorization_letter_mobile, user)
        end

        true
      end
    end
  end
end
