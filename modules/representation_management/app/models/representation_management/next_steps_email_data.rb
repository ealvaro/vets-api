# frozen_string_literal: true

module RepresentationManagement
  class NextStepsEmailData
    include ActiveModel::Model

    VALID_FORM_NUMBERS = %w[21-22 21-22A].freeze
    VALID_ENTITY_TYPES = %w[individual organization].freeze

    attr_accessor :email_address, :first_name, :form_name, :form_number, :entity_type, :entity_id

    validates :email_address, presence: true,
                              format: { with: URI::MailTo::EMAIL_REGEXP },
                              length: { maximum: 254 }
    validates :first_name, presence: true, length: { maximum: 100 },
                           format: { with: /\A[^\r\n\x00]*\z/ }
    validates :form_name, presence: true, length: { maximum: 200 },
                          format: { with: /\A[^\r\n\x00]*\z/ }
    validates :form_number, presence: true, inclusion: { in: VALID_FORM_NUMBERS }
    validates :entity_type, presence: true, inclusion: { in: VALID_ENTITY_TYPES }
    validates :entity_id, presence: true, length: { maximum: 36 }
    validate :entity_exists?

    def entity
      return @entity if defined?(@entity)

      @entity = find_entity
    end

    def entity_display_type
      return '' unless entity

      if entity.is_a?(Veteran::Service::Representative) || entity.is_a?(AccreditedIndividual)
        representative_type
      else
        'Veterans Service Organization'
      end
    end

    def entity_name
      return '' unless entity

      if entity_type == 'individual'
        entity.full_name&.strip.to_s
      elsif entity_type == 'organization'
        entity.name&.strip.to_s
      else
        ''
      end
    end

    def entity_address
      return '' unless entity

      <<~ADDRESS.squish
        #{entity.address_line1}
        #{entity.address_line2}
        #{entity.address_line3}
        #{entity.city}, #{entity.state_code} #{entity.zip_code}
        #{entity.country_code_iso3}
      ADDRESS
    end

    private

    def find_entity
      if entity_type == 'individual'
        find_representative
      elsif entity_type == 'organization'
        find_organization
      end
    end

    def entity_exists?
      return if entity_type.blank? || entity_id.blank? || VALID_ENTITY_TYPES.exclude?(entity_type)

      errors.add(:base, 'The specified entity could not be found') if entity.nil?
    end

    def find_representative
      AccreditedIndividual.find_by(registration_number: entity_id) ||
        Veteran::Service::Representative.find_by(representative_id: entity_id)
    end

    def find_organization
      AccreditedOrganization.find_by(id: entity_id) ||
        Veteran::Service::Organization.find_by(poa: entity_id)
    end

    def representative_type
      type_string = entity.is_a?(Veteran::Service::Representative) ? entity.user_types.first : entity.individual_type
      case type_string
      when 'claims_agent', 'claim_agents' then 'claims agent'
      when 'representative', 'veteran_service_officer' then 'VSO representative'
      when 'attorney' then 'attorney'
      else ''
      end
    end
  end
end
