# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::FacilityAccountSerializer do
  def facility_account(**overrides)
    MedicalCopays::FacilityAccounts::FacilityAccount.new(
      { station_id: '757', is_cerner: false, current_balance: 0.0 }.merge(overrides)
    )
  end

  def serialize(facilities, total_current_balance: 0.0)
    described_class.index(total_current_balance:, facilities:)
  end

  describe '.show' do
    it 'camelizes every key without the index envelope' do
      result = described_class.show(facility_account)

      expect(result.keys).to contain_exactly(
        'stationId', 'facilityName', 'city', 'isCerner', 'accountNumber', 'currentBalance',
        'pastDueBalance', 'statementDate', 'dueDate', 'transactions'
      )
    end

    it 'camelizes keys nested below the transaction, not just the transaction itself' do
      account = facility_account(
        transactions: [{ billing_reference: 'H1234',
                         medication: { medication_name: 'ATORVASTATIN', days_supply: 30 } }]
      )

      transaction = described_class.show(account)['transactions'].first

      expect(transaction.keys).to contain_exactly('billingReference', 'medication')
      expect(transaction['medication'].keys).to contain_exactly('medicationName', 'daysSupply')
    end

    it 'emits the detail-only attributes the index leaves null' do
      account = facility_account(account_number: '123456', statement_date: Date.new(2025, 12, 11))

      result = described_class.show(account)

      expect(result['accountNumber']).to eq('123456')
      expect(result['statementDate']).to eq('2025-12-11')
    end

    it 'omits model attributes that are not on the allowlist' do
      stub_const("#{described_class}::ATTRIBUTES", %i[station_id current_balance].freeze)

      expect(described_class.show(facility_account).keys).to contain_exactly('stationId', 'currentBalance')
    end
  end

  it 'camelizes the envelope and every facility key' do
    result = serialize([facility_account])

    expect(result.keys).to contain_exactly('totalCurrentBalance', 'facilities')
    expect(result['facilities'].first.keys).to contain_exactly(
      'stationId', 'facilityName', 'city', 'isCerner', 'accountNumber', 'currentBalance',
      'pastDueBalance', 'statementDate', 'dueDate', 'transactions'
    )
  end

  it 'camelizes nested transaction keys' do
    account = facility_account(
      transactions: [{ billing_reference: 'B1', provider_name: 'Dr X', date_posted: '2025-12-01' }]
    )

    transaction = serialize([account])['facilities'].first['transactions'].first

    expect(transaction.keys).to contain_exactly('billingReference', 'providerName', 'datePosted')
  end

  it 'emits dates as ISO strings and keeps unset attributes null' do
    account = facility_account(
      facility_name: 'Chalmers P. Wylie Veterans Outpatient Clinic', city: 'Columbus',
      current_balance: 105.24, past_due_balance: 0.0,
      statement_date: Date.new(2025, 12, 11), due_date: Date.new(2026, 1, 5)
    )

    expect(serialize([account], total_current_balance: 105.24)).to eq(
      'totalCurrentBalance' => 105.24,
      'facilities' => [
        {
          'stationId' => '757',
          'facilityName' => 'Chalmers P. Wylie Veterans Outpatient Clinic',
          'city' => 'Columbus',
          'isCerner' => false,
          'accountNumber' => nil,
          'currentBalance' => 105.24,
          'pastDueBalance' => 0.0,
          'statementDate' => '2025-12-11',
          'dueDate' => '2026-01-05',
          'transactions' => nil
        }
      ]
    )
  end

  it 'omits model attributes that are not on the index allowlist' do
    stub_const("#{described_class}::ATTRIBUTES", %i[station_id current_balance].freeze)

    expect(serialize([facility_account])['facilities'].first.keys).to contain_exactly(
      'stationId', 'currentBalance'
    )
  end

  it 'returns an empty facilities list when the user has no accounts' do
    expect(serialize([])).to eq('totalCurrentBalance' => 0.0, 'facilities' => [])
  end
end
