# frozen_string_literal: true

module Mobile
  module V0
    class MaintenanceWindowsController < ApplicationController
      skip_before_action :authenticate

      # Backend → API mapping reference:
      # https://va.ghe.com/software/leeroy-jenkles/wiki/API-Backend-Systems#api-to-va-backend-mapping
      BASE_EDGES = [
        %i[bgs caseflow],
        %i[bgs payment_history],
        %i[bgs lighthouse_benefits_claims],
        %i[bgs lighthouse_direct_deposit],
        %i[bgs lighthouse_vshe],
        %i[bgs lighthouse_letters_generator],
        %i[mpi lighthouse_direct_deposit],
        %i[mpi lighthouse_veterans_health],
        %i[mpi lighthouse_letters_generator],
        %i[mpi lighthouse_vshe],
        %i[vbms lighthouse_benefits_claims],
        %i[arcgis facility_locator],
        %i[caseflow appeals],
        %i[vapro_military_info military_service_history],
        %i[lighthouse_benefits_claims claims],
        %i[lighthouse_vshe disability_rating],
        %i[lighthouse_letters_generator letters_and_documents],
        %i[lighthouse_veterans_health immunizations],
        %i[lighthouse_veterans_health allergies],
        %i[lighthouse_veterans_health labs_and_tests],
        %i[lighthouse_facilities facility_locator],
        %i[lighthouse_direct_deposit direct_deposit_benefits],
        %i[mhv_platform mhv_sm],
        %i[mhv_platform mhv_meds],
        %i[mhv_sm secure_messaging],
        %i[mhv_meds rx_refill],
        %i[vaos appointments],
        %i[vapro_personal_info user_demographics],
        %i[vapro_contact_info user_profile_update],
        %i[eoas preneed_burial],
        %i[travel_pay travel_pay_features]
      ].freeze

      # When the efolder_use_lighthouse_benefits_documents_service flag is OFF, mobile's efolder
      # feature hits VBMS directly; an upstream VBMS outage cascades straight to :efolder.
      VBMS_EFOLDER_GRAPH = Mobile::V0::ServiceGraph.new(*BASE_EDGES, %i[vbms efolder])

      # When the flag is ON, the efolder feature routes through the Lighthouse Benefits Documents
      # API. Per the backend wiki, that API depends on both BGS and VBMS, so outages on either
      # upstream cascade to :efolder via the lighthouse_benefits_documents intermediate node.
      LH_EFOLDER_GRAPH = Mobile::V0::ServiceGraph.new(
        *BASE_EDGES,
        %i[bgs lighthouse_benefits_documents],
        %i[vbms lighthouse_benefits_documents],
        %i[lighthouse_benefits_documents efolder]
      )

      def index
        render json: Mobile::V0::MaintenanceWindowSerializer.new(maintenance_windows)
      end

      private

      def maintenance_windows
        upstream_maintenance_windows = ::MaintenanceWindow.end_after(Time.zone.now)
        service_graph.affected_services(upstream_maintenance_windows).values
      end

      # Endpoint is unauthenticated, so @current_user is nil — Flipper evaluates the flag globally.
      # Keeping this global will keep maintenance windows consistent across all users, regardless
      # of rollout percentage or targeting rules.
      def service_graph
        if Flipper.enabled?(:efolder_use_lighthouse_benefits_documents_service)
          LH_EFOLDER_GRAPH
        else
          VBMS_EFOLDER_GRAPH
        end
      end
    end
  end
end
