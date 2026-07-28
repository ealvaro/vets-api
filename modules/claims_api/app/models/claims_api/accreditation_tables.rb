# frozen_string_literal: true

module ClaimsApi
  module AccreditationTables
    FLAG = :claims_api_use_claims_accreditation_tables

    module_function

    def representative
      # return ::ClaimsApi::Representative if use_claims_accreditation_tables?

      ::Veteran::Service::Representative
    end

    def organization
      # return ::ClaimsApi::Organization if use_claims_accreditation_tables?

      ::Veteran::Service::Organization
    end

    def use_claims_accreditation_tables?
      Flipper.enabled?(FLAG)
    end
  end
end
