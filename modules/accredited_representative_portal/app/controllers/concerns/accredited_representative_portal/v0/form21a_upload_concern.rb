# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    module Form21aUploadConcern
      extend ActiveSupport::Concern

      DOCUMENT_KEYS = {
        'conviction-details' => 'convictionDetailsDocuments',
        'court-martialed-details' => 'courtMartialedDetailsDocuments',
        'under-charges-details' => 'underChargesDetailsDocuments',
        'resigned-from-education-details' => 'resignedFromEducationDetailsDocuments',
        'withdrawn-from-education-details' => 'withdrawnFromEducationDetailsDocuments',
        'disciplined-for-dishonesty-details' => 'disciplinedForDishonestyDetailsDocuments',
        'resigned-for-dishonesty-details' => 'resignedForDishonestyDetailsDocuments',
        'representative-for-agency-details' => 'representativeForAgencyDetailsDocuments',
        'reprimanded-in-agency-details' => 'reprimandedInAgencyDetailsDocuments',
        'resigned-from-agency-details' => 'resignedFromAgencyDetailsDocuments',
        'applied-for-va-accreditation-details' => 'appliedForVaAccreditationDetailsDocuments',
        'terminated-by-vsorg-details' => 'terminatedByVsorgDetailsDocuments',
        'condition-that-affects-representation-details' => 'conditionThatAffectsRepresentationDetailsDocuments'
      }.freeze

      def documents_key_for(slug)
        DOCUMENT_KEYS.fetch(slug) do
          raise ArgumentError, "Unknown details slug: #{slug}"
        end
      end
    end
  end
end
