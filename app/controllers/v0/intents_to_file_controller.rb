# frozen_string_literal: true

require 'concurrent-ruby'
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
    #
    # Requests run in parallel (scatter-gather) to reduce total latency; each future
    # instantiates its own BenefitsClaims::Service to avoid sharing instance state.
    def fetch_all_itfs
      icn = @current_user.icn

      futures = TYPES.map do |type|
        Concurrent::Promises.future { fetch_itf_for_type(icn, type) }
      end
      # Wait for every type to finish and raise if any future failed
      Concurrent::Promises.zip(*futures).value!.flatten
    rescue Concurrent::MultipleErrors => e
      # Several types can fail at once; surface one exception for consistent API / error handling
      raise e.errors.first
    end

    def fetch_itf_for_type(icn, type)
      response = BenefitsClaims::Service.new(icn).get_intent_to_file(type, nil, nil)
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
  end
end
