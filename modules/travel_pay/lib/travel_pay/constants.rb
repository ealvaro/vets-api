# frozen_string_literal: true

module TravelPay
  module Constants
    # Usage:
    # TravelPay::Constants::BASE_EXPENSE_PATHS[:meal]
    BASE_EXPENSE_PATHS = {
      airtravel: 'api/v1/expenses/airtravel',
      commoncarrier: 'api/v1/expenses/commoncarrier',
      lodging: 'api/v1/expenses/lodging',
      meal: 'api/v1/expenses/meal',
      mileage: 'api/v2/expenses/mileage',
      parking: 'api/v1/expenses/parking',
      other: 'api/v1/expenses/other',
      toll: 'api/v1/expenses/toll'
    }.freeze

    # Usage:
    # TravelPay::Constants::EXPENSE_TYPES[:parking]
    EXPENSE_TYPES = {
      airtravel: 'airtravel',
      commoncarrier: 'commoncarrier',
      lodging: 'lodging',
      meal: 'meal',
      mileage: 'mileage',
      parking: 'parking',
      other: 'other',
      toll: 'toll'
    }.freeze

    # Usage:
    # TravelPay::Constants::TRIP_TYPES[:one_way]
    # TODO: After 8/20/26 TP API release, remove TRIP_TYPES and rename SPACED_TRIP_TYPES to TRIP_TYPES.
    TRIP_TYPES = {
      one_way: 'OneWay',
      round_trip: 'RoundTrip',
      unspecified: 'Unspecified'
    }.freeze

    # Spaced equivalents accepted by the updated BTSSS API (travel_pay_api_spaced_keys).
    SPACED_TRIP_TYPES = {
      one_way: 'One Way',
      round_trip: 'Round Trip',
      unspecified: 'Unspecified'
    }.freeze

    # TODO: After 8/20/26 TP API release, remove ALL_TRIP_TYPE_VALUES and validate against TRIP_TYPES.values.
    ALL_TRIP_TYPE_VALUES = (TRIP_TYPES.values + SPACED_TRIP_TYPES.values).uniq.freeze

    # Maps unspaced trip type values to their spaced equivalents for BTSSS API submission.
    # TODO: After 8/20/26 TP API release, remove this mapping.
    TRIP_TYPE_TO_SPACED = TRIP_TYPES.each_with_object({}) do |(key, val), hash|
      hash[val] = SPACED_TRIP_TYPES[key]
    end.freeze

    # Usage:
    # TravelPay::Constants::COMMON_CARRIER_EXPLANATIONS[:privately_owned_vehicle_not_available]
    COMMON_CARRIER_EXPLANATIONS = {
      privately_owned_vehicle_not_available: 'Privately Owned Vehicle Not Available',
      medically_indicated: 'Medically Indicated',
      other: 'Other',
      unspecified: 'Unspecified'
    }.freeze

    # Usage:
    # TravelPay::Constants::COMMON_CARRIER_TYPES[:bus]
    COMMON_CARRIER_TYPES = {
      bus: 'Bus',
      subway: 'Subway',
      taxi: 'Taxi',
      train: 'Train',
      other: 'Other'
    }.freeze

    # Usage:
    # TravelPay::Constants::UUID_REGEX.match?(uuid_string)
    UUID_REGEX = /\A[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[89ABCD][0-9A-F]{3}-[0-9A-F]{12}\z/i
  end
end
