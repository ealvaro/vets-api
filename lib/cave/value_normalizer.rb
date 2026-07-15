# frozen_string_literal: true

module Cave
  # Ports the field normalization used by vets-website
  # (src/applications/survivors-benefits/cave/transformers/normalize.js) into Ruby.
  #
  # The CAVE 21-4138 change log compares two representations of the same field:
  #   * the OCR-extracted value: a raw string from CaveSubmission#cave_response
  #     (e.g. "JON A DOE", "ARMY USAR", "01/15/1960")
  #   * the user-final value: the already-normalized value the frontend submits in
  #     files[].idpArtifacts (e.g. { first: "John", ... }, "army", "1960-01-15")
  #
  # To decide whether the user actually CHANGED a field (rather than the value merely
  # being stored in a different shape), both sides are reduced to a canonical,
  # comparable form here. This mirrors normalize.js so an unedited field compares equal.
  #
  # If normalize.js changes, keep this in sync (see spec/lib/cave/value_normalizer_spec.rb).
  # rubocop:disable Metrics/ModuleLength
  module ValueNormalizer
    module_function

    NAME_SUFFIXES = ['Jr.', 'Sr.', 'II', 'III', 'IV'].freeze

    CHARACTER_OF_SERVICE_OPTIONS = [
      'Honorable',
      'General (Under Honorable Conditions)',
      'Other Than Honorable',
      'Bad Conduct Discharge',
      'Dishonorable Discharge',
      'Uncharacterized',
      'Entry Level Separation'
    ].freeze

    CHARACTER_OF_SERVICE_ABBREV_MAP = {
      'OTH' => 'Other Than Honorable',
      'BCD' => 'Bad Conduct Discharge',
      'DD' => 'Dishonorable Discharge',
      'ELS' => 'Entry Level Separation'
    }.freeze

    PAY_GRADE_OPTIONS = %w[
      O-1 O-2 O-3 O-4 O-5 O-6 O-7 O-8 O-9 O-10
      E-1 E-2 E-3 E-4 E-5 E-6 E-7 E-8 E-9
      W-1 W-2 W-3 W-4 W-5
    ].freeze

    BRANCH_PATTERNS = [
      [/\bAIR\s*FORCE\b/, 'airForce'],
      [/\bSPACE\s*FORCE\b/, 'spaceForce'],
      [/\bCOAST\s*GUARD\b/, 'coastGuard'],
      [/\bMARINE\b/, 'marineCorps'],
      [/\bNAVY\b/, 'navy'],
      [/\bARMY\b/, 'army'],
      [/\bUSPHS\b|\bPUBLIC\s*HEALTH\b/, 'usphs'],
      [/\bNOAA\b/, 'noaa']
    ].freeze

    NAME_SUFFIX_LOOKUP = NAME_SUFFIXES.index_by { |suffix| suffix.downcase.delete('.') }.freeze

    CHARACTER_OF_SERVICE_LOOKUP = begin
      lookup = {}
      CHARACTER_OF_SERVICE_ABBREV_MAP.each { |abbrev, full| lookup[abbrev.downcase] = full }
      CHARACTER_OF_SERVICE_OPTIONS.each { |full| lookup[full.downcase] = full }
      lookup.freeze
    end

    PAY_GRADE_LOOKUP = PAY_GRADE_OPTIONS.index_by(&:downcase).freeze

    # Display labels for the 534EZ service-branch enum values (the user-final side
    # stores the enum, e.g. "army"); used only for human-readable change-log output.
    BRANCH_LABELS = {
      'army' => 'Army',
      'navy' => 'Navy',
      'airForce' => 'Air Force',
      'spaceForce' => 'Space Force',
      'coastGuard' => 'Coast Guard',
      'marineCorps' => 'Marine Corps',
      'usphs' => 'USPHS',
      'noaa' => 'NOAA'
    }.freeze

    # Returns a canonical, comparable string for `value` interpreted as `type`.
    # Accepts either a raw OCR string or an already-normalized user value.
    # Empty / unparseable values collapse to '' so nil and '' compare equal.
    def canonical(type, value)
      case type
      when :name then canonical_name(value)
      when :ssn then digits(value).then { |d| d.length == 9 ? d : '' }
      when :date then normalize_date(value).to_s
      when :branch then normalize_branch(value).to_s
      when :pay_grade then normalize_pay_grade(value).to_s
      when :character_of_service then normalize_character_of_service(value).to_s
      else free_text(value).downcase # :text and :separation_code
      end
    end

    # Returns a human-readable rendering of an already-normalized user value, for
    # display in the change-log line. (The OCR side is shown verbatim from cave_response.)
    def display(type, value)
      case type
      when :name then format_name(value)
      when :ssn then format_ssn(value)
      when :date then format_date(value)
      when :branch then BRANCH_LABELS[value.to_s] || value.to_s
      else value.to_s.strip
      end
    end

    def free_text(value)
      value.is_a?(String) ? value.strip : value.to_s.strip
    end

    def digits(value)
      value.to_s.gsub(/\D/, '')
    end

    # Parses a full name string into { first, middle, last, suffix }, mirroring
    # parseFullName in normalize.js.
    #
    # Ordering: DD-214 Field 1 (and death-certificate names) arrive in
    # "Last, First, Middle" order, e.g. "ARTHUR, DONALD, CALDWELL JR.". The comma
    # is the only signal of that ordering, so when a comma is present the text
    # before the first comma is the surname and the remainder is
    # First [Middle...] [Suffix]. Without a comma the value is assumed to already
    # be in natural order and parsed positionally (2 -> first/last,
    # 3 -> first/middle/last, 4+ -> +suffix).
    def parse_full_name(raw)
      return {} unless raw.is_a?(String)

      parse_last_first_name(raw) || parse_positional_name(raw)
    end

    # Parses the "Last, First, Middle" comma form. Returns nil when there is no
    # usable comma so the caller can fall back to positional parsing.
    def parse_last_first_name(raw)
      comma_idx = raw.index(',')
      return nil unless comma_idx

      last_tokens = raw[0...comma_idx].strip.split(/\s+/).reject(&:empty?)
      rest_tokens = (raw[(comma_idx + 1)..] || '').delete(',').strip.split(/\s+/).reject(&:empty?)
      return nil if last_tokens.empty? || rest_tokens.empty?

      middle, suffix = split_middle_and_suffix(rest_tokens[1..] || [])
      result = { first: title_case(rest_tokens[0]), last: last_tokens.map { |t| title_case(t) }.join(' ') }
      result[:middle] = middle unless middle.empty?
      result[:suffix] = suffix if suffix
      result
    end

    # Parses a comma-free name assumed to be in natural order
    # (2 -> first/last, 3 -> first/middle/last, 4+ -> +suffix).
    def parse_positional_name(raw)
      tokens = raw.delete(',').strip.split(/\s+/).reject(&:empty?)
      return {} if tokens.empty?

      first = title_case(tokens[0])
      case tokens.length
      when 1 then { first: }
      when 2 then { first:, last: title_case(tokens[1]) }
      when 3 then { first:, middle: title_case(tokens[1]), last: title_case(tokens[2]) }
      else
        {
          first:,
          middle: title_case(tokens[1]),
          last: title_case(tokens[2]),
          suffix: normalize_suffix(tokens[3..].join(' '))
        }.compact
      end
    end

    # Splits the trailing suffix (if any) off a [first, middle...] token list,
    # returning [middle_string, suffix_or_nil].
    def split_middle_and_suffix(middle_tokens)
      if middle_tokens.any?
        suffix = normalize_suffix(middle_tokens[-1])
        return [middle_tokens[0...-1].map { |t| title_case(t) }.join(' '), suffix] if suffix
      end
      [middle_tokens.map { |t| title_case(t) }.join(' '), nil]
    end

    def title_case(str)
      return str if str.blank?

      str[0].upcase + str[1..].downcase
    end

    def normalize_suffix(value)
      return nil unless value.is_a?(String)

      NAME_SUFFIX_LOOKUP[value.strip.downcase.delete('.')]
    end

    # "MM/DD/YYYY" -> "YYYY-MM-DD". Passes through values already in ISO form.
    # Returns '' for blank, nil for unparseable.
    def normalize_date(value)
      return '' if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return nil unless value.is_a?(String)

      trimmed = value.strip
      return trimmed if /\A\d{4}-\d{2}-\d{2}\z/.match?(trimmed)

      parts = trimmed.split('/')
      return nil unless parts.length == 3

      month, day, year = parts
      return nil unless year&.length == 4

      format('%<y>s-%<m>02d-%<d>02d', y: year, m: month.to_i, d: day.to_i)
    end

    def normalize_branch(value)
      return '' if value.nil? || (value.is_a?(String) && value.strip.empty?)

      upper = value.to_s.strip.upcase
      return '' if upper.empty?

      BRANCH_PATTERNS.each { |pattern, enum| return enum if pattern.match?(upper) }
      # Already a 534 enum value (the user side) — pass through unchanged.
      value.to_s.strip
    end

    def normalize_pay_grade(value)
      return '' if value.nil? || (value.is_a?(String) && value.strip.empty?)

      PAY_GRADE_LOOKUP[value.to_s.strip.downcase] || ''
    end

    def normalize_character_of_service(value)
      return '' if value.nil? || (value.is_a?(String) && value.strip.empty?)

      CHARACTER_OF_SERVICE_LOOKUP[value.to_s.strip.downcase] || ''
    end

    # ---- display helpers -------------------------------------------------------

    def format_name(value)
      parts = value.is_a?(Hash) ? value.transform_keys(&:to_sym) : parse_full_name(value.to_s)
      [parts[:first], parts[:middle], parts[:last], parts[:suffix]].compact.map(&:to_s).reject(&:empty?).join(' ')
    end

    def format_ssn(value)
      d = digits(value)
      d.length == 9 ? "#{d[0..2]}-#{d[3..4]}-#{d[5..8]}" : value.to_s
    end

    def format_date(value)
      iso = normalize_date(value)
      return value.to_s unless iso.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(iso)

      year, month, day = iso.split('-')
      "#{month}/#{day}/#{year}"
    end

    # Canonicalizes a name from either a raw string or a { first, middle, last, suffix } hash.
    def canonical_name(value)
      format_name(value).downcase.gsub(/\s+/, ' ').strip
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
