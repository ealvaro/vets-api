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

  let(:cs_claimant) do
    {
      'eligibility_results' => [],
      'entitlement_results' => [
        {
          'id' => 300_000_000_000_061,
          'orig_entitled_days' => 1084.00000,
          'days_used' => 1033.00000,
          'days_remaining' => 17.00000,
          'vt2_entitlement_charged_days' => nil,
          'vt2_exhaustion_date' => nil,
          'exhaustion_date' => nil,
          'is_current' => true,
          'benefit_type' => 'CH33'
        }
      ]
    }
  end

  let(:coe_information) do
    [
      {
        'claim_id' => nil,
        'wp_key' => 99_000_000_113_358_420,
        'benefit_or_source_type' => 'CH33',
        'is_in_progress' => false,
        'is_eligible' => true,
        'date_authorized' => '2025-06-24 11:17:21'
      }
    ]
  end

  let(:latest_ch33) do
    [
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
    ]
  end

  let(:claimant_response) do
    body = { 'claimant' => claimant,
             'service_data' => service_data,
             'cs_claimant' => cs_claimant,
             'coe_information' => coe_information,
             'latest_ch33_eligibilites' => latest_ch33 }
    response = double('response', body:)
    MebApi::DGI::Forms::ClaimantResponse.new(200, response)
  end

  let(:data) { JSON.parse(subject)['data'] }
  let(:attributes) { data['attributes'] }

  let(:letter_service) { instance_double(MebApi::DGI::Letters::Service) }
  let(:coe_letter_response) do
    double('response',
           status: 200,
           body: "%PDF-1.4\ntrailer<</Root<</Pages<</Kids[<</MediaBox[0 0 3 3]>>]>>>>>>")
  end

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
      allow(MebApi::DGI::Letters::Service).to receive(:new).and_return(letter_service)
      allow(letter_service).to receive(:get_claim_letter_by_claim_id).and_return(coe_letter_response)
    end

    it 'includes :benefits' do
      result = [{
        'benefit_type' => 'CH33',
        'amount_received' => { 'months' => 36, 'days' => 4.0 },
        'amount_used' => { 'months' => 34, 'days' => 13.0 },
        'amount_left' => { 'months' => 0, 'days' => 17.0 },
        'benefit_end_date' => nil,
        'amount_transferred' => { 'months' => 1, 'days' => 0 },
        'eligibility_percentage' => 100,
        'coe_issued_date' => '2025-06-24 11:17:21',
        'coe_letter' => "data:application/pdf;base64,#{Base64.strict_encode64(coe_letter_response.body)}"
      }]
      expect(attributes['benefits']).to eq(result)
    end

    it 'includes in progress flags' do
      expect(attributes['has_ch_35_original_claim_in_progress']).to be(false)
      expect(attributes['has_ch_33_original_claim_in_progress']).to be(false)
      expect(attributes['has_fry_original_claim_in_progress']).to be(false)
      expect(attributes['has_toe_original_claim_in_progress']).to be(false)
    end

    it 'returns benefits even if coe letter fetch fails' do
      expect(letter_service).to receive(:get_claim_letter_by_claim_id).and_raise(StandardError)
      expect(attributes['benefits']).to eq([{
                                             'benefit_type' => 'CH33',
                                             'amount_received' => { 'months' => 36, 'days' => 4.0 },
                                             'amount_used' => { 'months' => 34, 'days' => 13.0 },
                                             'amount_left' => { 'months' => 0, 'days' => 17.0 },
                                             'benefit_end_date' => nil,
                                             'amount_transferred' => { 'months' => 1, 'days' => 0 },
                                             'eligibility_percentage' => 100,
                                             'coe_issued_date' => '2025-06-24 11:17:21',
                                             'coe_letter' => nil
                                           }])
    end
  end
end
