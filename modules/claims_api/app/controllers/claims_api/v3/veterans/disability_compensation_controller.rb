# frozen_string_literal: true

module ClaimsApi
  module V3
    module Veterans
      class DisabilityCompensationController < ClaimsApi::V3::Veterans::Base
        FORM_NUMBER = '526'

        # attachments are uploaded as multipart, not JSON
        skip_before_action :validate_json_format, only: %i[upload_supporting_documents]

        def submit
          render json: { errors: [{ status: '501', title: 'Not Implemented' }] }, status: :not_implemented
        end

        def generate_pdf
          render json: { errors: [{ status: '501', title: 'Not Implemented' }] }, status: :not_implemented
        end

        def upload_supporting_documents
          render json: { errors: [{ status: '501', title: 'Not Implemented' }] }, status: :not_implemented
        end
      end
    end
  end
end
