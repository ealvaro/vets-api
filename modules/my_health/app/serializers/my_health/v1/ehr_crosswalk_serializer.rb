# frozen_string_literal: true

module MyHealth
  module V1
    class EhrCrosswalkSerializer
      include JSONAPI::Serializer

      set_type :ehr_crosswalk_entries
      set_id :vista_triage_group_id

      attributes :vista_triage_group_id,
                 :vista_triage_group_name,
                 :oh_triage_group_id,
                 :oh_triage_group_name
    end
  end
end
