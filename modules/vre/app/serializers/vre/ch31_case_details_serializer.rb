# frozen_string_literal: true

module VRE
  class Ch31CaseDetailsSerializer
    include JSONAPI::Serializer

    set_id { '' }

    attributes :res_case_id,
               :is_transferred_to_cwnrs,
               :orientation_appointment_details,
               :external_status,
               :case_manager,
               :is_initial_evaluation_step_code_of_conduct_completed,
               :has_veteran_opted_for_eva
  end
end
