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

  def show_onboarding_flow_on_login
    actor = OpenStruct.new(flipper_id: user_account_uuid)
    return false unless Flipper.enabled?(:cve_onboarding_modal, actor)

    display_onboarding_flow
  end

  def self.create_for_user_account(account)
    actor = OpenStruct.new(flipper_id: account.id)
    return unless Flipper.enabled?(:cve_onboarding_modal, actor)

    unless account.verified?
      Rails.logger.info("VeteranOnboarding - Account not verified: #{account.id}")
      return
    end

    record = create!(user_account: account, display_onboarding_flow: true)
    StatsD.increment('veteran_onboarding.record_created')
    record
  rescue => e
    Rails.logger.error("VeteranOnboarding - Error creating record for account #{account.id}: #{e.message}")
    nil
  end
end
