# frozen_string_literal: true

require 'rails_helper'
require 'mhv/aal/client'

RSpec.describe Mobile::AALClientConcerns, type: :model do
  let(:test_class) do
    Class.new do
      include Mobile::AALClientConcerns

      attr_reader :current_user

      def initialize(current_user)
        @current_user = current_user
      end
    end
  end

  let(:current_user) { build(:user, :mhv) }
  let(:instance) { test_class.new(current_user) }
  let(:aal_client) { instance_double(AAL::MobileClient, authenticate: nil, create_aal: nil) }

  before do
    allow(AAL::MobileClient).to receive(:new).and_return(aal_client)
  end

  describe '#log_mhv_aal' do
    context 'when the feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_mobile_medical_records_aal_logging, current_user).and_return(true)
      end

      it 'authenticates and creates a once-per-session AAL entry' do
        instance.log_mhv_aal('Vaccines')

        expect(aal_client).to have_received(:authenticate)
        expect(aal_client).to have_received(:create_aal).with(
          {
            activity_type: 'Vaccines',
            action: 'View',
            performer_type: 'Self',
            status: 1
          },
          true,
          current_user.last_signed_in
        )
      end

      it 'supports a custom action' do
        instance.log_mhv_aal('Allergy and Reactions', action: 'Download')

        expect(aal_client).to have_received(:create_aal).with(
          hash_including(activity_type: 'Allergy and Reactions', action: 'Download'),
          true,
          anything
        )
      end

      it 'is non-blocking: swallows client errors and logs them with the exception object' do
        error = StandardError.new('boom')
        allow(aal_client).to receive(:create_aal).and_raise(error)
        expect(Rails.logger).to receive(:error)
          .with('Mobile MHV AAL logging failed', exception: error)

        expect { instance.log_mhv_aal('Vaccines') }.not_to raise_error
      end

      context 'when the user has no MHV correlation id' do
        before { allow(current_user).to receive(:mhv_correlation_id).and_return(nil) }

        it 'no-ops without building or authenticating the AAL client' do
          instance.log_mhv_aal('Vaccines')

          expect(AAL::MobileClient).not_to have_received(:new)
          expect(aal_client).not_to have_received(:authenticate)
          expect(aal_client).not_to have_received(:create_aal)
        end
      end
    end

    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_mobile_medical_records_aal_logging, current_user).and_return(false)
      end

      it 'does not build a client or log anything' do
        instance.log_mhv_aal('Vaccines')

        expect(AAL::MobileClient).not_to have_received(:new)
        expect(aal_client).not_to have_received(:create_aal)
      end
    end
  end
end
