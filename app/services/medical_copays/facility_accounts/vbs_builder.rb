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
        statement = statements
                    .select { |item| get_station_id(item) == station_id }
                    .max_by { |item| statement_date_for(item) }
        return nil unless statement

        build_account(station_id, statement, include_details: true)
      end

      private

      def statements
        response = @vbs_service.get_copays
        raise MedicalCopays::VBS::Service::ServiceError unless response[:status] == 200

        response[:data]
      end

      def build_account(station_id, statement, include_details: false)
        statement_date = statement_date_for(statement)
        due_date = statement_date + FacilityAccount::PAYMENT_DUE_DAYS
        current_balance = statement['pHNewBalance'].to_f

        attributes = {
          station_id:,
          facility_name: statement.dig('station', 'facilitYDesc'),
          is_cerner: true,
          current_balance:,
          past_due_balance: past_due_balance(statement, due_date, current_balance),
          statement_date:,
          due_date:
        }
        attributes.merge!(detail_attributes(statement)) if include_details

        FacilityAccount.new(attributes)
      end

      def detail_attributes(statement)
        {
          account_number: statement['accountNumber'],
          transactions: build_transactions(statement)
        }
      end

      # Details are the printed statement's lines, not a ledger. A charge that wraps is followed
      # by indented continuation lines (drug, quantity, prescriber), which are presentation, not rows.
      def build_transactions(statement)
        rows = Array(statement['details']).reject { |row| continuation_line?(row) }
        transactions = rows.map.with_index { |row, index| transaction(row, statement['id'], index) }

        transactions.sort_by { |transaction| transaction[:date].to_s }.reverse
      end

      def transaction(row, statement_id, index)
        {
          # pDRefNo is a bill number rather than a line id and repeats across a statement's
          # lines, so ids are a position within the statement that carries the row. Anchoring
          # to the statement UUID rather than the station keeps them distinct across cycles.
          id: "#{statement_id}-#{index + 1}",
          type: transaction_type(row),
          date: transaction_date(row['pDDatePosted']),
          description: row['pDTransDescOutput'],
          amount: row['pDTransAmt'].to_f.abs,
          billing_reference: row['pDRefNo'].presence,
          provider: nil,
          medication: nil
        }
      end

      # ICD field 18 defines a negative amount as "payments or other credits", so once payments
      # are identified by description, whatever negative remains is a credit. In practice that is
      # a reversed charge, printed as its own row negating the charge above it.
      def transaction_type(row)
        return 'payment' if payment_detail?(row)
        return 'credit' if row['pDTransAmt'].to_f.negative?

        'charge'
      end

      def continuation_line?(row)
        row['pDTransDescOutput'].to_s.start_with?('&nbsp;')
      end

      # The ICD documents VBS rewriting "PAYMENT" to "PAYMENT POSTED ON" when it renders a payment
      # detail record. Sign alone cannot classify, since credits are negative too.
      def payment_detail?(row)
        row['pDTransDescOutput'].to_s.start_with?('PAYMENT POSTED ON')
      end

      def transaction_date(posted)
        Date.strptime(posted, '%m%d%Y').iso8601 if posted.present?
      rescue ArgumentError
        nil
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
