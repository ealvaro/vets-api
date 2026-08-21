# frozen_string_literal: true

require 'rails_helper'
require 'digital_forms_api/dpdf_downloader'

RSpec.describe DigitalFormsApi::SubmissionsController, type: :controller do
  routes { DigitalFormsApi::Engine.routes }

  let(:user) { create(:user, :loa3) }
  let(:claim) { create(:add_remove_dependents_claim) }
  let(:flipper_enabled) { true }
  let(:pdf_bytes) { '%PDF-1.4 fake-bytes' }
  let(:monitor) { instance_double(DigitalFormsApi::Monitor::Controller, track_show: true) }
  let(:downloader) { instance_double(DigitalFormsApi::DpdfDownloader, fetch: pdf_bytes) }

  before do
    sign_in_as(user)
    claim.update!(user_account_id: user.user_account.id)
    allow(Flipper).to receive(:enabled?)
      .with(:dependents_digital_forms_api_submission_enabled, instance_of(User)).and_return(flipper_enabled)
    allow_any_instance_of(described_class).to receive(:monitor).and_return(monitor)
    allow(DigitalFormsApi::DpdfDownloader).to receive(:new).and_return(downloader)
  end

  describe '#show' do
    subject(:show) { get(:show, params: { id: claim.guid }) }

    context 'when the claim belongs to the current user and its dPDF is filed' do
      it 'streams the PDF back from Claims Evidence' do
        expect(monitor).to receive(:track_show).with(
          hash_including(http_status: 200, submission_id: claim.guid, form_id: claim.form_id.downcase,
                         failure_stage: 'none')
        )

        show

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/pdf')
        expect(response.body).to eq(pdf_bytes)
      end
    end

    context 'when the guid matches no claim' do
      it 'returns 404' do
        get(:show, params: { id: 'no-such-guid' })
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the guid belongs to a claim that is not a 686c/674 child claim' do
      it 'returns 404 — the lookup is scoped to the dependents child claims' do
        other = create(:dependents_claim) # PrimaryDependencyClaim (the parent), not a 686c/674 child
        get(:show, params: { id: other.guid })
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the claim belongs to a different user' do
      before { claim.update!(user_account_id: create(:user_account).id) }

      it 'returns 403' do
        show
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the claim has nothing filed in Claims Evidence yet' do
      before { allow(downloader).to receive(:fetch).and_raise(DigitalFormsApi::DpdfDownloader::NotFiled) }

      it 'returns 404' do
        show
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when Claims Evidence returns a client error' do
      before do
        allow(downloader).to receive(:fetch).and_raise(Common::Client::Errors::ClientError.new('boom', 500))
      end

      it 'returns 500' do
        show
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context 'when Claims Evidence times out' do
      before { allow(downloader).to receive(:fetch).and_raise(Common::Exceptions::GatewayTimeout) }

      it 'tracks the failure as a 504 (matching the rendered status)' do
        expect(monitor).to receive(:track_show).with(
          hash_including(http_status: 504, error_source: 'upstream_unavailable', failure_stage: 'download_dpdf')
        )
        show
        expect(response).to have_http_status(:gateway_timeout)
      end
    end

    context 'when the Claims Evidence circuit breaker is open' do
      before do
        breaker_service = instance_double(Breakers::Service, name: 'ClaimsEvidenceApi')
        outage = instance_double(Breakers::Outage, start_time: Time.current, service: breaker_service)
        allow(downloader).to receive(:fetch).and_raise(Breakers::OutageException.new(outage, breaker_service))
      end

      it 'tracks the failure as a 503 (matching the rendered status)' do
        expect(monitor).to receive(:track_show).with(
          hash_including(http_status: 503, error_source: 'upstream_unavailable', failure_stage: 'download_dpdf')
        )
        show
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when the feature flag is disabled' do
      let(:flipper_enabled) { false }

      it 'returns 403' do
        show
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
