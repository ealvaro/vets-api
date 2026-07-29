# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::VBSBuilder do
  subject(:builder) { described_class.new(vbs_service:) }

  let(:vbs_service) { instance_double(MedicalCopays::VBS::Service) }

  # Values mirror vets-api-mockdata vbs/index/default.yml
  def statement_hash(**overrides)
    {
      'pSFacilityNum' => '757',
      'pSStatementDate' => '12112025',
      'pHNewBalance' => 105.24,
      'pHPrevBal' => 103.21,
      'pHTotCredits' => 0,
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
