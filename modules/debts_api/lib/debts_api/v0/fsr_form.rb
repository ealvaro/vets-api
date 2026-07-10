# frozen_string_literal: true

module DebtsApi
  class V0::FsrForm
    class FSRInvalidRequest < StandardError; end

    DEBTS_KEY = 'selectedDebtsAndCopays'
    DEDUCTION_CODES = {
      '30' => 'Disability compensation and pension debt',
      '41' => 'Chapter 34 education debt',
      '44' => 'Chapter 35 education debt',
      '71' => 'Post-9/11 GI Bill debt for books and supplies',
      '72' => 'Post-9/11 GI Bill debt for housing',
      '74' => 'Post-9/11 GI Bill debt for tuition',
      '75' => 'Post-9/11 GI Bill debt for tuition (school liable)'
    }.freeze
    HARDSHIP_SUSPENSION = 'hardship-suspension'
    MONTHLY = 'monthly'
    WAIVER = 'waiver'
    COMPROMISE = 'compromise'

    HARDSHIP_SUSPENSION_DESCRIPTION =
      'Hardship Suspension Request Information: I am experiencing temporary financial hardship ' \
      'and I estimate my financial situation to improve'
    COMPROMISE_DESCRIPTION = 'compromise amount:'

    TIMEFRAME_OPTIONS = {
      'within-6-months' => 'within 6 months',
      '6-to-12-months' => 'between 6-12 months',
      '12-to-18-months' => 'between 12-18 months',
      '18-to-24-months' => 'between 18-24 months'
    }.freeze

    def add_additional_comments(form, debts)
      resolution_text = get_resolution_option_text(debts)
      return if resolution_text.blank?

      existing = form['additionalData']['additionalComments']
      form['additionalData']['additionalComments'] =
        [existing, resolution_text].compact_blank.join(' ')
    end

    def extract_resolution_options(debts)
      return [] if debts.blank?

      debts.pluck('resolutionOption').compact.uniq
    end

    def get_resolution_option_text(debts)
      debts.filter_map { |debt| format_resolution(debt) }.join(', ')
    end

    def aggregate_fsr_reasons(form, debts)
      return if debts.blank?

      reasons = debts.pluck('resolutionOption').uniq.map do |option|
        option == HARDSHIP_SUSPENSION ? 'hardship suspension' : option
      end
      form['personalIdentification']['fsrReason'] = reasons.join(', ').delete_prefix(', ')
    end

    def enabled_feature_flags(user)
      begin
        enabled_flags = Flipper.features.select { |feature| feature.enabled?(user) }.map do |feature|
          feature.name.to_s
        end.sort
      rescue => e
        Rails.logger.error('Failed to source user flags', e.message)
        enabled_flags = []
      end

      enabled_flags
    end

    def in_progress_form(user_uuid)
      InProgressForm.where(form_id: '5655', user_uuid:).last
    end

    private

    def format_resolution(debt)
      case debt['resolutionOption']
      when COMPROMISE          then format_compromise(debt)
      when HARDSHIP_SUSPENSION then format_hardship(debt) if hardship_suspension_enabled?
      end
    end

    def format_compromise(debt)
      "#{DEDUCTION_CODES[debt['deductionCode']]} #{COMPROMISE_DESCRIPTION} $#{debt['resolutionComment']}"
    end

    def format_hardship(debt)
      "#{DEDUCTION_CODES[debt['deductionCode']]} - #{HARDSHIP_SUSPENSION_DESCRIPTION} " \
        "#{TIMEFRAME_OPTIONS[debt['hardshipTimeframe']]}"
    end

    def hardship_suspension_enabled?
      Flipper.enabled?(:enable_hardship_suspension, @user)
    end
  end
end
