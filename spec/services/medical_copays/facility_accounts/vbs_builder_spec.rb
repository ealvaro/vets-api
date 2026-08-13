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
      'accountNumber' => '757 0000 0001 97750 SMITH',
      'details' => [],
      'station' => { 'facilitYDesc' => 'CHALMERS P WYLIE VA ACC (757)' }
    }.merge(overrides.transform_keys(&:to_s))
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
    # Mirrors the shape of a printed statement. Named individually so each row's expected
    # classification is visible without working it out from the field values.

    # Interest is charged per cycle rather than per event, so it carries no posted date.
    # All 36 interest rows in the Stage payload are undated.
    let(:interest_charge) do
      {
        'pDDatePosted' => nil,
        'pDTransDescOutput' => 'INTEREST/ADM. CHARGE (Int:0.10 Adm:1.93 Other:0.00)',
        'pDTransAmt' => 2.03,
        'pDRefNo' => nil
      }
    end

    let(:pharmacy_charge) do
      {
        'pDDatePosted' => '11202025',
        'pDTransDescOutput' => 'COPAY RX#20981144E FILL DATE: 11/20/2025',
        'pDTransAmt' => 8,
        'pDRefNo' => '402-K30G0H8'
      }
    end

    # Wraps under the charge above it, carrying that charge's drug and quantity.
    let(:continuation_line) do
      {
        'pDDatePosted' => nil,
        'pDTransDescOutput' => '&nbsp;&nbsp;&nbsp;DRUG:LISINOPRIL 10MG TAB  DAYS:30  QTY:30',
        'pDTransAmt' => 0,
        'pDRefNo' => nil
      }
    end

    # Shares the pharmacy charge's bill number, since a payment settles a bill.
    let(:payment) do
      {
        'pDDatePosted' => '11262025',
        'pDTransDescOutput' => 'PAYMENT POSTED ON 11/26/2025',
        'pDTransAmt' => -8,
        'pDRefNo' => '402-K30G0H8'
      }
    end

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
