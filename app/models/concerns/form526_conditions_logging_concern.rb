# frozen_string_literal: true

# For use with Form526Submission.
#
# Logs metrics about the Veteran-entered conditions on a submission. Reads the
# raw (pre-transformation) form data from the associated SavedClaim's
# parsed_form.
#
# This includes:
#
# * Date-completion metrics for the v2 workflow, classifying each condition's date into
# one of three extents:
#
# - full:    a complete date, YYYY-MM-DD with no wildcards (e.g. "2022-04-01")
# - partial: a date with missing parts, indicated by "XX" (e.g. "2024-02-XX", "2024-XX-XX")
# - blank:   no date provided (key absent or empty)
#
# New conditions store the date under "conditionDate"; rated disabilities store
# it under "approximateDate". Only rated disabilities being claimed for an
# increase (disabilityActionType "INCREASE") are counted; existing rated
# disabilities not being claimed (e.g. "NONE") are ignored.
#
# Note: "conditionDate" and "approximateDate" are only captured by the v2
# ("new conditions") workflow.
#
# * Supporting evidence metrics, describing evidence counts and whether any toxic exposure events
# are reported.
#
# Additional condition logging can be added here as new methods.
module Form526ConditionsLoggingConcern
  extend ActiveSupport::Concern

  FULL_DATE_REGEX = /\A\d{4}-\d{2}-\d{2}\z/

  def log_conditions_date_metrics
    Rails.logger.info('Form526 conditions date metrics',
                      submission_id: id,
                      user_uuid:,
                      in_progress_form_id: in_progress_form&.id,
                      **condition_date_completion_extent)
  rescue => e
    # Log the exception but do not fail
    log_error(e)
  end

  def log_conditions_evidence_metrics
    Rails.logger.info('Form526 conditions evidence metrics',
                      submission_id: id,
                      user_uuid:,
                      in_progress_form_id: in_progress_form&.id,
                      **condition_evidence_metrics)
  rescue => e
    # Log the exception but do not fail
    log_error(e)
  end

  private

  def submitted_conditions
    form_data = saved_claim.parsed_form || {}
    new_conditions = Array(form_data['newPrimaryDisabilities'])
    rated_increases = Array(form_data['ratedDisabilities']).select do |disability|
      disability['disabilityActionType']&.upcase == 'INCREASE'
    end
    new_conditions + rated_increases
  end

  def condition_date_completion_extent
    tally = { full_count: 0, partial_count: 0, blank_count: 0, total_conditions: 0 }

    submitted_conditions.each do |condition|
      tally[:total_conditions] += 1
      case condition_date_extent(condition['conditionDate'] || condition['approximateDate'])
      when :full    then tally[:full_count] += 1
      when :partial then tally[:partial_count] += 1
      else               tally[:blank_count] += 1
      end
    end

    tally
  end

  def condition_date_extent(date_string)
    return :blank if date_string.blank?

    str = date_string.to_s.strip
    return :blank if str.blank?
    return :full if str.match?(FULL_DATE_REGEX)

    :partial
  end

  def condition_evidence_metrics
    form_data = saved_claim.parsed_form || {}

    evidence_va = Array(form_data['vaTreatmentFacilities']).size
    evidence_private = Array(form_data.dig('form4142', 'providerFacility')).size
    evidence_uploads = Array(form_data['attachments']).size

    metrics = {
      toxic_exposure: toxic_exposure_reported?(form_data['toxicExposure']),
      evidence_va:,
      evidence_private:,
      evidence_uploads:,
      evidence_any: [evidence_va, evidence_private, evidence_uploads].any?(&:positive?),
      total_conditions: submitted_conditions.size
    }

    if form_data.key?('disabilityCompConditionsEvidenceMessagingTest')
      metrics[:disability_comp_conditions_evidence_messaging_test] =
        form_data['disabilityCompConditionsEvidenceMessagingTest']
    end

    metrics
  end

  TOXIC_EXPOSURE_CATEGORIES = %w[gulfWar1990 gulfWar2001 herbicide otherExposures].freeze
  TOXIC_EXPOSURE_NON_AFFIRMATIVE_KEYS = %w[none notsure].freeze
  TOXIC_EXPOSURE_DESCRIPTION_KEYS = %w[otherHerbicideLocations specifyOtherExposures].freeze

  # Returns true if the submission reports any toxic exposure events.
  # Determined by:
  #  - response of true to any of the keys within each of the categories, excluding
  #    the keys "none" and "notsure"
  #  - presence of a non-empty "description" field of the free-text options
  def toxic_exposure_reported?(toxic_exposure_data)
    return false unless toxic_exposure_data.is_a?(Hash) && toxic_exposure_data.present?

    category_reported = TOXIC_EXPOSURE_CATEGORIES.any? do |category_key|
      category = toxic_exposure_data[category_key]
      next false unless category.is_a?(Hash) && category.present?

      category.any? { |question, response| TOXIC_EXPOSURE_NON_AFFIRMATIVE_KEYS.exclude?(question) && response == true }
    end

    description_reported = TOXIC_EXPOSURE_DESCRIPTION_KEYS.any? do |description_key|
      toxic_exposure_data[description_key]&.[]('description').present?
    end

    category_reported || description_reported
  end
end
