# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V1::MedicalCopaysController, type: :controller do
  let(:user) { build(:user, :loa3) }

  before { sign_in_as(user) }

  # Helper: stub all three flags to explicit values; default everything off.
  def stub_flags(old_flag: false, lighthouse_copays: false, payment_history: false)
    flag_values = {
      vha_show_payment_history: old_flag,
      enable_lighthouse_copays: lighthouse_copays,
      enable_facility_account_history: payment_history
    }
    allow(Flipper).to receive(:enabled?) do |flag, *_args|
      flag_values.fetch(flag, false)
    end
  end

  def stub_cerner(value)
    allow_any_instance_of(described_class).to receive(:cerner_copay_user?).and_return(value)
  end

  def stub_vbs
    allow_any_instance_of(MedicalCopays::VBS::Service)
      .to receive(:get_copays).and_return(data: [{ 'fooBar' => 'bar' }], status: 200)
  end

  def stub_lighthouse
    invoice_bundle = double('invoice_bundle', entries: [], links: {}, meta: {})
    lighthouse_service = instance_double(
      MedicalCopays::LighthouseIntegration::Service,
      list_months: invoice_bundle
    )
    allow(MedicalCopays::LighthouseIntegration::Service)
      .to receive(:new).and_return(lighthouse_service)
    serializer = instance_double(Lighthouse::HCC::InvoiceSerializer, serializable_hash: { data: [] })
    allow(Lighthouse::HCC::InvoiceSerializer).to receive(:new).and_return(serializer)
  end

  describe '#use_vbs? routing via #index' do
    context 'non-Cerner user' do
      before { stub_cerner(false) }

      it 'routes to VBS when no flags are on' do
        stub_flags
        stub_vbs
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(true)
      end

      it 'routes to VBS when only enable_facility_account_history is on' do
        stub_flags(payment_history: true)
        stub_vbs
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(true)
      end

      it 'routes to Lighthouse when the old flag is on' do
        stub_flags(old_flag: true)
        stub_lighthouse
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(false)
      end

      it 'routes to Lighthouse when the old flag and enable_facility_account_history are both on' do
        stub_flags(old_flag: true, payment_history: true)
        stub_lighthouse
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(false)
      end

      it 'logs a warning when enable_facility_account_history is on' do
        stub_flags(payment_history: true)
        stub_vbs
        expect(Rails.logger).to receive(:warn)
          .with('medical_copays route hit when enable_facility_account_history true')
        get(:index)
      end
    end

    context 'Cerner user' do
      before { stub_cerner(true) }

      it 'routes to VBS when all flags are off' do
        stub_flags
        stub_vbs
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(true)
      end

      it 'routes to VBS even when the old flag is on' do
        stub_flags(old_flag: true)
        stub_vbs
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(true)
      end

      it 'routes to VBS even when the new flag is on' do
        stub_flags(old_flag: true, payment_history: true)
        stub_vbs
        get(:index)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be(true)
      end
    end
  end
end
