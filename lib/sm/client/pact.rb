# frozen_string_literal: true

module SM
  class Client < Common::Client::Base
    module Pact
      ##
      # Get an array of Pact teams for a given station_id
      #
      # @return [Hash{Symbol=>Object}] response envelope with keys :data (Array<Hash>), :errors (Hash), :metadata (Hash)
      #
      def get_pact(station_id)
        path = 'pcmm/assignments'
        json = perform(:get, path, nil, token_headers).body
        select_pact_by_station(json, station_id)
      end

      private

      def select_pact_by_station(pact_resp, station_id)
        pact_resp[:data]&.select! do |pact|
          !pact[:station_number].nil? &&
            pact[:station_number].to_s == station_id.to_s
        end
        pact_resp
      end
    end
  end
end
