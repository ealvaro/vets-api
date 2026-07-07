# frozen_string_literal: true

class CaveSubmission < ApplicationRecord
  # PII retention window. A CaveSubmission holds extracted document PII only long enough
  # to generate the 21-4138 change log and forward corrections to CAVE; rows past their
  # delete_date are removed by CaveSubmissionPurgeJob.
  RETENTION_DAYS = 90

  has_kms_key
  has_encrypted :cave_response, :change_log, key: :kms_key, **lockbox_options

  belongs_to :saved_claim, optional: true

  validates :cave_response, presence: true
  validate :cave_response_is_valid_json

  before_create :set_delete_date

  def parsed_response
    @parsed_response ||= JSON.parse(cave_response)
  rescue JSON::ParserError => e
    Rails.logger.warn('CaveSubmission#parsed_response: corrupt cave_response JSON', id:, error: e.message)
    nil
  end

  # The persisted user-correction change-log records for this submission ([] if none).
  def parsed_change_log
    return [] if change_log.blank?

    @parsed_change_log ||= JSON.parse(change_log)
  rescue JSON::ParserError => e
    Rails.logger.warn('CaveSubmission#parsed_change_log: corrupt change_log JSON', id:, error: e.message)
    []
  end

  private

  # Guards against persisting a row whose cave_response cannot be parsed back out. Without this,
  # a malformed payload would be stored silently and only blow up later at read time.
  def cave_response_is_valid_json
    return if cave_response.blank?

    JSON.parse(cave_response)
  rescue JSON::ParserError
    errors.add(:cave_response, 'must be valid JSON')
  end

  def set_delete_date
    self.delete_date ||= RETENTION_DAYS.days.from_now
  end
end
