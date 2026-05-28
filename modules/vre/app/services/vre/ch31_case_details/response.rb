# frozen_string_literal: true

module VRE
  module Ch31CaseDetails
    class Response
      include Vets::Model

      attribute :res_case_id, Integer
      attribute :is_transferred_to_cwnrs, Bool
      attribute :orientation_appointment_details, OrientationAppointmentDetails
      attribute :external_status, ExternalStatus
      attribute :case_manager, CaseManager
      attribute :is_initial_evaluation_step_code_of_conduct_completed, Bool
      attribute :has_veteran_opted_for_eva, Bool

      def initialize(_status, response = nil)
        super(response.body) if response
      end
    end
  end
end
