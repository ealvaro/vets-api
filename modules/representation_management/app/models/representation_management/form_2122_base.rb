# frozen_string_literal: true

module RepresentationManagement
  class Form2122Base
    include ActiveModel::Model
    include ActiveModel::Validations::Callbacks

    VALIDATION_ERROR_FORM_ID = '21-22'

    NINE_DIGIT_NUMBER = /\A\d{9}\z/
    TEN_DIGIT_NUMBER = /\A\d{10}\z/
    SERVICE_NUMBER = /\A[A-Z]{0,2}\d{5,8}\z/
    LIMITATIONS_OF_CONSENT = %w[ALCOHOLISM DRUG_ABUSE HIV SICKLE_CELL].freeze

    veteran_attrs = %i[
      veteran_first_name veteran_middle_initial veteran_last_name
      veteran_social_security_number
      veteran_va_file_number
      veteran_date_of_birth
      veteran_address_line1
      veteran_address_line2
      veteran_city
      veteran_country
      veteran_state_code
      veteran_zip_code
      veteran_zip_code_suffix
      veteran_phone
      veteran_email
      veteran_service_number
    ]

    claimant_attrs = %i[
      claimant_first_name
      claimant_middle_initial
      claimant_last_name
      claimant_date_of_birth
      claimant_relationship
      claimant_address_line1
      claimant_address_line2
      claimant_city
      claimant_country
      claimant_state_code
      claimant_zip_code
      claimant_zip_code_suffix
      claimant_phone
      claimant_email
    ]

    representative_attrs = %i[
      representative_id
    ]

    consent_attrs = %i[
      record_consent
      consent_address_change
      consent_limits
    ]

    attr_accessor(*[veteran_attrs, claimant_attrs, representative_attrs, consent_attrs].flatten)

    after_validation :log_validation_errors, if: -> { Flipper.enabled?(:form2122_validation_error_logging) }

    validates :veteran_first_name, presence: true, length: { maximum: 12 }
    validates :veteran_middle_initial, length: { maximum: 1 }
    validates :veteran_last_name, presence: true, length: { maximum: 18 }
    validates :veteran_social_security_number, presence: true, format: { with: NINE_DIGIT_NUMBER }
    validates :veteran_va_file_number,
              length: { is: 9 },
              format: { with: NINE_DIGIT_NUMBER },
              if: -> { veteran_va_file_number.present? }
    validates :veteran_date_of_birth, presence: true
    validates :veteran_address_line1, presence: true, length: { maximum: 30 }
    validates :veteran_address_line2, length: { maximum: 5 }, if: -> { veteran_address_line2.present? }
    validates :veteran_city, presence: true, length: { maximum: 18 }
    validates :veteran_country, presence: true, length: { is: 2 }
    # LH request should contain 'NA' if international and no state code is provided (client should do this)
    validates :veteran_state_code, presence: true, length: { minimum: 2 }

    # Zip code is only required for USA-based addresses (per VaProfile)
    with_options if: -> { veteran_address_usa_based? } do
      validates :veteran_zip_code, presence: true, length: { minimum: 4 }
    end

    validates :veteran_phone, length: { is: 10 }, format: { with: TEN_DIGIT_NUMBER }, if: -> { veteran_phone.present? }
    validates :veteran_service_number,
              format: { with: SERVICE_NUMBER },
              if: -> { veteran_service_number.present? }

    validate :consent_limits_must_contain_valid_values
    validate :representative_exists?, if: -> { representative_id.present? }

    with_options if: -> { claimant_first_name.present? } do
      validates :claimant_first_name, presence: true, length: { maximum: 12 }
      validates :claimant_middle_initial, length: { maximum: 1 }
      validates :claimant_last_name, presence: true, length: { maximum: 18 }
      validates :claimant_date_of_birth, presence: true
      validates :claimant_relationship, presence: true
      validates :claimant_address_line1, presence: true, length: { maximum: 30 }
      validates :claimant_address_line2, length: { maximum: 5 }
      validates :claimant_city, presence: true, length: { maximum: 18 }
      validates :claimant_country, presence: true, length: { is: 2 }
      # LH request should contain 'NA' if international and no state code is provided (client should do this)
      validates :claimant_state_code, presence: true, length: { minimum: 2 }

      validates :claimant_phone, length: { is: 10 }, format: { with: TEN_DIGIT_NUMBER }
    end

    # Zip code is only required for USA-based addresses (per VaProfile)
    with_options if: -> { claimant_address_usa_based? } do
      validates :claimant_zip_code, presence: true, length: { minimum: 4 }
    end

    def representative
      @representative ||= find_representative
    end

    def representative_individual_type
      type = if representative.is_a?(AccreditedIndividual)
               representative.individual_type
             else
               representative.user_types.first
             end
      # We're converting 'claims_agent' and 'claim_agents' to 'agent'
      # here because the PDF checkbox responds to 'agent'.
      %w[claims_agent claim_agents].include?(type) ? 'agent' : type
    end

    def representative_phone
      if representative.is_a?(AccreditedIndividual)
        representative.phone
      else
        representative.phone_number
      end
    end

    def veteran_state_code_truncated
      veteran_state_code.to_s[0..1]
    end

    def claimant_state_code_truncated
      claimant_state_code.to_s[0..1]
    end

    def veteran_zip_code_expanded
      expand_zip_code(veteran_zip_code, veteran_zip_code_suffix)
    end

    def claimant_zip_code_expanded
      expand_zip_code(claimant_zip_code, claimant_zip_code_suffix)
    end

    def veteran_address_usa_based?
      usa_country_code?(veteran_country)
    end

    def claimant_address_usa_based?
      usa_country_code?(claimant_country)
    end

    private

    def usa_country_code?(country_code)
      # We should be dealing with alpha2 country codes here, but just in case, check for alpha3 as well.
      %w[US USA].include?(country_code)
    end

    def expand_zip_code(zip_code, zip_code_suffix)
      zip_code = zip_code.to_s
      zip_code_suffix = zip_code_suffix.to_s

      if zip_code_suffix.blank?
        [zip_code[0..4].to_s, zip_code[5..8].to_s]
      else
        [zip_code[0..4].to_s, zip_code_suffix[0..3].to_s]
      end
    end

    def consent_limits_must_contain_valid_values
      return if consent_limits.blank? || (consent_limits.size == 1 && consent_limits.first.blank?)

      consent_limits.each do |limit|
        unless LIMITATIONS_OF_CONSENT.include?(limit)
          errors.add(:consent_limits,
                     "#{limit} is not a valid limitation of consent")
        end
      end
    end

    def find_representative
      if appoint_accredited_models_enabled?
        AccreditedIndividual.find_by(id: representative_id)
      else
        Veteran::Service::Representative.find_by(representative_id:)
      end
    end

    # Gates the Appoint a Rep migration: when on, resolve/accept against the AccreditedX models;
    # when off (default), against the legacy Veteran::Service models.
    def appoint_accredited_models_enabled?
      Flipper.enabled?(:arc_appoint_a_representative_use_accredited_models)
    end

    def representative_exists?
      return unless representative.nil?

      errors.add(:representative_id, 'Representative not found')
    end

    def log_validation_errors
      return if errors.blank?

      monitor.track_validation_errors(
        message: validation_error_message,
        errors: errors.messages,
        form_id: validation_error_form_id
      )
    end

    # Default validation log message for subclasses that do not provide a
    # more specific message for their submission flow.
    def validation_error_message
      'Representation management base form validation failed'
    end

    def validation_error_form_id
      self.class::VALIDATION_ERROR_FORM_ID
    end

    def monitor
      @monitor ||= RepresentationManagement::Monitor.new
    end
  end
end
