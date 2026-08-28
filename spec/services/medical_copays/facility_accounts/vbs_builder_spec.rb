# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::VBSBuilder do
  subject(:builder) { described_class.new(vbs_service:) }

  let(:vbs_service) { instance_double(MedicalCopays::VBS::Service) }

  # Values mirror vets-api-mockdata vbs/index/default.yml
  def statement_hash(**overrides)
    {
      'id' => '0100e6ef-4de8-48b1-a5f5-e50ac86698ab',
      'pSFacilityNum' => '757',
      'pSStatementDate' => '12112025',
      'pHNewBalance' => 105.24,
      'pHPrevBal' => 103.21,
      'pHTotCredits' => 0,
      'pHTotCharges' => 2.03,
      'accountNumber' => '757 0000 0001 97750 SMITH',
      'pHAddress1' => '7780 RED MAPLE CT',
      'pHAddress2' => nil,
      'pHAddress3' => nil,
      'pHCity' => 'HUBER HEIGHTS',
      'pHState' => 'OH',
      'pHZipCdeOutput' => '45424-1234',
      'details' => [],
      'station' => station_hash
    }.merge(overrides.transform_keys(&:to_s))
  end

  # The station table entry VBS nests under every statement, carrying the return address.
  def station_hash
    {
      'facilitYDesc' => 'CHALMERS P WYLIE VA ACC (757)',
      'staTAddress1' => '420 N JAMES RD',
      'staTAddress2' => nil,
      'staTAddress3' => nil,
      'city' => 'COLUMBUS',
      'state' => 'OH',
      'ziPCdeOutput' => '43219-1834'
    }
  end

  # Mirrors the shape of a printed statement. Named individually so each row's expected
  # classification is visible without working it out from the field values.

  # Interest is charged per cycle rather than per event, so it carries no posted date.
  # All 36 interest rows in the Stage payload are undated.
  def interest_charge
    {
      'pDDatePosted' => nil,
      'pDTransDescOutput' => 'INTEREST/ADM. CHARGE (Int:0.10 Adm:1.93 Other:0.00)',
      'pDTransAmt' => 2.03,
      'pDRefNo' => nil
    }
  end

  def pharmacy_charge
    {
      'pDDatePosted' => '11202025',
      'pDTransDescOutput' => 'COPAY RX#20981144E FILL DATE: 11/20/2025',
      'pDTransAmt' => 8,
      'pDRefNo' => '402-K30G0H8'
    }
  end

  # Wraps under the charge above it, carrying that charge's drug and quantity.
  def continuation_line
    {
      'pDDatePosted' => nil,
      'pDTransDescOutput' => '&nbsp;&nbsp;&nbsp;DRUG:LISINOPRIL 10MG TAB  DAYS:30  QTY:30',
      'pDTransAmt' => 0,
      'pDRefNo' => nil
    }
  end

  # Shares the pharmacy charge's bill number, since a payment settles a bill.
  def payment
    {
      'pDDatePosted' => '11262025',
      'pDTransDescOutput' => 'PAYMENT POSTED ON 11/26/2025',
      'pDTransAmt' => -8,
      'pDRefNo' => '402-K30G0H8'
    }
  end

  # EHRM/CCPC send the carry forward as its own detail row rather than only a header total.
  def balance_forward_charge
    {
      'pDDatePosted' => nil,
      'pDTransDescOutput' => 'Outpatient-Family Medicine(BAL FWD)',
      'pDTransAmt' => 15,
      'pDRefNo' => '21709831'
    }
  end

  describe '#build_facility_accounts' do
    let(:statements) { [statement_hash] }
    let(:accounts) { builder.build_facility_accounts }

    before do
      allow(vbs_service).to receive(:get_copays).and_return({ data: statements, status: 200 })
      Timecop.freeze(Time.zone.local(2025, 12, 15))
    end

    after { Timecop.return }

    it 'builds a facility account per station from the statement balance' do
      expect(accounts.size).to eq(1)
      expect(accounts.first).to have_attributes(station_id: '757', current_balance: 105.24)
    end

    it 'names the facility from the station description' do
      expect(accounts.first.facility_name).to eq('CHALMERS P WYLIE VA ACC (757)')
    end

    it 'takes the city from the station block' do
      expect(accounts.first.city).to eq('COLUMBUS')
    end

    it 'marks accounts cerner, since the VBS branch is the cerner branch' do
      expect(accounts.first.is_cerner).to be(true)
    end

    it 'parses the statement date and dues it 25 days later' do
      expect(accounts.first.statement_date).to eq(Date.new(2025, 12, 11))
      expect(accounts.first.due_date).to eq(Date.new(2026, 1, 5))
    end

    context 'when a facility has statements from several cycles' do
      let(:statements) do
        [
          statement_hash(pSStatementDate: '10112025', pHPrevBal: 0, pHNewBalance: 50.0),
          statement_hash(pSStatementDate: '11112025', pHPrevBal: 50.0, pHNewBalance: 75.0),
          statement_hash(pSStatementDate: '12112025', pHPrevBal: 75.0, pHNewBalance: 105.24)
        ]
      end

      it 'snapshots the latest statement, whose balance already carries the earlier cycles' do
        expect(accounts.size).to eq(1)
        expect(accounts.first).to have_attributes(
          current_balance: 105.24,
          past_due_balance: 75.0,
          statement_date: Date.new(2025, 12, 11)
        )
      end
    end

    context 'when statements span divisions of one parent station' do
      let(:statements) do
        [
          statement_hash(pSFacilityNum: '640', pSStatementDate: '11112025', pHNewBalance: 10.0),
          statement_hash(pSFacilityNum: '640A0', pHNewBalance: 20.0)
        ]
      end

      it 'merges divisions into the parent station and keeps the latest statement' do
        expect(accounts.map(&:station_id)).to contain_exactly('640')
        expect(accounts.first.current_balance).to eq(20.0)
      end
    end

    describe 'past due balance' do
      it 'reports the carried balance while the statement is not yet due' do
        expect(accounts.first.past_due_balance).to eq(103.21)
      end

      context 'when credits cover the carried balance' do
        let(:statements) do
          [statement_hash(pHNewBalance: 15.0, pHPrevBal: 135.0, pHTotCredits: -135.0)]
        end

        it 'reports nothing past due, reading credits by magnitude' do
          expect(accounts.first.past_due_balance).to eq(0.0)
        end
      end

      context 'when credits cover part of the carried balance' do
        let(:statements) do
          [statement_hash(pHPrevBal: 105.24, pHTotCredits: -15.15)]
        end

        it 'reports the uncovered remainder without float drift' do
          expect(accounts.first.past_due_balance).to eq(90.09)
        end
      end

      context 'when credits exceed the carried balance' do
        let(:statements) do
          [statement_hash(pHNewBalance: 2.03, pHPrevBal: 100.0, pHTotCredits: -150.0)]
        end

        it 'reports nothing past due, since the overpayment spilled onto the current charges' do
          expect(accounts.first.past_due_balance).to eq(0.0)
        end
      end

      context 'when the due date has passed' do
        before { Timecop.freeze(Time.zone.local(2026, 1, 6)) }

        it 'reports the whole balance as past due, not just the carried portion' do
          expect(accounts.first.past_due_balance).to eq(105.24)
        end

        context 'and the facility has earlier cycles that are also overdue' do
          let(:statements) do
            [
              statement_hash(pSStatementDate: '10112025', pHPrevBal: 0, pHNewBalance: 50.0),
              statement_hash(pSStatementDate: '11112025', pHPrevBal: 50.0, pHNewBalance: 75.0),
              statement_hash(pSStatementDate: '12112025', pHPrevBal: 75.0, pHNewBalance: 105.24)
            ]
          end

          it 'tiers against the latest statement rather than an earlier one' do
            expect(accounts.first.past_due_balance).to eq(105.24)
          end
        end
      end
    end

    context 'when a statement has no facility number' do
      let(:statements) { [statement_hash, statement_hash(pSFacilityNum: nil, pHNewBalance: 50.0)] }

      it 'excludes statements that cannot resolve to a station' do
        expect(accounts.map(&:station_id)).to contain_exactly('757')
      end
    end

    context 'when the user has no statements' do
      let(:statements) { [] }

      it 'returns no accounts' do
        expect(accounts).to eq([])
      end
    end

    context 'when VBS returns a non-200' do
      before do
        allow(vbs_service).to receive(:get_copays).and_return({ data: { message: 'Bad request' }, status: 400 })
      end

      it 'raises rather than reporting the user has no copays' do
        expect { accounts }.to raise_error(MedicalCopays::VBS::Service::ServiceError)
      end
    end
  end

  describe '#build_facility_account' do
    let(:details_fixture) { [interest_charge, pharmacy_charge, continuation_line, payment] }

    let(:statements) do
      [
        statement_hash(pSStatementDate: '11112025', pHNewBalance: 75.0),
        statement_hash(pSStatementDate: '12112025', pHNewBalance: 105.24, details: details_fixture),
        statement_hash(pSFacilityNum: '668', pHNewBalance: 46.0)
      ]
    end

    before do
      allow(vbs_service).to receive(:get_copays).and_return({ data: statements, status: 200 })
      Timecop.freeze(Time.zone.local(2025, 12, 15))
    end

    after { Timecop.return }

    it 'builds the requested facility from its latest statement' do
      expect(builder.build_facility_account('757')).to have_attributes(
        station_id: '757',
        account_number: '757 0000 0001 97750 SMITH',
        current_balance: 105.24,
        statement_date: Date.new(2025, 12, 11),
        due_date: Date.new(2026, 1, 5)
      )
    end

    it 'returns nil when the requested facility is absent' do
      expect(builder.build_facility_account('999')).to be_nil
    end

    describe 'transactions' do
      subject(:transactions) { builder.build_facility_account('757').transactions }

      # Ids are a position within the statement that carries the row, so they are prefixed
      # with that statement's UUID rather than the station.
      let(:statement_id) { '0100e6ef-4de8-48b1-a5f5-e50ac86698ab' }

      it 'maps the latest statement details newest first, undated last' do
        expect(transactions).to eq(
          [
            {
              id: "#{statement_id}-3",
              type: 'payment',
              date: '2025-11-26',
              description: 'PAYMENT POSTED ON 11/26/2025',
              amount: 8.0,
              billing_reference: '402-K30G0H8',
              provider: nil,
              medication: nil
            },
            {
              id: "#{statement_id}-2",
              type: 'charge',
              date: '2025-11-20',
              description: 'COPAY RX#20981144E FILL DATE: 11/20/2025',
              amount: 8.0,
              billing_reference: '402-K30G0H8',
              provider: nil,
              medication: nil
            },
            {
              id: "#{statement_id}-1",
              type: 'charge',
              date: nil,
              description: 'INTEREST/ADM. CHARGE (Int:0.10 Adm:1.93 Other:0.00)',
              amount: 2.03,
              billing_reference: nil,
              provider: nil,
              medication: nil
            }
          ]
        )
      end

      it 'drops the indented lines that wrap under a printed charge' do
        descriptions = transactions.map { |transaction| transaction[:description] }

        expect(descriptions).to all(satisfy { |description| !description.start_with?('&nbsp;') })
      end

      it 'reads payments from the rendered description, since sign alone does not identify one' do
        payments = transactions.select { |transaction| transaction[:type] == 'payment' }

        expect(payments).to contain_exactly(
          hash_including(description: 'PAYMENT POSTED ON 11/26/2025', amount: 8.0)
        )
      end

      context 'when a charge was cancelled' do
        let(:statements) do
          [
            statement_hash(
              pSStatementDate: '12112025',
              details: [
                {
                  'pDDatePosted' => '07092025',
                  'pDTransDescOutput' => 'OUTPATIENT CARE VISIT DATE: 06/08/2025',
                  'pDTransAmt' => 50,
                  'pDRefNo' => '516-K00V8T8'
                },
                {
                  'pDDatePosted' => '07092025',
                  'pDTransDescOutput' => 'OUTPATIENT CARE',
                  'pDTransAmt' => -50,
                  'pDRefNo' => '516-K00V8T8'
                }
              ]
            )
          ]
        end

        it 'reports the reversing row as a credit for the amount it cancels' do
          expect(transactions).to contain_exactly(
            hash_including(
              type: 'charge',
              description: 'OUTPATIENT CARE VISIT DATE: 06/08/2025',
              amount: 50.0
            ),
            hash_including(type: 'credit', description: 'OUTPATIENT CARE', amount: 50.0)
          )
        end
      end

      context 'when a row has an unparseable posted date' do
        let(:statements) do
          [
            statement_hash(
              pSStatementDate: '12112025',
              details: [
                {
                  'pDDatePosted' => '99999999',
                  'pDTransDescOutput' => 'OUTPATIENT CARE VISIT DATE: 06/08/2025',
                  'pDTransAmt' => 50,
                  'pDRefNo' => '516-K00V8T8'
                }
              ]
            )
          ]
        end

        it 'reports no date rather than raising' do
          expect(transactions).to contain_exactly(
            hash_including(type: 'charge', date: nil, amount: 50.0)
          )
        end
      end

      context 'when the statement has no details' do
        let(:statements) { [statement_hash(pSStatementDate: '12112025', details: nil)] }

        it 'returns no transactions rather than raising' do
          expect(transactions).to eq([])
        end
      end

      context 'when a negative row carries no bill number or posted date' do
        let(:statements) do
          [
            statement_hash(
              pSStatementDate: '12112025',
              details: [
                {
                  'pDDatePosted' => nil,
                  'pDTransDescOutput' => 'RX CO-PAYMENT/NSC VET',
                  'pDTransAmt' => -5,
                  'pDRefNo' => nil
                }
              ]
            )
          ]
        end

        it 'still reports it as a credit, since the ICD reads any negative that way' do
          expect(transactions).to contain_exactly(
            hash_including(type: 'credit', description: 'RX CO-PAYMENT/NSC VET', amount: 5.0)
          )
        end
      end

      context 'when one bill number spans several lines' do
        let(:statements) do
          [
            statement_hash(
              pSStatementDate: '12112025',
              details: Array.new(3) do |index|
                {
                  'pDDatePosted' => "0#{index + 1}202025",
                  'pDTransDescOutput' => "COPAY RX#10004#{index} FILL DATE: 0#{index + 1}/20/2025",
                  'pDTransAmt' => 8,
                  'pDRefNo' => '516-K10J56V'
                }
              end
            )
          ]
        end

        it 'still gives every transaction a unique id, since the bill number repeats' do
          expect(transactions.map { |transaction| transaction[:billing_reference] }.uniq)
            .to eq(['516-K10J56V'])
          expect(transactions.map { |transaction| transaction[:id] })
            .to contain_exactly("#{statement_id}-1", "#{statement_id}-2", "#{statement_id}-3")
        end
      end
    end
  end

  describe '#build_statements' do
    let(:statements) { [statement_hash] }
    let(:documents) { builder.build_statements('757') }

    before do
      allow(vbs_service).to receive(:get_copays).and_return({ data: statements, status: 200 })
      Timecop.freeze(Time.zone.local(2025, 12, 15))
    end

    after { Timecop.return }

    it 'builds Statement documents, not the FacilityAccount ledger snapshot' do
      expect(documents.first).to be_a(MedicalCopays::FacilityAccounts::Statement)
    end

    it 'maps the identity and header totals from the VBS statement' do
      expect(documents.first).to have_attributes(
        id: '0100e6ef-4de8-48b1-a5f5-e50ac86698ab',
        station_id: '757',
        facility_name: 'CHALMERS P WYLIE VA ACC (757)',
        account_number: '757 0000 0001 97750 SMITH',
        previous_balance: 103.21,
        new_charges: 2.03,
        payments_and_credits: 0.0,
        statement_balance: 105.24
      )
    end

    it 'parses the statement date and computes the pay-by date 25 days later' do
      expect(documents.first.statement_date).to eq(Date.new(2025, 12, 11))
      expect(documents.first.pay_by_date).to eq(Date.new(2026, 1, 5))
    end

    it 'maps the addresses from the station and header, taking the formatted zip' do
      expect(documents.first.facility_address).to eq(
        line1: '420 N JAMES RD', line2: nil, line3: nil,
        city: 'COLUMBUS', state: 'OH', zip: '43219-1834'
      )
      expect(documents.first.recipient_address).to eq(
        line1: '7780 RED MAPLE CT', line2: nil, line3: nil,
        city: 'HUBER HEIGHTS', state: 'OH', zip: '45424-1234'
      )
    end

    context 'when a statement arrives without its station block' do
      let(:statements) { [statement_hash(station: nil)] }

      it 'leaves the return address blank rather than failing the whole request' do
        expect(documents.first.facility_address).to eq(
          line1: nil, line2: nil, line3: nil, city: nil, state: nil, zip: nil
        )
      end
    end

    context 'when the facility has several cycles' do
      let(:statements) do
        [
          statement_hash(pSStatementDate: '10112025'),
          statement_hash(pSStatementDate: '12112025'),
          statement_hash(pSStatementDate: '11112025')
        ]
      end

      it 'returns every statement newest first, unlike the ledger snapshot' do
        expect(documents.map(&:statement_date)).to eq(
          [Date.new(2025, 12, 11), Date.new(2025, 11, 11), Date.new(2025, 10, 11)]
        )
      end
    end

    # Today is frozen at 2025-12-15, so the endpoint's own cutoff is 2025-06-15. The builder
    # applies it whether or not VBS::ResponseData already trimmed the list.
    context 'when VBS returns statements older than six months' do
      let(:statements) do
        [
          statement_hash(pSStatementDate: '05112025'),
          statement_hash(pSStatementDate: '07112025')
        ]
      end

      it 'returns only statements from the most recent six months' do
        expect(documents.map(&:statement_date)).to contain_exactly(Date.new(2025, 7, 11))
      end
    end

    context 'when a statement sits on the six-month cutoff' do
      let(:statements) do
        [
          statement_hash(pSStatementDate: '06152025'),
          statement_hash(pSStatementDate: '06162025')
        ]
      end

      it 'excludes the cutoff date itself and keeps the day after' do
        expect(documents.map(&:statement_date)).to contain_exactly(Date.new(2025, 6, 16))
      end
    end

    # medical_copays_zero_debt appends a placeholder per facility with no debt. It is the
    # shape MedicalCopays::ZeroBalanceStatements#list builds: no id, no account number, no
    # totals, and the station number only under `station`.
    context 'when VBS includes a synthetic zero-balance facility record' do
      let(:zero_balance_record) do
        {
          'pHAmtDue' => 0,
          'pSStatementDate' => Time.zone.today.strftime('%m%d%Y'),
          'station' => { 'facilitYNum' => '757', 'city' => 'COLUMBUS' }
        }
      end
      let(:statements) { [statement_hash, zero_balance_record] }

      it 'excludes the record, since no statement was mailed and no PDF exists' do
        expect(documents.map(&:id)).to contain_exactly('0100e6ef-4de8-48b1-a5f5-e50ac86698ab')
      end
    end

    context 'when a record cannot be dated' do
      let(:statements) do
        [statement_hash, statement_hash(id: 'undateable', pSStatementDate: bad_date)]
      end

      before { allow(Rails.logger).to receive(:warn) }

      [['a malformed', 'NOTADATE'], ['a missing', nil]].each do |description, value|
        context "because #{description} pSStatementDate arrived" do
          let(:bad_date) { value }

          it 'drops that record and still returns the rest' do
            expect(documents.map(&:id)).to contain_exactly('0100e6ef-4de8-48b1-a5f5-e50ac86698ab')
          end

          it 'logs the dropped id, so upstream corruption is not silent' do
            documents

            expect(Rails.logger).to have_received(:warn)
              .with('MedicalCopays::FacilityAccounts undateable statement undateable')
          end
        end
      end
    end

    context 'when statements span other facilities' do
      let(:statements) do
        [statement_hash, statement_hash(id: 'other-facility', pSFacilityNum: '668')]
      end

      it 'drops statements mailed by another station' do
        expect(documents.map(&:id)).to contain_exactly('0100e6ef-4de8-48b1-a5f5-e50ac86698ab')
      end
    end

    context 'when a statement comes from a division of the requested station' do
      let(:statements) do
        [statement_hash, statement_hash(id: 'division-statement', pSFacilityNum: '757A0')]
      end

      it 'keeps it, since divisions collapse to the parent station' do
        expect(documents.map(&:id)).to contain_exactly('0100e6ef-4de8-48b1-a5f5-e50ac86698ab', 'division-statement')
      end
    end

    context 'when the requested facility has no statements' do
      it 'returns an empty array' do
        expect(builder.build_statements('999')).to eq([])
      end
    end

    context 'when VBS returns a non-200' do
      before do
        allow(vbs_service).to receive(:get_copays).and_return({ data: { message: 'Bad request' }, status: 400 })
      end

      it 'raises rather than reporting no statements' do
        expect { documents }.to raise_error(MedicalCopays::VBS::Service::ServiceError)
      end
    end

    describe 'line items' do
      let(:details_fixture) { [interest_charge, pharmacy_charge, balance_forward_charge, continuation_line] }
      let(:statements) { [statement_hash(details: details_fixture)] }
      let(:line_items) { documents.first.line_items }

      # ICD field 17: detail records print in the order they arrive. Unlike transactions[],
      # which the ledger re-sorts newest first, a statement is a frozen document.
      it 'keeps the rows in the order VBS sent them, rather than sorting by date' do
        expect(line_items.map { |item| item[:description] }).to eq(
          [
            'INTEREST/ADM. CHARGE (Int:0.10 Adm:1.93 Other:0.00)',
            'COPAY RX#20981144E FILL DATE: 11/20/2025',
            'Outpatient-Family Medicine(BAL FWD)'
          ]
        )
      end

      it 'maps a dated charge to date, description, reference number and amount' do
        expect(line_items[1]).to eq(
          date: '2025-11-20',
          description: 'COPAY RX#20981144E FILL DATE: 11/20/2025',
          reference_number: '402-K30G0H8',
          amount: 8.0
        )
      end

      # CCPC sends no date for interest and administrative charges, so the row stays undated
      # rather than borrowing the statement date.
      it 'leaves an interest charge undated rather than inventing a date' do
        expect(line_items.first).to eq(
          date: nil,
          description: 'INTEREST/ADM. CHARGE (Int:0.10 Adm:1.93 Other:0.00)',
          reference_number: nil,
          amount: 2.03
        )
      end

      # EHRM/CCPC send the carry as its own detail row. It passes through like any other row;
      # nothing is synthesized from pHPrevBal, and nothing is added when the row is absent.
      it 'passes an existing (BAL FWD) row through as a line item' do
        expect(line_items.last).to eq(
          date: nil,
          description: 'Outpatient-Family Medicine(BAL FWD)',
          reference_number: '21709831',
          amount: 15.0
        )
      end

      it 'drops the indented continuation lines, which are presentation and not rows' do
        expect(line_items.map { |item| item[:description] })
          .not_to include(a_string_starting_with('&nbsp;'))
      end

      it 'carries no type or row id, unlike the live transaction contract' do
        expect(line_items.first.keys).to contain_exactly(:date, :description, :reference_number, :amount)
      end

      context 'when a row is a payment or other credit' do
        let(:details_fixture) { [pharmacy_charge, payment] }

        # ICD field 18: the trailing negative is what marks a payment or other credit, and line
        # items carry no type. Dropping the sign would leave the row indistinguishable from a
        # charge and stop the items reconciling against the header totals.
        it 'keeps the negative sign the mailed statement printed' do
          expect(line_items.last).to eq(
            date: '2025-11-26',
            description: 'PAYMENT POSTED ON 11/26/2025',
            reference_number: '402-K30G0H8',
            amount: -8.0
          )
        end
      end

      context 'when the statement has no details' do
        let(:statements) { [statement_hash(details: nil)] }

        it 'returns no line items rather than raising' do
          expect(line_items).to eq([])
        end
      end
    end
  end

  describe '#get_station_id' do
    it 'reads the station id from the statement facility number' do
      statement = { 'pSFacilityNum' => '757' }

      expect(builder.send(:get_station_id, statement)).to eq('757')
    end

    it 'truncates a division-suffixed facility number to the parent station' do
      statement = { 'pSFacilityNum' => '640A0' }

      expect(builder.send(:get_station_id, statement)).to eq('640')
    end
  end
end
