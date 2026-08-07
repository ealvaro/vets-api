# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class VBSBuilder
      def initialize(vbs_service:)
        @vbs_service = vbs_service
      end

      def build_facility_accounts
        grouped = statements.group_by { |statement| get_station_id(statement) }.except(nil)
        grouped.map do |station_id, station_statements|
          latest = station_statements.max_by { |statement| statement_date_for(statement) }
          build_account(station_id, latest)
        end
      end

      def build_facility_account(station_id)
        # TODO: latest-statement snapshot for station_id
      end

      private

      def statements
        response = @vbs_service.get_copays
        raise MedicalCopays::VBS::Service::ServiceError unless response[:status] == 200

        response[:data]
      end

      def build_account(station_id, statement)
        statement_date = statement_date_for(statement)
        due_date = statement_date + FacilityAccount::PAYMENT_DUE_DAYS
        current_balance = statement['pHNewBalance'].to_f

        FacilityAccount.new(
          station_id:,
          facility_name: statement.dig('station', 'facilitYDesc'),
          is_cerner: true,
          current_balance:,
          past_due_balance: past_due_balance(statement, due_date, current_balance),
          statement_date:,
          due_date:
        )
      end

      def past_due_balance(statement, due_date, current_balance)
        return current_balance if due_date < Time.zone.today

        previous_balance = BigDecimal(statement['pHPrevBal'].to_f.to_s)
        payments = BigDecimal(statement['pHTotCredits'].to_f.to_s).abs

        # Payment application is FIFO, so payments land on previous_balance before this cycle's
        # charges. A large enough payment clears the carry and spills onto the current charges,
        # leaving nothing past due rather than a negative.
        unpaid_previous_balance = previous_balance - payments
        return 0.0 if unpaid_previous_balance.negative?

        unpaid_previous_balance.to_f
      end

      def statement_date_for(statement)
        Date.strptime(statement['pSStatementDate'], '%m%d%Y')
      end

      def get_station_id(statement)
        statement['pSFacilityNum'].to_s.slice(FacilityAccount::STATION_ID_PATTERN)
      end
    end
  end
end
