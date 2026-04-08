# frozen_string_literal: true

require 'rails_helper'

Sidekiq::Testing.fake!

RSpec.describe MyHealth::V2::ImagingController, type: :controller do
  let(:user) { create(:user, :loa3) }

  before do
    sign_in_as(user)
    controller.instance_variable_set(:@current_user, user)
  end

  describe 'enqueue_imaging_refresh_job' do
    context 'when OH imaging toggle is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, user)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, user)
          .and_return(false)
      end

      it 'enqueues the ImagingRefreshJob' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async).with(user.uuid)
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

      it 'enqueues the ImagingRefreshJob' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async).with(user.uuid)
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

      it 'enqueues the ImagingRefreshJob only once' do
        expect(UnifiedHealthData::ImagingRefreshJob).to receive(:perform_async).with(user.uuid).once
        controller.send(:enqueue_imaging_refresh_job)
      end
    end
  end
end
