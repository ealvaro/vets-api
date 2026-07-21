# frozen_string_literal: true

require 'rails_helper'
require 'dgi/forms/response/claimant_info_response'
require 'dgi/letters/service'

describe ToeClaimantInfoSerializer, type: :serializer do
  subject { serialize(claimant_response, serializer_class: described_class) }

  let(:claimant) do
    {
      claimant_id: 0,
      suffix: nil,
      date_of_birth: '1992-04-01',
      first_name: 'Black',
      last_name: 'Johnson',
      middle_name: 'Jet',
      notification_method: 'NONE',
      contact_info: nil,
      preferred_contact: nil
    }
  end

  let(:toe_sponsors) do
    {
      transfer_of_entitlements: [
        {
          fist_name: 'SEAN',
          second_name: 'JOHNSON',
          sponsor_relationship: 'Child',
          sponsor_va_id: 1_000_000_077,
          date_of_birth: '1971-05-24'
        }
      ]
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
      { 'benefit_or_source_type' => 'CH35', 'date_received' => '2025-06-24' }
    ]
  end

  let(:latest_ch33) do
    {
      'wp_key' => 99_000_000_113_358_421,
      'ch33_original_entitled_days' => 1084.0,
      'ch33_days_used' => 1033.0,
      'entitlement_transfers' => [
        {
          'entitlement_transfer_key' => 99_000_000_001_473_862,
          'begin_date' => 1_734_670_800_000,
          'ch1606_kicker_out' => nil,
          'ch30_kicker_out' => nil,
          'end_date' => nil,
          'recipient' => {
            'key' => 300_000_000_000_081
          },
          'relationship' => 'Child',
          'transfer_out' => 30,
          'transferor_person' => {
            'key' => 300_000_000_000_062
          }
        }
      ],
      'ch33_days_remaining' => 17.0,
      'percentage_benefit' => 100,
      'delimiting_date' => nil,
      'date_authorized' => '2025-06-24 16:18:33',
      'veteran_is_eligible' => nil,
      'benefit_or_source_type' => 'CH33'
    }
  end

  let(:claimant_response) do
    body = { 'claimant' => claimant,
             'service_data' => service_data,
             'submission_pending_review_information' => submission_pending_review_information,
             'non33_eligibilities' => [],
             'latest_ch33_eligibility' => latest_ch33 }
    response = double('response', body:)
    MebApi::DGI::Forms::ClaimantResponse.new(200, response)
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

  it 'includes :toe_sponsors' do
    expect_data_eq(attributes['toe_sponsors'], toe_sponsors)
  end

  describe 'meb_supplemental_coe flag on' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:meb_supplemental_coe)
        .and_return(true)
    end

    it 'includes :benefits' do
      result = [{
        'benefit_type' => 'CH33',
        'amount_received' => { 'months' => 36, 'days' => 4.0 },
        'amount_used' => { 'months' => 34, 'days' => 13.0 },
        'amount_left' => { 'months' => 0, 'days' => 17.0 },
        'benefit_end_date' => nil,
        'amount_transferred' => { 'months' => 1, 'days' => 0 },
        'eligibility_percentage' => 100
      }]
      expect(attributes['benefits']).to eq(result)
    end

    it 'includes in progress flags' do
      expect(attributes['has_ch_35_original_claim_in_progress']).to be(true)
      expect(attributes['has_ch_33_original_claim_in_progress']).to be(false)
      expect(attributes['has_fry_original_claim_in_progress']).to be(false)
      expect(attributes['has_toe_original_claim_in_progress']).to be(false)
    end

    it 'includes received dates' do
      expect(attributes['ch_35_received_date']).to eq('2025-06-24')
      expect(attributes['ch_33_received_date']).to be_nil
      expect(attributes['fry_received_date']).to be_nil
      expect(attributes['toe_received_date']).to be_nil
    end
  end
end
