# frozen_string_literal: true

module V0
  class EducationBenefitsClaimsController < ApplicationController
    service_tag 'education-forms'
    skip_before_action(:authenticate)
    before_action :load_user

    def create
      claim = SavedClaim::EducationBenefits.form_class(form_type).new(education_benefits_claim_params)

      raise Common::Exceptions::Unauthorized if claim.requires_authenticated_user? && !@current_user

      claim.user_account = @current_user&.user_account
      claim.delete_date = Time.zone.now + claim.retention_period if claim.retention_period

      unless claim.save
        StatsD.increment("#{stats_key('create')}.failure")
        StatsD.increment("#{stats_key("create.22#{form_type}")}.failure")
        Rails.logger.error("EBCC::create Failed to create claim 22#{form_type}",
                           form_type:,
                           errors: claim.errors.full_messages)
        raise Common::Exceptions::ValidationErrors, claim
      end

      StatsD.increment("#{stats_key('create')}.success")
      StatsD.increment("#{stats_key("create.22#{form_type}")}.success")
      Rails.logger.info "ClaimID=#{claim.id} RPO=#{claim.education_benefits_claim.region} Form=#{form_type}"

      claim.after_submit(@current_user)
      clear_saved_form(claim.in_progress_form_id)
      render json: EducationBenefitsClaimSerializer.new(claim.education_benefits_claim)
    end

    def download_pdf
      education_claim = EducationBenefitsClaim.find_by!(token: params[:id])
      saved_claim = SavedClaim.find(education_claim.saved_claim_id)

      # Use the claim's own #to_pdf (not PdfFill::Filler.fill_form directly) so that
      # per-form overrides -- e.g. VA0803's extras_redesign/omit_esign_stamp/placeholder
      # options for ExtrasGeneratorV2 overflow pages -- are honored on this download path.
      source_file_path = saved_claim.to_pdf(SecureRandom.uuid)

      client_file_name = "education_benefits_claim_#{saved_claim.id}.pdf"
      file_contents = File.read(source_file_path)

      send_data file_contents,
                filename: client_file_name,
                type: 'application/pdf',
                disposition: 'attachment'
      StatsD.increment("#{stats_key('pdf_download')}.22#{education_claim.form_type}.success")
    rescue => e
      StatsD.increment("#{stats_key('pdf_download')}.failure")
      Rails.logger.error "EBCC::download_pdf Failed to download pdf ClaimID=#{params[:id]} #{e.message}"
      raise e
    ensure
      File.delete(source_file_path) if source_file_path && File.exist?(source_file_path)
    end

    private

    def form_type
      params[:form_type] || '1990'
    end

    def education_benefits_claim_params
      params.require(:education_benefits_claim).permit(:form)
    end

    def stats_key(action)
      "api.education_benefits_claim.#{action}"
    end
  end
end
