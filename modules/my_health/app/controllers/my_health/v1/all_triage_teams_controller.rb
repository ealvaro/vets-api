# frozen_string_literal: true

module MyHealth
  module V1
    class AllTriageTeamsController < SMController
      STATSD_KEY_PREFIX = 'api.my_health.all_triage_teams'

      def index
        filter_non_pretransitioned = !Flipper.enabled?(:mhv_secure_messaging_show_vtgs_web, @current_user)
        filter_pretransitioned = Flipper.enabled?(:mhv_secure_messaging_hide_pretransitioned_vtgs, @current_user)
        resource = client.get_all_triage_teams(@current_user.uuid,
                                               filter_non_pretransitioned_vtgs: filter_non_pretransitioned,
                                               filter_pretransitioned_vtgs: filter_pretransitioned)
        if resource.blank?
          raise Common::Exceptions::RecordNotFound,
                "Triage teams for user ID #{@current_user.uuid} not found"
        end

        resource = resource.sort(params.permit(:sort)[:sort])

        # Even though this is a collection action we are not going to paginate
        render json: AllTriageTeamsSerializer.new(resource.data, { meta: resource.metadata })
      rescue => e
        StatsD.increment("#{STATSD_KEY_PREFIX}.fail")
        context = e.try(:errors)&.first&.try(:attributes)&.compact
        Rails.logger.error(e.message, context, e)
        raise e
      end
    end
  end
end
