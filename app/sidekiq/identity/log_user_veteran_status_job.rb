# frozen_string_literal: true

module Identity
  class LogUserVeteranStatusJob
    include Sidekiq::Job

    sidekiq_options retry: 3

    def perform(user_uuid)
      user = User.find(user_uuid)
      return unless user

      is_veteran = false

      is_veteran = fetch_user_veteran_status(user) if user.loa3? && user.edipi.present?

      Rails.logger.info(
        'user_veteran_status',
        icn: user.icn,
        user_uuid: user.uuid,
        is_veteran:,
        safe_keys: [:icn]
      )
    end

    private

    def fetch_user_veteran_status(user)
      user.veteran?
    rescue VAProfile::VeteranStatus::VAProfileError => e
      if e.status == 404
        false
      else
        Rails.logger.info('user_veteran_status lookup failed',
                          user_uuid: user.uuid,
                          icn: user.icn,
                          status: e.status,
                          safe_keys: [:icn])
        raise
      end
    end
  end
end
