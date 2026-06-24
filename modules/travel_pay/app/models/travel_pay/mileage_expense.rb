# frozen_string_literal: true

require_relative '../../../lib/travel_pay/constants'

module TravelPay
  class MileageExpense < BaseExpense
    attribute :trip_type, :string
    attribute :start_address
    attribute :end_address

    attr_accessor :user

    validates :trip_type, presence: true, inclusion: { in: TravelPay::Constants::TRIP_TYPES.values }

    ADDRESS_PARAMS = %i[address_line1 address_line2 city state_code postal_code].freeze

    # Returns the list of permitted parameters for mileage expenses
    # Overrides base params completely since mileage doesn't use description or cost_requested
    #
    # @return [Array<Symbol>] list of permitted parameter names
    def self.permitted_params(user = nil)
      base = %i[purchase_date trip_type description]
      if Flipper.enabled?(:travel_pay_enable_one_way_mileage, user)
        base + [{ start_address: ADDRESS_PARAMS, end_address: ADDRESS_PARAMS }]
      else
        base
      end
    end

    # Returns the expense type for mileage expenses
    #
    # @return [String] the expense type
    def expense_type
      TravelPay::Constants::EXPENSE_TYPES[:mileage]
    end

    # Returns a hash of parameters formatted for the service layer
    # Overrides base implementation since mileage has different params
    #
    # @return [Hash] parameters formatted for the service
    def to_service_params
      params = {
        'expense_type' => expense_type,
        'purchase_date' => format_date(purchase_date),
        'trip_type' => trip_type,
        'description' => description
      }
      params['claim_id'] = claim_id if claim_id.present?
      if Flipper.enabled?(:travel_pay_enable_one_way_mileage, user)
        params['start_address'] = start_address.to_h if start_address.present?
        params['end_address'] = end_address.to_h if end_address.present?
      end
      params
    end
  end
end
