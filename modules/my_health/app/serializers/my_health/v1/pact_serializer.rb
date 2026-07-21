# frozen_string_literal: true

module MyHealth
  module V1
    class PactSerializer
      include JSONAPI::Serializer

      set_type :pact_teams
      set_id { '' }

      attribute :station_number do |object|
        object[:station_number]
      end

      attribute :provider_ien do |object|
        object[:provider_ien]
      end

      attribute :provider_name do |object|
        object[:provider_name]
      end

      attribute :assignment_status do |object|
        object[:assignment_status]
      end

      attribute :team_name do |object|
        object[:team_name]
      end

      attribute :summary_text do |object|
        object[:summary_text]
      end
    end
  end
end
