# frozen_string_literal: true

require 'form21p530a/find_cemeteries_service'

module Form21p530a
  class FindCemeteriesJob
    include Sidekiq::Job

    sidekiq_options retry: 7

    def perform
      Rails.logger.info('Form21p530a::FindCemeteriesJob started')

      response = Form21p530a::FindCemeteriesService.new.response

      message = response.is_a?(Array) && response.size.positive? ? 'Find Cemeteries cached' : 'Find Cemeteries failed'
      Rails.logger.info("Form21p530a::FindCemeteriesJob: #{message}")

      Rails.logger.info('Form21p530a::FindCemeteriesJob completed')
    end
  end
end
