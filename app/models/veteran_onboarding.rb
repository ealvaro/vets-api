# frozen_string_literal: true

# The VeteranOnboarding model represents the onboarding status of a veteran.
# Each instance corresponds to a veteran who is in the process of onboarding.
#
# == Schema Information
#
# Table name: veteran_onboardings
#
#  id                      :bigint           not null, primary key
#  user_account_uuid       :string           not null, unique
#  display_onboarding_flow :boolean          default(TRUE)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
class VeteranOnboarding < ApplicationRecord
  belongs_to :user_account, primary_key: :id, foreign_key: :user_account_uuid, inverse_of: :veteran_onboarding
  validates :user_account, uniqueness: true

  DEFAULT_THRESHOLD_MINUTES = 30

  def show_onboarding_flow_on_login(user)
    return false unless Flipper.enabled?(:cve_onboarding_modal, user)

    display_onboarding_flow
  end

  class << self
    def find_or_create_for_user(user)
      return unless Flipper.enabled?(:cve_onboarding_modal, user)

      user_account = user.user_account
      return user_account&.veteran_onboarding if user_account&.veteran_onboarding
      return unless user_account&.verified?

      verified_at = user.user_verification&.verified_at
      return if verified_at.blank? || verified_at < cutoff_time

      record = create!(user_account:, display_onboarding_flow: true)
      StatsD.increment('veteran_onboarding.record_created')
      record
    rescue => e
      Rails.logger.error("VeteranOnboarding - Error creating record for account #{user_account&.id}: #{e.message}")
      nil
    end

    private

    def cutoff_time
      rd = release_date
      return rd if rd.present?

      recent_verification_threshold
    end

    def recent_verification_threshold
      raw = Settings.veteran_onboarding.onboarding_threshold_minutes.presence || DEFAULT_THRESHOLD_MINUTES
      minutes = Integer(raw)
      Time.zone.now - minutes.minutes
    rescue ArgumentError
      Rails.logger.error("VeteranOnboarding - Invalid onboarding threshold: #{raw}")
      Time.zone.now - DEFAULT_THRESHOLD_MINUTES.minutes
    end

    def release_date
      date = Settings.veteran_onboarding.onboarding_release_date
      return unless date.is_a?(String) && date.present?

      parsed = Time.zone.parse(date)
      parsed.presence
    rescue ArgumentError
      Rails.logger.error("VeteranOnboarding - Invalid onboarding release date: #{date}")
      nil
    end
  end
end
