# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2025::Section06
  ##
  # Section VI
  # Build and merge the children of the veteran structured data entries.
  def build_section6
    children_do_not_live_with_claimant = form['childrenLiveTogetherButNotWithSpouse']
    merge_custodian_fields if children_do_not_live_with_claimant
    fields.merge!({ 'NUMBER_OF_DEP_CHILD' => form['veteranChildrenCount'] })
    fields.merge!(
      y_n_pair(children_do_not_live_with_claimant, 'CHILD_DO_NOT_LIVE_WITH_CL_Y', 'CHILD_DO_NOT_LIVE_WITH_CL_N')
    )

    children = form['veteransChildren'] || []
    children&.each_with_index do |child, index|
      child_num = index + 1
      merge_child_status_fields(child['childStatus'], child_num)
      build_and_merge_child(child, child_num)
    end
  end

  ##
  # Build and merge the structured data fields for the custodian of the veteran's children.
  def merge_custodian_fields
    custodian_name = build_name(form['custodianFullName'])
    custodian_address = form['custodianAddress'] || {}
    fields.merge!(
      {
        'CUSTODIAN_CHILD1_NAME' => custodian_name[:full],
        'CUSTODIAN_CHILD1_FIRST_NAME' => custodian_name[:first],
        'CUSTODIAN_CHILD1_MID_INT' => custodian_name[:middle_initial],
        'CUSTODIAN_CHILD1_LAST_NAME' => custodian_name[:last],
        'CUSTODIAN_ADDRESS_LINE_1' => custodian_address['street'],
        'CUSTODIAN_ADDRESS_LINE_2' => custodian_address['street2'],
        'CUSTODIAN_ADDRESS_CITY' => custodian_address['city'],
        'CUSTODIAN_ADDRESS_STATE' => custodian_address['state'],
        'CUSTODIAN_ADDRESS_COUNTRY' => custodian_address['country'],
        'CUSTODIAN_ADDRESS_ZIP' => custodian_address['postalCode']&.[](0..4),
        'CUSTODIAN_CHILD_NAME_ADDRESS' => [
          custodian_name[:full],
          build_address_block(custodian_address)
        ].compact.join(', ')
      }
    )
  end

  ##
  # Build and merge the structured data fields for a veteran/child status.
  # V2025 uses a childStatus array instead of a single relationship string.
  #
  # @param child_status [Array<String>] The child status values (e.g., "BIOLOGICAL", "ADOPTED", "STEPCHILD")
  # @param child_num [Integer] The number of the child (e.g., 1 for the first child, 2 for the second, etc.)
  def merge_child_status_fields(child_status, child_num)
    status = Array(child_status)
    fields.merge!(
      {
        "BIOLOGICAL_CHILD_#{child_num}" => status.include?('BIOLOGICAL'),
        "ADOPTED_CHILD_#{child_num}" => status.include?('ADOPTED'),
        "STEPCHILD_#{child_num}" => status.include?('STEPCHILD')
      }
    )
  end

  ##
  # Build and merge the structured data fields for a veteran's child based on the child's information.
  #
  # @param child [Hash] The child's information from the form
  def build_and_merge_child(child, child_num)
    child_name = build_name(child['childFullName'])
    child_status = Array(child['childStatus'])
    fields.merge!(
      {
        "NAME_OF_CHILD_#{child_num}" => child_name[:full],
        "FIRST_NAME_OF_CHILD_#{child_num}" => child_name[:first],
        "MID_INT_OF_CHILD_#{child_num}" => child_name[:middle_initial],
        "LAST_NAME_OF_CHILD_#{child_num}" => child_name[:last],
        "DATE_OF_BIRTH_CHILD_#{child_num}" => format_date(child['childDateOfBirth']),
        "CHILD_#{child_num}_SSN" => child['childSocialSecurityNumber'],
        "PLACE_OF_BIRTH_CHILD_#{child_num}" => child_place_of_birth(child),
        "CHILD_#{child_num}_18_TO_23" => child_status.include?('18-23_YEARS_OLD'),
        "CHILD_#{child_num}_DISABLED" => child_status.include?('SERIOUSLY_DISABLED'),
        "CHILD_#{child_num}_PREV_MARRIED" => child_status.include?('CHILD_PREVIOUSLY_MARRIED'),
        "CB_CHILD#{child_num}_LIVE_WITH_OTHERS" => child_status.include?('DOES_NOT_LIVE_WITH_SPOUSE'),
        "AMNT_CONTRIBUTE_TO_CHILD_#{child_num}" => format_currency(child['childSupport'])
      }
    )
  end

  def child_place_of_birth(child)
    # V2025 sends childPlaceOfBirth as a string; V2022 sent birthPlace as a hash.
    if child['childPlaceOfBirth'].is_a?(String)
      child['childPlaceOfBirth'].presence
    elsif child['birthPlace'].is_a?(Hash)
      bp = child['birthPlace']
      [bp['city'], bp['state'], bp['country']].compact.join(', ').presence
    end
  end
end
