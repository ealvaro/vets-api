# frozen_string_literal: true

module MyHealth
  module V1
    class ActivitySerializer
      include JSONAPI::Serializer

      set_id :id
      set_type :activities

      attribute :action
      attribute :status
      attribute :performer_type
      attribute :activity_type
      attribute :detail_value
      attribute :completion_time
    end
  end
end
