# frozen_string_literal: true

module VRE
  module Ch31CaseDetails
    class CaseManager
      include Vets::Model

      attribute :first_name, String
      attribute :last_name, String
      attribute :email, String
      attribute :phone, String
    end
  end
end
