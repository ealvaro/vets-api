# frozen_string_literal: true

require 'lighthouse/benefits_claims/service'

module Mobile
  module V0
    class PowerOfAttorneyController < ApplicationController
      before_action { authorize :power_of_attorney, :access? }

      def index
        @active_poa = lighthouse_service.get_power_of_attorney

        if @active_poa.blank? || record.blank?
          render json: { data: {} }, status: :ok
        else
          render json: serializer.new(record), status: :ok
        end
      end

      private

      def use_accredited_models?
        Flipper.enabled?(:mobile_power_of_attorney_use_accredited_models)
      end

      def lighthouse_service
        BenefitsClaims::Service.new(icn)
      end

      def icn
        @current_user&.icn
      end

      def poa_code
        @poa_code ||= @active_poa.dig('data', 'attributes', 'code')
      end

      def poa_type
        @poa_type ||= @active_poa.dig('data', 'type')
      end

      def record
        return @record if defined? @record

        @record ||= if poa_type == 'organization'
                      organization
                    else
                      representative
                    end
      end

      def serializer
        if poa_type == 'organization'
          if use_accredited_models?
            Mobile::V0::PowerOfAttorney::AccreditedOrganizationSerializer
          else
            RepresentationManagement::PowerOfAttorney::OrganizationSerializer
          end
        elsif use_accredited_models?
          Mobile::V0::PowerOfAttorney::AccreditedIndividualSerializer
        else
          RepresentationManagement::PowerOfAttorney::RepresentativeSerializer
        end
      end

      def organization
        if use_accredited_models?
          AccreditedOrganization.find_by(poa_code:)
        else
          Veteran::Service::Organization.find_by(poa: poa_code)
        end
      end

      def representative
        if use_accredited_models?
          # VSO Representatives have no POA code in the "individuals" table - they must be found
          # by searching by organization
          AccreditedIndividual
            .left_joins(:accredited_organizations)
            .where('accredited_individuals.poa_code = :code OR accredited_organizations.poa_code = :code',
                   code: poa_code)
            .order(created_at: :desc)
            .first
        else
          Veteran::Service::Representative.where('? = ANY(poa_codes)', poa_code).order(created_at: :desc).first
        end
      end
    end
  end
end
