# frozen_string_literal: true

require 'sidekiq'
require_relative 'constants'

module EventBusGateway
  # DEPRECATED — no-op drain shim. The claim-letter propagation-lag measurement
  # this job performed (#146570) has been replaced by the gated send in
  # LetterReadyNotificationJob (#148062), which no longer enqueues this job.
  #
  # This empty shell exists only so that measurement jobs already on the Sidekiq
  # queue when #148062 deploys — deferred via perform_in up to 7 days out — can
  # still deserialize and drain instead of landing in the dead set. It does no BD
  # work; it just records that a stale job was drained.
  #
  # SAFE TO DELETE once the longest outstanding interval (7 days) has elapsed
  # after deploy and the drained metric has gone quiet. Tracked as a follow-up to
  # #148062.
  class LetterReadyClaimLetterRecheckJob
    include Sidekiq::Job

    STATSD_METRIC_PREFIX = 'event_bus_gateway.letter_ready_claim_letter_recheck'

    # Never retry: a drained measurement job must never back up the queue.
    sidekiq_options retry: false

    def perform(*_args)
      ::Rails.logger.info('LetterReadyClaimLetterRecheckJob drained (deprecated no-op)')
      StatsD.increment("#{STATSD_METRIC_PREFIX}.drained", tags: Constants::DD_TAGS)
      nil
    end
  end
end
