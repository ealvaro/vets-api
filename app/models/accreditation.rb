# frozen_string_literal: true

class Accreditation < ApplicationRecord
  # Acts as the join between AccreditedIndividual and AccreditedOrganization and is meant to store information that
  # lives at the grain between the two models. For example, can_accept_reject_poa is a permission that needs to be
  # set for each organization a representative is accredited with.
  #
  # @note for can_accept_reject_poa that a slight change
  # to implementation might be needed to support attorneys and claims agents since they do not have organization
  # accreditations.

  belongs_to :accredited_individual
  belongs_to :accredited_organization

  validates :accredited_organization_id, uniqueness: { scope: :accredited_individual_id }

  enum :acceptance_mode, {
    any_request: 'any_request',
    self_only: 'self_only',
    no_acceptance: 'no_acceptance'
  }, default: 'no_acceptance', validate: true

  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  scope :for_organization_poa_codes, lambda { |poa_codes|
    joins(:accredited_organization).where(accredited_organizations: { poa_code: poa_codes })
  }
  scope :for_registration_numbers, lambda { |registration_numbers|
    joins(:accredited_individual).where(accredited_individuals: { registration_number: registration_numbers })
  }

  def activate!
    return true if deactivated_at.nil?

    update!(deactivated_at: nil)
  end

  def deactivate!
    update!(deactivated_at: Time.current)
  end

  def self.deactivate!(ids)
    ids = Array(ids).compact
    return 0 if ids.empty?

    now = Time.current
    count = 0

    where(id: ids).find_each do |record|
      record.update!(deactivated_at: now)
      count += 1
    end

    count
  end
end
