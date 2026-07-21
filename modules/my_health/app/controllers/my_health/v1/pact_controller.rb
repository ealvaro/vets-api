# frozen_string_literal: true

module MyHealth
  module V1
    class PactController < SMController
      def show
        station = fetch_params[:station].to_s.to_i
        return render json: { data: [], errors: {}, metadata: {} }, status: :not_found if station.zero?

        response = client.get_pact(station)
        render json: PactSerializer.new(response[:data])
      end

      private

      def fetch_params
        params.permit(:station)
      end
    end
  end
end
