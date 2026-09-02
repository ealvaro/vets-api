# frozen_string_literal: true

module BGSDependents
  class Divorce < Base
    CITY_LENGTH = 30

    def initialize(divorce_info)
      @divorce_info = divorce_info
    end

    def format_info
      {
        divorce_state:,
        divorce_city:,
        divorce_country: @divorce_info.dig('divorce_location', 'location', 'country'),
        marriage_termination_type_code:,
        end_date: format_date(@divorce_info['date']),
        vet_ind: 'N',
        ssn: @divorce_info['ssn'],
        birth_date: @divorce_info['birth_date'],
        type: 'divorce'
      }.merge(@divorce_info['full_name']).with_indifferent_access
    end

    # The BGS API expects the state to be nil if the divorce occurred outside the US,
    # so we check the 'outside_usa' flag in the location data.
    # FE should pass nil for state in this case, but this is a safeguard
    #
    # @return [String, nil] The state where the divorce occurred, or nil if it occurred outside the US.
    def divorce_state
      return if @divorce_info.dig('divorce_location', 'outside_usa')

      @divorce_info.dig('divorce_location', 'location', 'state')
    end

    # BGS expects max of 30 characters
    # try to accommodate international edge cases, eg. "Balneario Barra do Sul/ Santa Catarina"
    def divorce_city
      city = @divorce_info.dig('divorce_location', 'location', 'city')&.to_s
      return unless city
      return city if city.length <= CITY_LENGTH

      city = city.split('/').first.strip
      return city if city.length <= CITY_LENGTH

      city[0...CITY_LENGTH].strip
    end

    def marriage_termination_type_code
      mttc = @divorce_info['reason_marriage_ended']
      mttc == 'Annulment' ? 'Other' : mttc
    end
  end
end
