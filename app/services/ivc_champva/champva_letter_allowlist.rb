# frozen_string_literal: true

require 'ivc_champva/config_file_loader'

module IvcChampva
  # Allowlist of VES correspondence letterTemplate.formNumber values relevant to
  # the CHAMPVA Status Tool (ticket #152149). An explicit allowlist, not a
  # prefix allowlist -- a CG/CCL/CVA prefix alone does not make a letter
  # relevant to CHAMPVA; CG in particular can include correspondence outside
  # CHAMPVA scope entirely. See config/benefits_claims/ves_approved_champva_letters.json
  # for the source-of-truth list and how to update it.
  module ChampvaLetterAllowlist
    APPROVED_FORM_NUMBERS_PATH =
      Rails.root.join('config', 'benefits_claims', 'ves_approved_champva_letters.json').freeze

    # Strips any suffix VES appends after a literal '.' (e.g. ".ENC") and a single
    # trailing lowercase letter, which is a version indicator (e.g. "CG-A01a" today,
    # a future "CG-A01b" tomorrow) rather than part of the letter's identity, so
    # both compare equal without the allowlist needing an update for every new
    # version letter VES introduces.
    #
    # Defined before APPROVED_FORM_NUMBERS below, which calls this at load time --
    # constant assignments run immediately as the file loads, so this method must
    # already exist by then, unlike a method body's own calls to methods defined
    # later in the file.
    #
    # @param form_number [String, nil]
    # @return [String, nil] normalized form number, or nil for blank input
    def self.normalize(form_number)
      return nil if form_number.blank?

      base = form_number.to_s.strip.split('.').first
      # Strip the trailing version letter, if present, based on its *original* case --
      # before downcasing, not after. Downcasing first (as this used to do) makes every
      # trailing letter look lowercase by the time the regex runs, so a genuinely
      # different form number ending in an uppercase letter (if VES ever sends one) would
      # get silently collapsed into whatever lowercase-suffixed entry shares the same base,
      # rather than being treated as its own distinct identity like this comment always
      # said it should be. Every value in the actual allowlist config today already uses a
      # lowercase suffix, so this only makes matching stricter, never looser.
      base = base.sub(/[a-z]\z/, '')
      base.downcase
    end

    APPROVED_FORM_NUMBERS = IvcChampva::ConfigFileLoader.load(
      APPROVED_FORM_NUMBERS_PATH,
      context: 'IvcChampva::ChampvaLetterAllowlist',
      fallback: {}
    ).fetch('approved_form_numbers', []).filter_map { |id| normalize(id) }.to_set.freeze

    # @param form_number [String, nil] a VES correspondence's letterTemplate.formNumber,
    #   e.g. "CCL-A43a.ENC" or "CG-A01a"
    # @return [Boolean] true when this letter is on the approved allowlist
    def self.approved?(form_number)
      normalized = normalize(form_number)
      normalized.present? && APPROVED_FORM_NUMBERS.include?(normalized)
    end
  end
end
