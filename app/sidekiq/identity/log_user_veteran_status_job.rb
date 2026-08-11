# frozen_string_literal: true

module Identity
  class LogUserVeteranStatusJob
    include Sidekiq::Job

    sidekiq_options retry: 3

    def perform(user_uuid)
      user = User.find(user_uuid)
      return unless user

      verified = user.loa3?
      is_veteran = false

      is_veteran = fetch_user_veteran_status(user) if verified && user.edipi.present?

      Rails.logger.info(
        'user_veteran_status',
        icn: user.icn,
        user_uuid: user.uuid,
        verified:,
        is_veteran:,
        mpi_vet_person_type: mpi_vet_person_type(user),
        safe_keys: [:icn]
      )
    rescue Breakers::OutageException
      # An open circuit stays open for the duration of the outage, so retrying cannot succeed. End
      # the job here and record why, in place of the user_veteran_status line that will not be
      # written — otherwise the attempt leaves no trace at all.
      log_veteran_status_unavailable(user)
    end

    private

    def mpi_vet_person_type(user)
      Array(user.person_types).include?('VET')
    end

    def log_veteran_status_unavailable(user)
      Rails.logger.warn(
        'user_veteran_status unavailable',
        icn: user.icn,
        user_uuid: user.uuid,
        reason: 'VA Profile veteran status unavailable',
        safe_keys: [:icn]
      )
    end

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
