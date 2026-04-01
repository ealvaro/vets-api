# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/disability_compensation_validations_helper'

describe ClaimsApi::DisabilityCompensationValidationsHelper do
  subject { test_class.new }

  let(:test_class) do
    Class.new do
      include ClaimsApi::DisabilityCompensationValidationsHelper

      attr_accessor :form_attributes

      def initialize
        @form_attributes = {}
      end
    end
  end

  describe '#eligible_for_future_end_date?' do
    let(:eligible_max_period) do
      {
        'serviceBranch' => 'Army Reserves',
        'activeDutyBeginDate' => 1.year.ago.to_date.iso8601,
        'activeDutyEndDate' => "#{Time.current.year + 1}-12-20"
      }
    end
    let(:ineligible_max_period) do
      {
        'serviceBranch' => 'Navy',
        'activeDutyBeginDate' => 1.year.ago.to_date.iso8601,
        'activeDutyEndDate' => "#{Time.current.year + 1}-12-20"
      }
    end
    let(:eligible_service_periods) do
      [
        {
          'serviceBranch' => 'Army',
          'activeDutyBeginDate' => 3.years.ago.to_date.iso8601,
          'activeDutyEndDate' => 1.year.ago.to_date.iso8601
        },
        {
          'serviceBranch' => 'Army',
          'activeDutyBeginDate' => 5.years.ago.to_date.iso8601,
          'activeDutyEndDate' => 7.years.ago.to_date.iso8601
        }
      ]
    end

    context 'eligible' do
      it 'if there is a past servicePeriod, the current serviceBranch is Reserves or Guard and end date > 180 days' do
        res = subject.send(:eligible_for_future_end_date?, eligible_max_period, eligible_service_periods)

        expect(res).to be(true)
      end
    end

    context 'ineligible' do
      it 'if the most recent serviceBranch is not Reserves or Guard and end date > 180 days' do
        res = subject.send(:eligible_for_future_end_date?, ineligible_max_period, eligible_service_periods)

        expect(res).to be(false)
      end
    end
  end

  describe '#most_recent_service_branch_is_reserves_or_guard?' do
    context 'when service branch is reserves or guard' do
      it 'returns true for Army Reserves' do
        max_period = { 'serviceBranch' => 'Army Reserves' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(true)
      end

      it 'returns true for Air National Guard' do
        max_period = { 'serviceBranch' => 'Air National Guard' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(true)
      end

      it 'returns true for Army National Guard' do
        max_period = { 'serviceBranch' => 'Army National Guard' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(true)
      end
    end

    context 'when service branch is not reserves or guard' do
      it 'returns false for regular Army' do
        max_period = { 'serviceBranch' => 'Army' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(false)
      end

      it 'returns false for Navy' do
        max_period = { 'serviceBranch' => 'Navy' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(false)
      end

      it 'returns false for blank service branch' do
        max_period = { 'serviceBranch' => '' }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(false)
      end

      it 'returns false for nil service branch' do
        max_period = { 'serviceBranch' => nil }
        expect(subject.send(:most_recent_service_branch_is_reserves_or_guard?, max_period)).to be(false)
      end
    end
  end

  describe '#past_service_period?' do
    context 'when there are past service periods' do
      it 'returns true when at least one period has past end date' do
        service_periods = [
          { 'activeDutyEndDate' => 1.year.ago.to_date.iso8601 },
          { 'activeDutyEndDate' => 1.year.from_now.to_date.iso8601 }
        ]
        expect(subject.send(:past_service_period?, service_periods)).to be(true)
      end
    end

    context 'when there are no past service periods' do
      it 'returns false when all periods have future end dates' do
        service_periods = [
          { 'activeDutyEndDate' => 1.year.from_now.to_date.iso8601 },
          { 'activeDutyEndDate' => 2.years.from_now.to_date.iso8601 }
        ]
        expect(subject.send(:past_service_period?, service_periods)).to be(false)
      end

      it 'returns false when service periods is empty' do
        expect(subject.send(:past_service_period?, [])).to be(false)
      end

      it 'returns false when service periods is nil' do
        expect(subject.send(:past_service_period?, nil)).to be(false)
      end

      it 'returns false when end dates are blank' do
        service_periods = [
          { 'activeDutyEndDate' => '' },
          { 'activeDutyEndDate' => nil }
        ]
        expect(subject.send(:past_service_period?, service_periods)).to be(false)
      end
    end
  end

  describe '#flatten_disabilities' do
    context 'when disabilities have secondary disabilities' do
      it 'flattens primary and secondary disabilities into one array' do
        disabilities = [
          {
            'disabilityActionType' => 'NEW',
            'name' => 'Primary 1',
            'secondaryDisabilities' => [
              { 'disabilityActionType' => 'NEW', 'name' => 'Secondary 1' },
              { 'disabilityActionType' => 'NEW', 'name' => 'Secondary 2' }
            ]
          },
          {
            'disabilityActionType' => 'NEW',
            'name' => 'Primary 2'
          }
        ]

        result = subject.send(:flatten_disabilities, disabilities)
        expect(result.length).to eq(4)
        expect(result.map { |d| d['name'] }).to contain_exactly('Primary 1', 'Secondary 1', 'Secondary 2', 'Primary 2')
      end
    end

    context 'when disabilities have NONE action type' do
      it 'excludes primary disabilities with NONE action type' do
        disabilities = [
          {
            'disabilityActionType' => 'NONE',
            'name' => 'Should be excluded',
            'secondaryDisabilities' => [
              { 'disabilityActionType' => 'NEW', 'name' => 'Secondary 1' }
            ]
          },
          {
            'disabilityActionType' => 'NEW',
            'name' => 'Should be included'
          }
        ]

        result = subject.send(:flatten_disabilities, disabilities)
        expect(result.length).to eq(2)
        expect(result.map { |d| d['name'] }).to contain_exactly('Secondary 1', 'Should be included')
      end
    end

    context 'when disabilities array is empty' do
      it 'returns empty array' do
        result = subject.send(:flatten_disabilities, [])
        expect(result).to eq([])
      end
    end
  end

  describe '#date_is_valid?' do
    context 'when date is valid' do
      it 'returns true for valid YYYY-MM-DD date' do
        expect(subject.send(:date_is_valid?, '2020-01-01', 'testDate', true)).to be(true)
      end

      it 'returns true for valid YYYY date if full date is not required' do
        expect(subject.send(:date_is_valid?, '2020', 'testDate')).to be(true)
      end

      it 'returns true for valid YYYY-MM date' do
        expect(subject.send(:date_is_valid?, '2020-01', 'testDate')).to be(true)
      end

      it 'returns true for leap year date' do
        expect(subject.send(:date_is_valid?, '2020-02-29', 'testDate', true)).to be(true)
      end

      it 'returns true for claimDates with ISO8601 timestamp' do
        expect(subject.send(:date_is_valid?, '2020-01-01T12:00:00Z', 'claimDate', true)).to be(true)
      end
    end

    context 'when date is invalid' do
      it 'returns false for blank date' do
        expect(subject.send(:date_is_valid?, '', 'testDate')).to be(false)
      end

      it 'returns false for nil date' do
        expect(subject.send(:date_is_valid?, nil, 'testDate')).to be(false)
      end

      it 'returns false when full date is required and the format is not YYYY-MM-DD' do
        expect(subject.send(:date_is_valid?, '01-01-2020', 'testDate', true)).to be(false)
      end

      it 'returns false when the date is a partial date and the full date is required' do
        expect(subject.send(:date_is_valid?, '2020-01', 'testDate', true)).to be(false)
      end

      it 'returns false for invalid date like February 30th' do
        expect(subject.send(:date_is_valid?, '2020-02-30', 'testDate', true)).to be(false)
      end

      it 'returns false for non-leap year February 29th' do
        expect(subject.send(:date_is_valid?, '2021-02-29', 'testDate', true)).to be(false)
      end

      it 'returns false for ISO 8601 timestamps for fields that are not claimDate' do
        expect(subject.send(:date_is_valid?, '2020-01-01T12:00:00Z', 'testDate', true)).to be(false)
      end

      it 'logs errors for invalid dates except claimDate' do
        expect(subject.send(:date_is_valid?, 'invalid-date', 'testDate')).to be(false)
        expect(subject.errors_array.length).to eq(1)
        expect(subject.errors_array.first[:detail]).to eq('invalid-date is not a valid date.')
        expect(subject.errors_array.first[:source]).to eq('data/attributes/testDate')
      end

      it 'does not log errors for invalid claimDate' do
        expect(subject.send(:date_is_valid?, 'invalid-date', 'claimDate')).to be(false)
        expect(subject.errors_array).to be_empty
      end
    end

    context 'when date is claimDate' do
      it 'allows invalid claimDate without collecting error' do
        expect(subject.send(:date_is_valid?, 'invalid-date', 'claimDate')).to be(false)
        expect(subject.errors_array).to be_empty
      end
    end
  end

  describe '#collect_date_error' do
    it 'adds date error to errors array' do
      subject.send(:collect_date_error, '2020-13-01', 'testDate')

      expect(subject.errors_array.length).to eq(1)
      expect(subject.errors_array.first[:detail]).to eq('2020-13-01 is not a valid date.')
      expect(subject.errors_array.first[:source]).to eq('data/attributes/testDate')
    end
  end

  describe '#errors_array' do
    it 'initializes empty array' do
      expect(subject.errors_array).to eq([])
    end

    it 'returns same array on multiple calls' do
      first_call = subject.errors_array
      second_call = subject.errors_array
      expect(first_call).to be(second_call)
    end
  end

  describe '#collect_error_messages' do
    context 'with default parameters' do
      it 'adds error with default values to errors array' do
        subject.send(:collect_error_messages)

        error = subject.errors_array.first
        expect(error[:detail]).to eq('Missing or invalid attribute')
        expect(error[:source]).to eq('/')
        expect(error[:title]).to eq('Unprocessable Entity')
        expect(error[:status]).to eq('422')
      end
    end

    context 'with custom parameters' do
      it 'adds error with custom values to errors array' do
        subject.send(
          :collect_error_messages,
          detail: 'Custom error message',
          source: 'data/attributes/customField',
          title: 'Custom Title',
          status: '400'
        )

        error = subject.errors_array.first
        expect(error[:detail]).to eq('Custom error message')
        expect(error[:source]).to eq('data/attributes/customField')
        expect(error[:title]).to eq('Custom Title')
        expect(error[:status]).to eq('400')
      end
    end
  end

  describe '#claim_date' do
    let(:form_attributes) { {} }

    before do
      subject.form_attributes = form_attributes
    end

    it 'returns the claimDate if it is a valid date' do
      form_attributes['claimDate'] = '2020-01-01'
      expect(subject.claim_date).to eq(Date.parse('2020-01-01'))
    end

    it 'returns the current date if claimDate is blank' do
      form_attributes['claimDate'] = ''
      expect(subject.claim_date).to eq(Date.current)
    end

    it 'returns the current date if claimDate is invalid' do
      form_attributes['claimDate'] = 'invalid-date'
      expect(subject.claim_date).to eq(Date.current)
    end

    it 'returns the current date if claimDate isn not YYYY-MM-DD' do
      form_attributes['claimDate'] = '01-01-2020'
      expect(subject.claim_date).to eq(Date.current)
    end
  end
end
