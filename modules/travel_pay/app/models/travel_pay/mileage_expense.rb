# frozen_string_literal: true

require_relative '../../../lib/travel_pay/constants'

module TravelPay
  class MileageExpense < BaseExpense
    attribute :trip_type, :string
    attribute :start_address
    attribute :end_address
    attribute :challenge_mileage, :boolean
    attribute :challenge_requested_mileage, :float
    attribute :challenge_reason, :string

    attr_accessor :user

    # TODO: After 8/20/26 TP API release, replace ALL_TRIP_TYPE_VALUES with TRIP_TYPES.values.
    validates :trip_type, presence: true, inclusion: { in: TravelPay::Constants::ALL_TRIP_TYPE_VALUES }

    validates :challenge_requested_mileage,
              presence: true,
              numericality: { greater_than: 0 },
              if: :challenging_mileage?

    validates :challenge_reason,
              presence: true,
              length: { maximum: 2000 },
              if: :challenging_mileage?

    ADDRESS_PARAMS = %i[address_line1 address_line2 city state_code postal_code].freeze

    # Returns the list of permitted parameters for mileage expenses
    # Overrides base params since mileage doesn't use cost_requested, and adds
    # address and challenge mileage fields when one-way mileage is enabled
    #
    # @return [Array<Symbol, Hash>] list of permitted parameter names, including a nested
    #   Hash for start/end addresses when one-way mileage is enabled
    def self.permitted_params(user = nil)
      base = %i[purchase_date trip_type description]
      if Flipper.enabled?(:travel_pay_enable_one_way_mileage, user)
        base + [{ start_address: ADDRESS_PARAMS, end_address: ADDRESS_PARAMS },
                :challenge_mileage, :challenge_requested_mileage, :challenge_reason]
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
        params['challenge_mileage'] = challenge_mileage unless challenge_mileage.nil?
        if challenge_mileage == true
          params['challenge_requested_mileage'] = challenge_requested_mileage if challenge_requested_mileage.present?
          params['challenge_reason'] = challenge_reason if challenge_reason.present?
        end
      end
      params
    end

    private

    def challenging_mileage?
      challenge_mileage == true && Flipper.enabled?(:travel_pay_enable_one_way_mileage, user)
    end
  end
end
