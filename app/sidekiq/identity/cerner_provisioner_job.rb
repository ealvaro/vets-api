# frozen_string_literal: true

module Identity
  class CernerProvisionerJob
    include Sidekiq::Job

    sidekiq_options retry: false, unique_for: 5.minutes

    def self.sidekiq_unique_context(job)
      icn, messaging_only = job['args']

      [job['class'], job['queue'], [icn, messaging_only]]
    end

    def perform(icn, messaging_only, source = nil)
      CernerProvisioner.new(icn:, messaging_only:, source:).perform
    rescue Errors::CernerProvisionerError => e
      Rails.logger.info('[Identity] [CernerProvisionerJob] error',
                        { icn:, error_message: e.message, source:, safe_keys: [:icn] })
      raise if source.to_s == 'tou'
    end
  end
end
