# frozen_string_literal: true

require 'travel_pay/constants'

module TravelPay
  module V0
    class ExpensesController < ApplicationController
      include FeatureFlagHelper
      include IdValidation
      include ErrorHandling

      before_action :validate_claim_id!, only: %i[create show]
      before_action :validate_expense_id!, only: %i[destroy show update]
      before_action :validate_expense_type!
      before_action :check_feature_flag

      def show
        monitor.log(:info, 'Travel Pay expense retrieval START')
        monitor.log(:info, <<~LOG_MESSAGE.strip)
          Getting expense of type '#{params[:expense_type]}'
          with ID #{params[:expense_id].slice(0, 8)}
          for claim #{params[:claim_id].slice(0, 8)}
        LOG_MESSAGE

        expense = expense_service.get_expense(params[:expense_type], params[:expense_id])

        monitor.log(:info, 'Travel Pay expense retrieval END')
        monitor.track_request(:info, 'Expense show success', 'travel_pay.expenses.show',
                              tags: ["expense_type:#{params[:expense_type]}", 'result:success'])
        render json: expense, status: :ok
      rescue => e
        monitor.track_request(:warn, 'Expense show failure', 'travel_pay.expenses.show',
                              error: e.message, tags: ["expense_type:#{params[:expense_type]}", 'result:failure'])
        raise
      end

      def create
        monitor.log(:info, 'Travel Pay expense submission START')
        monitor.log(:info,
                    "Creating expense of type '#{params[:expense_type]}' for claim #{params[:claim_id].slice(0, 8)}")
        expense = create_and_validate_expense
        created_expense = expense_service.create_expense(expense_params_for_service(expense))

        monitor.log(:info, 'Travel Pay expense submission END')
        increment_expense_statsd(params[:expense_type], 'success')

        render json: created_expense, status: :created
      rescue
        increment_expense_statsd(params[:expense_type], 'failure')
        raise
      end

      def update
        expense_type = params[:expense_type]
        expense_id = params[:expense_id]
        monitor.log(:info, "Updating expense of type '#{expense_type}' with expense id #{expense_id&.first(8)}")
        expense = create_and_validate_expense
        response_data = expense_service.update_expense(expense_id, expense_type, expense_params_for_service(expense))

        monitor.track_request(:info, 'Expense update success', 'travel_pay.expenses.update',
                              tags: ["expense_type:#{expense_type}", 'result:success'])
        render json: { id: response_data['id'] }, status: :ok
      rescue => e
        monitor.track_request(:warn, 'Expense update failure', 'travel_pay.expenses.update',
                              error: e.message, tags: ["expense_type:#{params[:expense_type]}", 'result:failure'])
        raise
      end

      def destroy
        expense_type = params[:expense_type]
        expense_id = params[:expense_id]

        monitor.log(:info, "Deleting expense of type '#{expense_type}' with expense id #{expense_id&.first(8)}")
        response_data = expense_service.delete_expense(expense_id:, expense_type:)

        monitor.track_request(:info, 'Expense destroy success', 'travel_pay.expenses.destroy',
                              tags: ["expense_type:#{expense_type}", 'result:success'])
        render json: { id: response_data['id'] }, status: :ok
      rescue => e
        monitor.track_request(:warn, 'Expense destroy failure', 'travel_pay.expenses.destroy',
                              error: e.message, tags: ["expense_type:#{params[:expense_type]}", 'result:failure'])
        raise
      end

      private

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def expense_service
        @expense_service ||= TravelPay::ExpensesService.new(auth_manager)
      end

      def increment_expense_statsd(expense_type, result)
        level = result == 'success' ? :info : :warn
        monitor.track_request(level, "Expense create #{result}", 'travel_pay.expenses.create',
                              tags: ["expense_type:#{expense_type}", "result:#{result}"])
      end

      def check_feature_flag
        verify_feature_flag!(
          :travel_pay_enable_complex_claims,
          current_user,
          error_message: 'Travel Pay expense endpoint unavailable per feature toggle'
        )
      end

      def create_and_validate_expense
        expense = build_expense_from_params

        return expense if expense.valid?

        monitor.track_request(:error, "Expense validation failed: #{expense.errors.full_messages}",
                              'travel_pay.expenses.validation_failed')
        raise Common::Exceptions::UnprocessableEntity, detail: expense.errors.full_messages.join(', ')
      end

      def validate_claim_id!
        validate_uuid_exists!(params[:claim_id], 'Claim')
      end

      def validate_expense_id!
        validate_uuid_exists!(params[:expense_id], 'Expense')
      end

      def validate_expense_type!
        raise Common::Exceptions::BadRequest, detail: 'Expense type is required' if params[:expense_type].blank?

        unless valid_expense_types.include?(params[:expense_type])
          raise Common::Exceptions::BadRequest,
                detail: "Invalid expense type. Must be one of: #{valid_expense_types.join(', ')}"
        end
      end

      def validate_expense_id
        raise Common::Exceptions::BadRequest, detail: 'Expense ID is required' if params[:expense_id].blank?

        uuid_all_version_format = /\A[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[89ABCD][0-9A-F]{3}-[0-9A-F]{12}\z/i

        unless uuid_all_version_format.match?(params[:expense_id])
          raise Common::Exceptions::BadRequest.new(
            detail: 'Expense ID is invalid'
          )
        end
      end

      def valid_expense_types
        TravelPay::Constants::BASE_EXPENSE_PATHS.keys.map(&:to_s)
      end

      def build_expense_from_params
        expense_class = expense_class_for_type(params[:expense_type])
        expense_params = permitted_params.to_h

        # Manually extract the 'receipt' object from the raw params, bypassing Strong Params filtering
        expense_params[:receipt] = params[:receipt] if params[:receipt].present?

        # Only add claim_id if it exists in params
        expense_params[:claim_id] = params[:claim_id] if params[:claim_id].present?

        expense = expense_class.new(expense_params)
        expense.user = @current_user if expense.respond_to?(:user=)
        expense
      end

      def expense_class_for_type(expense_type)
        return TravelPay::BaseExpense if expense_type.nil?

        case expense_type.to_sym
        when :airtravel
          TravelPay::FlightExpense
        when :commoncarrier
          TravelPay::CommonCarrierExpense
        when :lodging
          TravelPay::LodgingExpense
        when :meal
          TravelPay::MealExpense
        when :mileage
          TravelPay::MileageExpense
        when :parking
          TravelPay::ParkingExpense
        when :toll
          TravelPay::TollExpense
        else
          # :other or any unknown type defaults to BaseExpense
          TravelPay::BaseExpense
        end
      end

      def permitted_params
        expense_class = expense_class_for_type(params[:expense_type])
        params.permit(*expense_class.permitted_params(@current_user))
      end

      def expense_params_for_service(expense)
        expense.to_service_params
      end
    end
  end
end
