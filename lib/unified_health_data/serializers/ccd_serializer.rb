# frozen_string_literal: true

module UnifiedHealthData
  module Serializers
    class CcdSerializer
      include JSONAPI::Serializer

      set_id :job_id
      set_type :ccd_status

      attributes :status,
                 :job_id,
                 :task_id,
                 :source,
                 :message,
                 :retry_after_seconds,
                 :authored_on,
                 :xml,
                 :html,
                 :pdf
    end
  end
end
