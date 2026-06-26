# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2025::Section03
  ##
  # Section III
  # Build the veteran service info structured data entries.
  #
  # @return [Hash]
  def build_section3
    merge_vet_aliases(form['veteranPreviousNames'])
    merge_service_branch_fields(form['serviceBranch'])
    fields.merge!(y_n_pair(form['nationalGuardActivated'], 'ACTIVATED_TO_FED_DUTY_YES', 'ACTIVATED_TO_FED_DUTY_NO'))
    fields.merge!(y_n_pair(form['pow'], 'POW_YES', 'POW_NO'))
    fields.merge!(
      {
        'DATE_ENTERED_TO_SERVICE' => format_date(form.dig('activeServiceDateRange', 'from')),
        'DATE_SEPARATED_FROM_SERVICE' => format_date(form.dig('activeServiceDateRange', 'to')),
        'PLACE_SEPARATED_FROM_SERVICE_1' => form['placeOfSeparation'],
        'DATE_OF_ACTIVATION' => format_date(form['nationalGuardActivationDate']),
        'NAME_RESERVE_UNIT' => form['unitName'],
        'ADDRESS_RESERVE_UNIT' => form['unitAddress'],
        'RESERVE_PHONE_NUMBER' => form['unitPhone'],
        'DATE_OF_CONFINEMENT_START' => form['pow'] ? format_date(form.dig('powDateRange', 'from')) : nil,
        'DATE_OF_CONFINEMENT_END' => form['pow'] ? format_date(form.dig('powDateRange', 'to')) : nil
      }
    )
  end

  ##
  # Build and merge the veteran alias fields
  #
  # @param aliases [Array<Hash>]
  def merge_vet_aliases(aliases = [])
    has_aliases = aliases&.length&.positive? || false
    fields.merge!(y_n_pair(has_aliases, 'VET_NAME_OTHER_Y', 'VET_NAME_OTHER_N'))
    n1_name = alias_name_hash(aliases&.first)
    n2_name = alias_name_hash(aliases&.second)
    fields.merge!(
      {
        'VET_NAME_OTHER_1' => alias_full_name(n1_name),
        'VET_NAME_OTHER_2' => alias_full_name(n2_name)
      }
    )
  end

  def alias_name_hash(alias_row)
    return {} unless alias_row.is_a?(Hash)

    other_service_name = alias_row['otherServiceName']
    other_service_name.is_a?(Hash) ? other_service_name : alias_row
  end

  def alias_full_name(name_hash)
    name = build_name(name_hash)
    [name[:first], name[:middle_initial], name[:last], name[:suffix]].compact.join(' ').presence
  end

  ##
  # Build and merge the veteran service branch fields
  #
  # @param branch [String]
  def merge_service_branch_fields(branch)
    if branch
      fields.merge!(
        {
          'BRANCH_OF_SERVICE_ARMY' => branch == 'army',
          'BRANCH_OF_SERVICE_NAVY' => branch == 'navy',
          'BRANCH_OF_SERVICE_AIR-FORCE' => branch == 'airForce',
          'BRANCH_OF_SERVICE_MARINE' => branch == 'marineCorps',
          'BRANCH_OF_SERVICE_COAST-GUARD' => branch == 'coastGuard',
          'BRANCH_OF_SERVICE_SPACE' => branch == 'spaceForce',
          'BRANCH_OF_SERVICE_NOAA' => branch == 'noaa',
          'BRANCH_OF_SERVICE_USPHS' => branch == 'usphs'
        }
      )
    end
  end
end
