# frozen_string_literal: true

require 'sidekiq/attr_package'

module VANotify
  module V2
    class QueueEmailJob
      include Sidekiq::Job

      sidekiq_options retry: 14

      sidekiq_retries_exhausted do |msg, _ex|
        attr_package_key = msg['args']&.second
        Sidekiq::AttrPackage.delete(attr_package_key) if attr_package_key
        job_id = msg['jid']
        job_class = msg['class']
        error_class = msg['error_class']
        error_message = msg['error_message']

        message = "#{job_class} retries exhausted"
        Rails.logger.error(message, { job_id:, error_class:, error_message: })
        StatsD.increment("sidekiq.jobs.#{job_class.underscore}.retries_exhausted")
      end

      def perform(template_id, attr_package_key, api_key_path, callback_options = {})
        attrs = fetch_attrs(attr_package_key, template_id)
        email = attrs[:email]
        personalisation = attrs[:personalisation]
        api_key = resolve_api_key(api_key_path)

        begin
          VaNotify::Service.new(api_key, callback_options).send_email(
            email_address: email,
            template_id:,
            personalisation:
          )
          StatsD.increment('api.vanotify.v2.send_email.success')
        rescue VANotify::Error => e
          StatsD.increment('api.vanotify.v2.send_email.failure')
          handle_backend_exception(e, template_id, callback_options)
        rescue => e
          StatsD.increment('api.vanotify.v2.send_email.failure')
          raise e
        end
      end

      def self.enqueue(email, template_id, personalisation, api_key_path, callback_options = {})
        unless api_key_path.start_with?('Settings.')
          raise ArgumentError, "API key path must start with 'Settings.': #{api_key_path}"
        end

        key = Sidekiq::AttrPackage.create(email:, personalisation:)
        perform_async(template_id, key, api_key_path, callback_options)
      end

      # rubocop:disable Metrics/ParameterLists
      def self.enqueue_at(at, email, template_id, personalisation, api_key_path, callback_options = {})
        # rubocop:enable Metrics/ParameterLists
        unless api_key_path.start_with?('Settings.')
          raise ArgumentError, "API key path must start with 'Settings.': #{api_key_path}"
        end

        key = Sidekiq::AttrPackage.create(email:, personalisation:)
        perform_at(at, template_id, key, api_key_path, callback_options)
      end

      private

      def fetch_attrs(attr_package_key, template_id = nil)
        begin
          attrs = Sidekiq::AttrPackage.find(attr_package_key)
        rescue Sidekiq::AttrPackageError => e
          Rails.logger.error('VANotify::V2::QueueEmailJob AttrPackage error', {
                               error: e.message,
                               template_id:
                             })
          raise ArgumentError, e.message
        end

        if attrs
          attrs
        else
          Rails.logger.error('VANotify::V2::QueueEmailJob failed: Missing personalisation data in Redis', {
                               template_id:,
                               attr_package_key_present: attr_package_key.present?
                             })
          raise ArgumentError, 'Missing personalisation data in Redis'
        end
      end

      def handle_backend_exception(e, template_id, callback_options)
        if e.status_code == 400
          tags = failure_tags(callback_options)
          StatsD.increment('silent_failure', tags:) if tags.any?
          Rails.logger.error('VANotify::V2::QueueEmailJob send_email failed with 400', {
                               template_id:,
                               error_message: e.message,
                               tags:
                             })
        else
          raise e
        end
      end

      def failure_tags(callback_options)
        # Sidekiq round-trips job args through JSON, so symbol keys arrive as strings here.
        statsd_tags = callback_options.with_indifferent_access.dig(:callback_metadata, :statsd_tags)

        # Callers pass statsd_tags as either a Hash (service: ..., function: ...) or an
        # already-formatted Array of "key:value" strings -- same contract DefaultCallback
        # enforces on the delivery-callback side.
        case statsd_tags
        when Hash
          statsd_tags.map { |pair| pair.join(':') }
        when Array
          statsd_tags
        else
          []
        end
      end

      def resolve_api_key(api_key_path)
        unless api_key_path.start_with?('Settings.')
          raise ArgumentError, "API key path must start with 'Settings.': #{api_key_path}"
        end

        keys = api_key_path.delete_prefix('Settings.').split('.')
        api_key = Settings.dig(*keys)
        raise ArgumentError, "Unable to resolve API key from path: #{api_key_path}" if api_key.blank?

        api_key
      end
    end
  end
end
