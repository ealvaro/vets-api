# frozen_string_literal: true

module MyHealth
  module V1
    class PrescriptionDocumentationController < RxController
      def index
        id = params[:id]
        rx = client.get_rx_details(id)

        raise Common::Exceptions::RecordNotFound, id if rx.nil?

        ndc_value = rx.cmop_ndc_value.presence
        ndc_value ||= rx.ndc.presence if Flipper.enabled?(:mhv_medications_ndc_fallback, current_user)

        if ndc_value.blank?
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: 'Prescription is missing required drug information (NDC)'
          )
        end

        documentation = client.get_rx_documentation(ndc_value)
        prescription_documentation = PrescriptionDocumentation.new({ html: documentation[:data] })
        render json: PrescriptionDocumentationSerializer.new(prescription_documentation)
      end
    end
  end
end
