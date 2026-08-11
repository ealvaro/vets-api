# frozen_string_literal: true

require 'medical_copays/cerner_facilities'
require_relative '../../services/medical_copays/lighthouse_integration/exceptions'

module V1
  class MedicalCopaysController < ApplicationController
    service_tag 'debt-resolution'
    before_action :authorize_icn
    rescue_from MedicalCopays::LighthouseIntegration::Exceptions::ServiceError, with: :service_error
    rescue_from MedicalCopays::VBS::Service::StatementNotFound, with: :not_found
    rescue_from MedicalCopays::VBS::Service::ServiceError, with: :service_error

    def index
      if use_vbs?
        copays = vbs_service.get_copays
        copays[:isCerner] = true

        render json: copays
      else
        invoice_bundle = medical_copay_service.list_months(
          status: params[:status],
          include_line_items: params[:include_line_items]
        )
        serialized = Lighthouse::HCC::InvoiceSerializer.new(
          invoice_bundle.entries, links: invoice_bundle.links, meta: invoice_bundle.meta
        ).serializable_hash

        render json: serialized.merge(isCerner: false)
      end
    end

    def summary
      result = medical_copay_service.summary(
        month_count: params[:months]&.to_i || 6,
        status: cerner_copay_user? ? nil : params[:status]
      )

      render json: Lighthouse::HCC::InvoiceSerializer.new(
        result[:entries],
        meta: result[:meta]
      )
    end

    def show
      if use_vbs?
        copay = vbs_service.get_copay_by_id(params[:id])
        copay[:isCerner] = true

        render json: copay
      else
        copay_detail = medical_copay_service.get_detail(id: params[:id])
        serialized = Lighthouse::HCC::CopayDetailSerializer.new(copay_detail).serializable_hash

        render json: serialized.merge(isCerner: false)
      end
    end

    private

    def use_vbs?
      return true if cerner_copay_user?

      # If the feature flag is enabled, we want to log a warning so we can track usage of the route
      if payment_history_enabled?
        Rails.logger.warn('medical_copays route hit when enable_facility_account_history true')
      end

      !show_payment_history_enabled?
    end

    def show_payment_history_enabled?
      MedicalCopays::FeatureFlagHelpers.show_payment_history_enabled?(current_user)
    end

    def use_lighthouse?
      MedicalCopays::FeatureFlagHelpers.lighthouse_copays_enabled?(current_user)
    end

    def payment_history_enabled?
      MedicalCopays::FeatureFlagHelpers.facility_account_history_enabled?(current_user)
    end

    def medical_copay_service
      MedicalCopays::LighthouseIntegration::Service.new(current_user.icn)
    end

    def service_error
      render json: { error: 'External service error' }, status: :bad_gateway
    end

    def authorize_icn
      raise Common::Exceptions::Forbidden, detail: 'User ICN is required' if current_user.icn.blank?
    end

    def vbs_service
      MedicalCopays::VBS::Service.build(user: current_user)
    end

    def cerner_copay_user?
      MedicalCopays::CernerFacilities.cerner_copay_user?(current_user)
    end

    def not_found
      render json: nil, status: :not_found
    end
  end
end
