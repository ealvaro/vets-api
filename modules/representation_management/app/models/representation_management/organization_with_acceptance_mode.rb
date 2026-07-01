# frozen_string_literal: true

module RepresentationManagement
  # Wraps an organization an individual is accredited with, tagging it with the
  # acceptance_mode for that (individual, organization) pair sourced from the active
  # Accreditation join. Defaults to no_acceptance when no active Accreditation row exists.
  class OrganizationWithAcceptanceMode < SimpleDelegator
    DEFAULT_ACCEPTANCE_MODE = 'no_acceptance'

    def initialize(organization, acceptance_mode:)
      super(organization)
      @acceptance_mode = acceptance_mode
    end

    def acceptance_mode
      @acceptance_mode || DEFAULT_ACCEPTANCE_MODE
    end

    # Builds an acceptance_mode lookup for a whole collection of individuals in a single
    # query, so serializing a page of results doesn't trigger a per-individual query (N+1).
    # poa_code is identical on the legacy and AccreditedX sides.
    #
    # @return [Hash] { registration_number => { poa_code => acceptance_mode } }
    def self.acceptance_modes_for(individuals)
      registration_numbers = Array(individuals).map(&:registration_number).compact.uniq
      return {} if registration_numbers.empty?

      Accreditation.active
                   .for_registration_numbers(registration_numbers)
                   .joins(:accredited_organization)
                   .pluck(
                     'accredited_individuals.registration_number',
                     'accredited_organizations.poa_code',
                     :acceptance_mode
                   )
                   .each_with_object({}) do |(registration_number, poa_code, acceptance_mode), modes|
                     (modes[registration_number] ||= {})[poa_code] = acceptance_mode
                   end
    end
  end
end
