# frozen_string_literal: true

require 'lighthouse/benefits_claims/service'

module V0
  class IntentsToFileController < ApplicationController
    service_tag 'intents-to-file'

    before_action { authorize :lighthouse, :itf_access? }
    before_action { authorize :lighthouse, :access_vet_status? }

    TYPES = %w[compensation pension survivor].freeze

    STATSD_KEY_PREFIX = 'api.intents_to_file'
    STATSD_TAGS = [
      'service:intents-to-file',
      'team:benefits-management-tools',
      'dependency:lighthouse'
    ].freeze

    def index
      return render json: { data: [] } unless Flipper.enabled?(:cst_intents_to_file, @current_user)

      itfs = fetch_all_itfs
      record_itf_metrics(itfs)

      render json: { data: itfs }
    rescue => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.error", tags: STATSD_TAGS)
      Rails.logger.error('IntentsToFileController error fetching ITFs', {
                           error_class: e.class.name,
                           error_message: e.message
                         })
      raise
    end

    private

    # Temporary: fetches ITFs per type individually because Lighthouse currently only returns
    # the last active ITF for a single type. A change request has been submitted to Lighthouse
    # to support retrieving all ITFs in a single call.
    def fetch_all_itfs
      TYPES.flat_map { |type| fetch_itf_for_type(type) }
    end

    def fetch_itf_for_type(type)
      response = service.get_intent_to_file(type, nil, nil)
      data = response&.dig('data')

      return [] unless data

      [normalize_itf(data)]
    rescue Common::Exceptions::ResourceNotFound
      []
    end

    def normalize_itf(itf_data)
      attrs = itf_data['attributes'] || {}
      {
        id: itf_data['id'],
        type: attrs['type'],
        creation_date: attrs['creationDate'],
        expiration_date: attrs['expirationDate'],
        status: attrs['status']
      }
    end

    def record_itf_metrics(itfs)
      itfs.each do |itf|
        StatsD.increment("#{STATSD_KEY_PREFIX}.fetch",
                         tags: STATSD_TAGS + ["type:#{itf[:type]}", "status:#{itf[:status]}"])
      end
    end

    def service
      @service ||= BenefitsClaims::Service.new(@current_user.icn)
    end
  end
end
