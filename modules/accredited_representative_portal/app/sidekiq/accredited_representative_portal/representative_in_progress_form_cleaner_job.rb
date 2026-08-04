# frozen_string_literal: true

require 'sidekiq'

module AccreditedRepresentativePortal
  # Sweeps expired RepresentativeInProgressForm rows, mirroring InProgressFormCleaner.
  class RepresentativeInProgressFormCleanerJob
    include Sidekiq::Job

    sidekiq_options retry: 3

    def perform
      forms = RepresentativeInProgressForm.where('expires_at < ?', Time.now.utc)

      form_counts = forms.group(:form_id).count
      form_counts.each do |form_id, count|
        next unless count.positive?

        key = "worker.arp.representative_in_progress_form_cleaner.#{form_id.downcase.tr('-', '_')}_deleted"
        StatsD.increment(key, count)
      end

      Rails.logger.info("#{self.class.name}: Deleting #{forms.count} expired representative in-progress forms")
      forms.delete_all
    end
  end
end
