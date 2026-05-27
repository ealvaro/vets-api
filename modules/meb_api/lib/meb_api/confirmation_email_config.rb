# frozen_string_literal: true

module MebApi
  # Configuration and constants for MEB confirmation emails
  module ConfirmationEmailConfig
    # Form type identifiers
    FORM_1990MEB = '1990MEB'
    FORM_1990EMEB = '1990EMEB'
    FORM_10297 = '10297'
    FORM_225490 = '225490'
    FORM_1990_CHAPTER1606 = '1990_CHAPTER1606'
    FORM_1990_CHAPTER30 = '1990_CHAPTER30'

    # StatsD metric tags
    TAG_1990MEB = 'form:1990meb'
    TAG_1990EMEB = 'form:1990emeb'
    TAG_10297 = 'form:10297'
    TAG_225490 = 'form:225490'
    TAG_1990_CHAPTER1606 = 'form:1990_chapter1606'
    TAG_1990_CHAPTER30 = 'form:1990_chapter30'

    # Normalized claim statuses for metrics (prevent unbounded cardinality)
    # These are the actual claim statuses returned by DGI backend
    VALID_CLAIM_STATUSES = %w[ELIGIBLE DENIED INPROGRESS ERROR].freeze

    # Default fallback key per form type (used when status is not ELIGIBLE or DENIED)
    DEFAULT_FALLBACK = {
      FORM_1990MEB => 'OFFRAMP',
      FORM_1990EMEB => 'OFFRAMP',
      FORM_10297 => 'UNDER_REVIEW',
      FORM_225490 => 'OFFRAMP',
      FORM_1990_CHAPTER1606 => 'OFFRAMP',
      FORM_1990_CHAPTER30 => 'OFFRAMP'
    }.freeze

    # Template ID mappings by form type and status
    TEMPLATE_MAPPINGS = {
      FORM_1990MEB => {
        'ELIGIBLE' => :form1990meb_approved_confirmation_email,
        'DENIED' => :form1990meb_denied_confirmation_email,
        'OFFRAMP' => :form1990meb_offramp_confirmation_email
      },
      FORM_1990EMEB => {
        'ELIGIBLE' => :form1990emeb_approved_confirmation_email,
        'DENIED' => :form1990emeb_denied_confirmation_email,
        'OFFRAMP' => :form1990emeb_offramp_confirmation_email
      },
      FORM_10297 => {
        'ELIGIBLE' => :form10297_approved_confirmation_email,
        'DENIED' => :form10297_denied_confirmation_email,
        'UNDER_REVIEW' => :form10297_under_review_confirmation_email
      },
      FORM_225490 => {
        'ELIGIBLE' => :form225490_approved_confirmation_email,
        'OFFRAMP' => :form225490_offramp_confirmation_email
      },
      FORM_1990_CHAPTER1606 => {
        'ELIGIBLE' => :form1990_chapter1606_approved_confirmation_email,
        'OFFRAMP' => :form1990_chapter1606_offramp_confirmation_email
      },
      FORM_1990_CHAPTER30 => {
        'ELIGIBLE' => :form1990_chapter30_approved_confirmation_email,
        'OFFRAMP' => :form1990_chapter30_offramp_confirmation_email
      }
    }.freeze

    class << self
      # Normalize claim status to prevent unbounded metric cardinality
      # Maps frontend statuses to backend DGI statuses
      # @param status [String, Symbol] Raw claim status from frontend
      # @return [String] Normalized status (ELIGIBLE, DENIED, INPROGRESS, ERROR, or OTHER)
      def normalize_claim_status(status)
        normalized = status.to_s.upcase
        # Map frontend 'IN_PROGRESS' to backend 'INPROGRESS'
        normalized = 'INPROGRESS' if normalized == 'IN_PROGRESS'
        VALID_CLAIM_STATUSES.include?(normalized) ? normalized : 'OTHER'
      end

      # Get template ID for a confirmation email
      # @param form_type [String] '1990MEB', '1990EMEB', or '10297'
      # @param claim_status [String] Status of the claim
      # @return [String] VANotify template ID
      def template_id(form_type:, claim_status:)
        fallback_key = DEFAULT_FALLBACK.fetch(form_type, 'OFFRAMP')

        status_key = case claim_status.to_s.upcase
                     when 'ELIGIBLE', 'DENIED' then claim_status.to_s.upcase
                     else fallback_key
                     end

        template_key = TEMPLATE_MAPPINGS.dig(form_type, status_key) ||
                       TEMPLATE_MAPPINGS.dig(form_type, fallback_key)

        Settings.vanotify.services.va_gov.template_id.public_send(template_key)
      end
    end
  end
end
