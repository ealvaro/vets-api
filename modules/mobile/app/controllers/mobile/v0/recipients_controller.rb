# frozen_string_literal: true

module Mobile
  module V0
    class RecipientsController < MessagingController
      def recipients
        resource = client.get_triage_teams(@current_user.uuid, use_cache?)
        raise Common::Exceptions::ResourceNotFound if resource.blank?

        resource = resource.sort(params[:sort])

        # Even though this is a collection action we are not going to paginate
        options = { meta: resource.metadata }
        render json: TriageTeamSerializer.new(resource.data, options)
      end

      def all_recipients
        filter_vtgs = !Flipper.enabled?(:mhv_secure_messaging_show_vtgs_mobile, @current_user)
        resource = client.get_all_triage_teams(@current_user.uuid, filter_virtual_groups: filter_vtgs) do |resp|
          SchemaContract::ValidationInitiator.call(
            user: @current_user, response: resp, contract_name: 'triage_teams'
          )
        end
        raise Common::Exceptions::ResourceNotFound if resource.blank?

        resource.records = resource.records.reject(&:blocked_status)
        resource.records = resource.records.select(&:preferred_team)
        resource = resource.sort(params[:sort])

        resource.metadata[:care_systems] = get_unique_care_systems(resource.records)

        # Even though this is a collection action we are not going to paginate
        options = { meta: resource.metadata }
        render json: AllTriageTeamsSerializer.new(resource.data, options)
      end

      def crosswalk
        entries = client.get_crosswalk
        resource = entries.map { |entry| OpenStruct.new(entry) }
        render json: MyHealth::V1::EhrCrosswalkSerializer.new(resource)
      end

      private

      def get_unique_care_systems(all_recipients)
        all_recipients
          .uniq(&:station_number)
          .map do |team|
            {
              station_number: team.station_number,
              health_care_system_name: team.health_care_system_name || team.station_number
            }
          end
      end
    end
  end
end
