# frozen_string_literal: true

require 'formatters/date_formatter'
require 'lighthouse/benefits_education/service'

module V1
  class Post911GIBillStatusesController < ApplicationController
    include IgnoreNotFound

    service_tag 'gibill-statement'

    STATSD_KEY_PREFIX = 'api.post911_gi_bill_status'

    # Retrieves the Veteran's Post-9/11 GI Bill status from the Lighthouse Benefits Education API.
    def show
      response = service.get_gi_bill_status
      render json: Post911GIBillStatusSerializer.new(response)
    rescue Breakers::OutageException => e
      raise e
    rescue ArgumentError => e
      monitor.track_request(:error, e.message, "#{STATSD_KEY_PREFIX}.argument_error")
      StatsD.increment("#{STATSD_KEY_PREFIX}.fail", tags: ['error:422'])
      render json: { errors: [{ status: '422', detail: e.message }] }, status: :unprocessable_entity
    rescue => e
      handle_error(e)
    ensure
      StatsD.increment("#{STATSD_KEY_PREFIX}.total")
    end

    private

    def handle_error(e)
      errors = e.respond_to?(:errors) ? e.errors : [{ status: '500', detail: e.message }]
      status = errors.first[:status].to_i
      log_vet_not_found(@current_user, Time.now.in_time_zone('Eastern Time (US & Canada)')) if status == 404
      monitor.track_request(:error, errors.first[:detail].to_s, "#{STATSD_KEY_PREFIX}.upstream_error",
                            tags: ["error:#{status}"])
      StatsD.increment("#{STATSD_KEY_PREFIX}.fail", tags: ["error:#{status}"])
      render json: { errors: }, status: status || :internal_server_error
    end

    def log_vet_not_found(user, timestamp)
      PersonalInformationLog.create(
        data: { timestamp:, user: user_json(user) },
        error_class: 'BenefitsEducation::NotFound'
      )
    end

    def user_json(user)
      {
        first_name: user.first_name,
        last_name: user.last_name,
        assurance_level: user.loa[:current].to_s,
        birls_id: user.birls_id,
        icn: user.icn,
        edipi: user.edipi,
        mhv_correlation_id: user.mhv_correlation_id,
        participant_id: user.participant_id,
        vet360_id: user.vet360_id,
        ssn: user.ssn,
        birth_date: Formatters::DateFormatter.format_date(user.birth_date, :datetime_iso8601)
      }.to_json
    end

    def monitor
      @monitor ||= Logging::Monitor.new(self.class.trace_service_tag)
    end

    def service
      BenefitsEducation::Service.new(@current_user&.icn)
    end
  end
end
