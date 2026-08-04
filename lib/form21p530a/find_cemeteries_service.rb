# frozen_string_literal: true

require 'common/models/redis_store'
require 'common/models/concerns/cache_aside'
require 'form21p530a/cemetery_service'
require 'form21p530a/find_cemeteries_response'

module Form21p530a
  class FindCemeteriesService < ::Common::RedisStore
    include ::Common::CacheAside

    redis_config_key :bgs_find_cemeteries_response

    def response
      @response ||= begin
        result = response_from_redis_or_service
        result.is_a?(Form21p530a::FindCemeteriesResponse) ? result.response : result
      end
    end

    private

    def todays_date
      Time.zone.now.to_date.to_s
    end

    def response_from_redis_or_service
      do_cached_with(key: todays_date) do
        response = cemetery_service.find_cemeteries
        Form21p530a::FindCemeteriesResponse.new(filter_response(response))
      end
    end

    def cemetery_service
      Form21p530a::CemeteryService.new
    end

    def filter_response(response)
      Array.wrap(response).filter_map do |entry|
        next unless entry.is_a?(Hash)

        sliced = entry.slice(:org_nm, :addr_line_one, :addr_line_two, :city_nm, :state, :zip_code,
                             :day_phone_area_nbr, :day_phone_phone_nbr)
        sliced if sliced[:org_nm].present?
      end
    end
  end
end
