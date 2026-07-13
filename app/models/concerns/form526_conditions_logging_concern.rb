# frozen_string_literal: true

# For use with Form526Submission.
#
# Logs metrics about the Veteran-entered conditions on a submission. Reads the
# raw (pre-transformation) form data from the associated SavedClaim's
# parsed_form.
#
# Currently logs date-completion metrics for the v2 workflow, classifying each condition's date into
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
end
