# frozen_string_literal: true

require 'rails_helper'
require 'dgi/automation/claimant_response'
require 'dgi/letters/service'

describe AutomationSerializer, type: :serializer do
  subject { serialize(automation_claimant_response, serializer_class: described_class) }

  let(:claimant) do
    {
      claimant_id: 600_010_259,
      suffix: '',
      date_of_birth: '1990-08-01',
      first_name: 'Hector',
      last_name: 'Allen',
      middle_name: 'James',
      notification_method: 'NONE',
      contact_info: {
        address_line1: '1291 Boston Post Rd',
        address_line2: '',
        city: 'Madison',
        zipcode: '06443',
        email_address: 'testing@test.com',
        address_type: 'DOMESTIC',
        mobile_phone_number: '1231231234',
        home_phone_number: '1231231234',
        country_code: 'US',
        state_code: 'CT'
      },
      preferred_contact: nil
    }
  end

  let(:service_data) do
    [
      {
        branch_of_service: 'Air Force',
        begin_date: '2010-06-01',
        end_date: '2020-06-01',
        character_of_service: 'Honorable',
        reason_for_separation: 'Expiration Term Of Service',
        exclusion_periods: [],
        training_periods: []
      }
    ]
  end

  let(:submission_pending_review_information) do
    [
      { 'benefit_or_source_type' => 'CH1606', 'date_received' => '2025-06-24' }
    ]
  end

  let(:non33_eligibilities) do
    [{
      'benefit_type' => 'CH30',
      'eligibility_result' =>
        {
          'benefit_type' => 'CH30',
          'eligibility_period' => {
            'delimiting_date' => '2019-06-01'
          }
        },
      'entitlement_result' =>
        {
          'id' => 300_000_000_000_045,
          'orig_entitled_days' => 1080.00000,
          'days_used' => 157.50000,
          'days_remaining' => 922.50000,
          'vt2_entitlement_charged_days' => nil,
          'vt2_exhaustion_date' => nil,
          'exhaustion_date' => nil,
          'is_current' => true,
          'benefit_type' => 'CH30'
        }
    }]
  end

  let(:latest_ch33) do
    {
      'wp_key' => 99_000_000_113_358_386,
      'ch33_original_entitled_days' => 1080.0,
      'ch33_days_used' => 157.5,
      'entitlement_transfers' => [],
      'ch33_days_remaining' => 0.5,
      'percentage_benefit' => 100,
      'delimiting_date' => nil,
      'date_authorized' => '2025-06-24 16:18:33',
      'veteran_is_eligible' => nil,
      'benefit_or_source_type' => 'CH33'
    }
  end

  let(:automation_claimant_response) do
    response = double('response',
                      body: { 'claimant' => claimant,
                              'service_data' => service_data,
                              'submission_pending_review_information' => submission_pending_review_information,
                              'non33_eligibilities' => non33_eligibilities,
                              'latest_ch33_eligibility' => latest_ch33 })
    MebApi::DGI::Automation::ClaimantResponse.new(201, response)
  end

  let(:data) { JSON.parse(subject)['data'] }
  let(:attributes) { data['attributes'] }

  before do
    allow(Flipper).to receive(:enabled?)
      .with(:meb_supplemental_coe)
      .and_return(false)
  end

  it 'includes :id' do
    expect(data['id']).to be_blank
  end

  it 'includes :claimant' do
    expect_data_eq(attributes['claimant'], claimant)
  end

  it 'includes :service_data' do
    expect_data_eq(attributes['service_data'], service_data)
  end

  describe 'meb_supplemental_coe flag on' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:meb_supplemental_coe)
        .and_return(true)
    end

    it 'includes :benefits' do
      result = [
        {
          'benefit_type' => 'CH30',
          'amount_received' => { 'months' => 36, 'days' => 0 },
          'amount_used' => { 'months' => 5, 'days' => 8 },
          'amount_left' => { 'months' => 30, 'days' => 22 },
          'benefit_end_date' => '2019-06-01'
        },
        {
          'benefit_type' => 'CH33',
          'amount_received' => { 'months' => 36, 'days' => 0.0 },
          'amount_used' => { 'months' => 5, 'days' => 8 },
          'amount_left' => { 'months' => 0, 'days' => 1.0 },
          'eligibility_percentage' => 100,
          'benefit_end_date' => nil
        }
      ]
      expect(attributes['benefits']).to eq(result)
    end

    it 'includes in progress flags' do
      expect(attributes['has_ch_1606_original_claim_in_progress']).to be(true)
      expect(attributes['has_ch_30_original_claim_in_progress']).to be(false)
      expect(attributes['has_ch_35_original_claim_in_progress']).to be(false)
      expect(attributes['has_ch_33_original_claim_in_progress']).to be(false)
      expect(attributes['has_fry_original_claim_in_progress']).to be(false)
      expect(attributes['has_toe_original_claim_in_progress']).to be(false)
    end

    it 'includes received dates' do
      expect(attributes['ch_1606_received_date']).to eq('2025-06-24')
      expect(attributes['ch_30_received_date']).to be_nil
      expect(attributes['ch_35_received_date']).to be_nil
      expect(attributes['ch_33_received_date']).to be_nil
      expect(attributes['fry_received_date']).to be_nil
      expect(attributes['toe_received_date']).to be_nil
    end
  end
end
