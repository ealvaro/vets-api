# frozen_string_literal: true

##
# Shared concern for tracking dependents-related data fetching for FormProfiles
module DependentsServiceMonitoring
  extend ActiveSupport::Concern

  def track_dependents_results(dependents, _user)
    return if dependents.blank? || dependents[:persons].blank?

    num_dependents = dependents[:persons].size
    num_no_ssn_dependents = dependents[:persons].count { |d| d[:ssn].blank? }

    tags = ["class:#{self.class.name}"]

    StatsD.increment('bgs.get_dependents.total_results', num_dependents, tags:)
    StatsD.increment('bgs.get_dependents.no_ssn_results', num_no_ssn_dependents, tags:)
  rescue => e
    Rails.logger.error("Failure in track_dependents_results. #{self.class.name}: #{e.message}")
  end
end
