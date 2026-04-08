# frozen_string_literal: true

require 'rails_helper'

Sidekiq::Testing.fake!

RSpec.describe MyHealth::V2::ImagingController, type: :controller do
  let(:user) { create(:user, :loa3) }

  before do
    sign_in_as(user)
    controller.instance_variable_set(:@current_user, user)
    allow(user).to receive_messages(va_treatment_facility_ids: %w[453], cerner_facility_ids: %w[668])
  end

  describe 'enqueue_imaging_refresh_job' do
    let(:expected_site_ids) { %w[453 200CRNR] }

    context 'when OH imaging toggle is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(false)
      end

      it 'enqueues the ImagingRefreshJob with site_ids' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async)
          .with(user.uuid, expected_site_ids)
        controller.send(:enqueue_imaging_refresh_job)
      end
    end

    context 'when VistA imaging toggle is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(true)
      end

      it 'enqueues the ImagingRefreshJob with site_ids' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async)
          .with(user.uuid, expected_site_ids)
        controller.send(:enqueue_imaging_refresh_job)
      end
    end

    context 'when both imaging toggles are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(false)
      end

      it 'does not enqueue the ImagingRefreshJob' do
        expect(UnifiedHealthData::ImagingRefreshJob).not_to receive(:perform_async)
        controller.send(:enqueue_imaging_refresh_job)
      end
    end

    context 'when both imaging toggles are enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(true)
      end

      it 'enqueues the ImagingRefreshJob only once with site_ids' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async)
          .with(user.uuid, expected_site_ids).once
        controller.send(:enqueue_imaging_refresh_job)
      end
    end

    context 'when user has only VistA facilities' do
      before do
        allow(user).to receive(:cerner_facility_ids).and_return([])
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(false)
      end

      it 'passes only VistA site IDs without 200CRNR' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async)
          .with(user.uuid, %w[453])
        controller.send(:enqueue_imaging_refresh_job)
      end
    end
  end
end
