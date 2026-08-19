# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/prescription_service'
require 'unified_health_data/client'
require 'mhv/prescriptions/refill_request_tracker'
require 'support/shared_contexts/uhd_security_endpoint'

# End-to-end coverage confirming the refill-status endpoint reflects the true upstream status
# for a freshly staged, still-refillable titratable: it must surface as "active"/"Active" and
# stay refillable, with no client-side reclassification and no RefillRequestTracker override.
#
# These specs drive the real read chain, stubbing only the UHD HTTP client:
#   Client#get_prescriptions_by_date -> PrescriptionService -> PrescriptionsAdapter
#   -> Prescription -> controller#show (RefillRequestTracker) -> PrescriptionDetailsSerializer
RSpec.describe 'MyHealth::V2::Prescriptions refill_status classification', type: :request do
  include_context 'uhd legacy security endpoint'

  let(:current_user) { build(:user, :mhv) }
  let(:prescription_id) { '29511985' }
  let(:station_number)  { '989' }
  let(:show_path) { "/my_health/v2/prescriptions/#{prescription_id}?station_number=#{station_number}" }

  let(:frozen_time) { Time.zone.parse('2026-07-28 12:00:00') }
  let(:management_improvements) { true }

  let(:base_medication_hash) do
    {
      'refillStatus' => 'active',
      'refillSubmitDate' => nil,
      'refillDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'refillRemaining' => 11,
      'facilityApiName' => 'Dayton Medical Center',
      'isRefillable' => true,
      'isTrackable' => false,
      'prescriptionId' => 29_511_985,
      'sig' => 'TAKE ONE TABLET BY MOUTH DAILY FOR 14 DAYS, THEN TAKE TWO TABLETS DAILY',
      'orderedDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'quantity' => '60',
      'expirationDate' => 'Thu, 29 Jul 2027 00:00:00 EDT',
      'prescriptionNumber' => '2721495',
      'prescriptionName' => 'METOPROLOL SUCCINATE 100MG SA TAB',
      'dispensedDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'stationNumber' => '989',
      'notRefillableDisplayMessage' => 'A refill request cannot be submitted at this time...',
      'id' => 29_511_985,
      'dispStatus' => 'Active',
      'prescriptionSource' => 'RX',
      'dataSourceSystem' => 'VISTA',
      'isRenewable' => false,
      'trackingList' => nil,
      'rxRFRecords' => nil,
      'tracking' => false
    }
  end

  def base_medication(overrides = {})
    base_medication_hash.merge(overrides)
  end

  def envelope(medication)
    {
      'vista' => { 'medicationList' => { 'medication' => [medication] }, 'errors' => [], 'infoMessages' => [] },
      'oracle-health' => {}
    }
  end

  def stub_uhd_client(medication)
    response = instance_double(Faraday::Response, body: envelope(medication))
    allow_any_instance_of(UnifiedHealthData::Client)
      .to receive(:get_prescriptions_by_date).and_return(response)
  end

  def show_attributes
    get show_path
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('data', 'attributes')
  end

  around { |example| Timecop.freeze(frozen_time) { example.run } }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
    # Fresh cache => RefillRequestTracker has no active claim (apply_recent_submission_overrides no-op).
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(false)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medications_management_improvements, anything).and_return(management_improvements)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_mmi_refill_status_bandaid_temp, anything).and_return(management_improvements)
  end

  describe 'GET /my_health/v2/prescriptions/:id?station_number=989' do
    context 'freshly staged, refillable initial fill' do
      before { stub_uhd_client(base_medication) }

      context 'with mhv_medications_management_improvements ON' do
        let(:management_improvements) { true }

        it 'returns Active (not refillinprocess) and stays refillable' do
          attrs = show_attributes

          expect(attrs['refill_status']).to eq('active')
          expect(attrs['disp_status']).to eq('Active')
          expect(attrs['is_refillable']).to be true
        end

        it 'did not run the RefillRequestTracker override (status is not submitted)' do
          attrs = show_attributes

          expect(attrs['refill_status']).not_to eq('submitted')
          expect(attrs['disp_status']).not_to eq('Active: Submitted')
        end

        it 'nulls not_refillable_display_message (the UHD model never carries it)' do
          attrs = show_attributes

          expect(attrs).to have_key('not_refillable_display_message')
          expect(attrs['not_refillable_display_message']).to be_nil
        end
      end

      context 'with mhv_medications_management_improvements OFF' do
        let(:management_improvements) { false }

        it 'passes upstream status through unchanged' do
          attrs = show_attributes

          expect(attrs['refill_status']).to eq('active')
          expect(attrs['disp_status']).to eq('Active')
        end
      end
    end
  end
end
