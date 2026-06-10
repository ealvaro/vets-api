# frozen_string_literal: true

# Helper for loading and transforming the form_526_json_api.json fixture.
class Form526FixtureHelper
  FORM_526_FIXTURE_PATH = Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                          'disability_compensation', 'form_526_json_api.json').freeze

  attr_reader :data

  def initialize
    @data = JSON.parse(FORM_526_FIXTURE_PATH.read)
  end

  # Returns the nested attributes hash from data.attributes.
  def attributes
    @data.dig('data', 'attributes')
  end

  # Sets changeOfAddress beginDate and endDate to future values.
  def future_change_of_address_dates
    dates = @data.dig('data', 'attributes', 'changeOfAddress', 'dates')
    if dates
      dates['beginDate'] = 2.months.from_now.strftime('%Y-%m-%d')
      dates['endDate'] = 6.months.from_now.strftime('%Y-%m-%d')
    end
    self
  end
end
