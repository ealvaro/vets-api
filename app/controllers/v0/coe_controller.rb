# frozen_string_literal: true

require 'lgy/service'

module V0
  class CoeController < ApplicationController
    service_tag 'home-loan-status'

    before_action(only: :status) { authorize(:coe, :access?) }

    def status
      coe_status = lgy_service.coe_status

      if coe_status.nil?
        Rails.logger.error('COE status unexpected or blank', user_context)
        StatsD.increment("#{stats_key}.status.unexpected_blank")
      else
        Rails.logger.info('COE status retrieved successfully',
                          user_context.merge(status: coe_status[:status]))
        StatsD.increment("#{stats_key}.status.success")
      end

      render json: { data: { attributes: coe_status } }, status: :ok
    rescue => e
      Rails.logger.error('COE status request failed',
                         user_context.merge(error: e.message, backtrace: e.backtrace.first(5)))
      StatsD.increment("#{stats_key}.status.failure")
      raise
    end

    def download_coe
      res = lgy_service.get_coe_file
      StatsD.increment("#{stats_key}.download_coe.success")

      send_data(res.body, type: 'application/pdf', disposition: 'attachment')
    rescue => e
      Rails.logger.error('COE file download failed',
                         user_context.merge(error: e.message, backtrace: e.backtrace.first(5)))
      StatsD.increment("#{stats_key}.download_coe.failure")
      raise
    end

    def submit_coe_claim
      claim = SavedClaim::CoeClaim.new(form: filtered_params[:form])

      unless claim.save
        log_save_failed(claim)
        raise Common::Exceptions::ValidationErrors, claim
      end

      reference_number = claim.send_to_lgy(edipi: current_user.edipi, icn: current_user.icn)

      log_successful_submission(claim, reference_number)

      clear_saved_form(claim.form_id)
      render json: { data: { attributes: { reference_number:, claim: } } }
    rescue => e
      Rails.logger.error('COE claim submission failed',
                         user_context.merge(error: e.message, backtrace: e.backtrace.first(5)))
      StatsD.increment("#{stats_key}.submit_coe_claim.failure")
      raise
    end

    def documents
      documents = lgy_service.get_coe_documents.body
      # Vet-uploaded docs have documentType `Veteran Correspondence`. We are not
      # currently displaying these on the COE status page, so they are omitted.
      # In the near future, we will display them, and can remove this `reject`
      # block.
      notification_letters = documents.reject { |doc| doc['document_type']&.include?('Veteran Correspondence') }
      # Documents should be sorted from most to least recent
      sorted_notification_letters = notification_letters.sort_by { |doc| doc['create_date'] }.reverse

      Rails.logger.info('COE documents retrieved successfully',
                        user_context.merge(
                          total_documents: documents.length,
                          filtered_documents: sorted_notification_letters.length
                        ))
      StatsD.increment("#{stats_key}.documents.success")
      render json: { data: { attributes: sorted_notification_letters } }, status: :ok
    rescue => e
      Rails.logger.error('COE documents request failed',
                         user_context.merge(error: e.message, backtrace: e.backtrace.first(5)))
      StatsD.increment("#{stats_key}.documents.failure")
      raise
    end

    def document_upload
      log_upload_started
      status = 201

      attachments.each_with_index do |attachment, index|
        file_extension = attachment['file_type']

        if %w[jpg jpeg png pdf].include? file_extension.downcase
          log_uploading_document(index, attachment)
          document_data = build_document_data(attachment)
          status = post_document(document_data)
          break unless status == 201
        else
          log_invalid_file_type(attachment)
        end
      end

      log_by_status(status)
      render(json: status, status: status == 201 ? 200 : 500)
    rescue => e
      Rails.logger.error('COE document upload failed with exception',
                         user_context.merge(error: e.message, backtrace: e.backtrace.first(5)))
      StatsD.increment("#{stats_key}.document_upload.failure")
      raise
    end

    def post_document(document_data)
      Rails.logger.info('Posting document to LGY',
                        user_context.merge(
                          document_type: document_data['documentType'],
                          file_name: document_data['fileName']
                        ))

      response = lgy_service.post_document(payload: document_data)

      Rails.logger.info('Document posted to LGY successfully',
                        user_context.merge(
                          document_type: document_data['documentType'],
                          status: response.status
                        ))
      StatsD.increment("#{stats_key}.post_document.success")

      response.status
    rescue Common::Client::Errors::ClientError => e
      # 502-503 errors happen frequently from LGY endpoint at the time of implementation
      # and have not been corrected yet. We would like to seperate these from our monitoring for now
      # See https://va.ghe.com/software/va.gov-team/issues/90411
      # and https://va.ghe.com/software/va.gov-team/issues/91111
      if [503, 504].include?(e.status)
        log_lgy_unavailable(e, document_data)
      else
        log_lgy_returned_error(e, document_data)
      end
      e.status
    end

    def document_download
      Rails.logger.info('COE document download started',
                        user_context.merge(document_id: params[:id]))

      res = lgy_service.get_document(params[:id])

      Rails.logger.info('COE document download successful',
                        user_context.merge(
                          document_id: params[:id],
                          file_size: res.body.length
                        ))
      StatsD.increment("#{stats_key}.document_download.success")

      send_data(res.body, type: 'application/pdf', disposition: 'attachment')
    rescue => e
      Rails.logger.error('COE document download failed',
                         user_context.merge(
                           document_id: params[:id],
                           error: e.message,
                           backtrace: e.backtrace.first(5)
                         ))
      StatsD.increment("#{stats_key}.document_download.failure")
      raise
    end

    private

    def lgy_service
      @lgy_service ||= LGY::Service.new(edipi: @current_user.edipi, icn: @current_user.icn)
    end

    def user_context
      {
        user_uuid: @current_user&.uuid
      }
    end

    def log_by_status(status)
      if status == 201
        Rails.logger.info('COE document upload completed successfully',
                          user_context.merge(uploaded_count: attachments&.length || 0))
        StatsD.increment("#{stats_key}.document_upload.success")
      else
        Rails.logger.error('COE document upload failed',
                           user_context.merge(final_status: status))
        StatsD.increment("#{stats_key}.document_upload.failure")
      end
    end

    def log_save_failed(claim)
      Rails.logger.error('COE claim save failed',
                         user_context.merge(
                           validation_error_count: claim.errors.count,
                           failed_attributes: claim.errors.attribute_names
                         ))
    end

    def log_successful_submission(claim, reference_number)
      Rails.logger.info('COE claim submitted successfully',
                        user_context.merge(
                          claim_id: claim.confirmation_number,
                          form: claim.class::FORM,
                          reference_number:
                        ))
      StatsD.increment("#{stats_key}.submit_coe_claim.success")
    end

    def log_upload_started
      Rails.logger.info('COE document upload started',
                        user_context.merge(
                          attachment_count: attachments&.length || 0,
                          file_types: attachments&.map { |a| a['file_type'] }&.join(', ')
                        ))
    end

    def log_uploading_document(index, attachment)
      Rails.logger.info('Uploading document',
                        user_context.merge(
                          document_index: index + 1,
                          file_type: attachment['file_type'],
                          file_name: attachment['file_name']
                        ))
    end

    def log_invalid_file_type(attachment)
      Rails.logger.warn('Invalid file type for COE document upload',
                        user_context.merge(
                          file_type: attachment['file_type'],
                          file_name: attachment['file_name']
                        ))
    end

    def log_lgy_unavailable(e, document_data)
      Rails.logger.info('LGY server unavailable or unresponsive',
                        user_context.merge(
                          status: e.status,
                          message: e.message,
                          document_type: document_data['documentType']
                        ))
      StatsD.increment("#{stats_key}.post_document.lgy_unavailable")
    end

    def log_lgy_returned_error(e, document_data)
      Rails.logger.error('LGY API returned error',
                         user_context.merge(
                           status: e.status,
                           message: e.message,
                           body: e.body,
                           document_type: document_data['documentType']
                         ))
      StatsD.increment("#{stats_key}.post_document.lgy_error")
    end

    def filtered_params
      params.require(:lgy_coe_claim).permit(:form)
    end

    def attachments
      params[:files]
    end

    def stats_key
      'api.lgy_coe'
    end

    def build_document_data(attachment)
      file_data = attachment['file']
      index = file_data.index(';base64,') || 0
      file_data = file_data[(index + 8)..] if index.positive?

      {
        'documentType' => attachment['file_type'],
        'description' => attachment['document_type'],
        'contentsBase64' => file_data,
        'fileName' => attachment['file_name']
      }
    end
  end
end
