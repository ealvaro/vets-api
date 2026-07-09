# frozen_string_literal: true

require 'vets/model'

module IvcChampva
  class VHA107959a2027
    ADDITIONAL_PDF_KEY = 'claims'
    ADDITIONAL_PDF_COUNT = 1
    STATS_KEY = 'api.ivc_champva_form.10_7959a'
    FORM_VERSION = 'vha_10_7959a_2027'

    include Vets::Model
    include Attachments
    include DataTransformations
    include ClaimsAttachmentIds
    include StampableLogging
    include SubmissionTracking

    attribute :data, Hash
    attr_reader :form_id

    def initialize(data)
      @data = data
      @uuid = SecureRandom.uuid
      @form_id = 'vha_10_7959a_2027'
    end

    def metadata
      name_prefix = Flipper.enabled?(:champva_update_metadata_keys) ? 'sponsor' : 'veteran'

      {
        "#{name_prefix}FirstName" => @data.dig('applicant_name', 'first'),
        "#{name_prefix}LastName" => @data.dig('applicant_name', 'last'),
        'zipCode' => @data.dig('applicant_address', 'postal_code'),
        'source' => 'VA Platform Digital Forms',
        'docType' => @data['form_number'],
        'businessLine' => 'CMP',
        'ssn_or_tin' => @data['applicant_member_number'],
        'member_number' => @data['applicant_member_number'],
        'fileNumber' => @data['applicant_member_number'],
        'country' => @data.dig('applicant_address', 'country') || 'USA',
        'uuid' => @uuid,
        'primaryContactInfo' => @data['primary_contact_info'],
        'primaryContactEmail' => @data.dig('primary_contact_info', 'email').to_s,
        'applicantEmail' => @data['applicant_email'].to_s,
        'signerEmail' => @data['certifier_email'].to_s,
        'formExpiration' => '12/31/2027'
      }.merge(add_resubmission_properties)
    end

    def add_resubmission_properties
      @data.slice('claim_status', 'pdi_or_claim_number', 'claim_type',
                  'provider_name', 'beginning_date_of_service',
                  'end_date_of_service', 'medication_name',
                  'prescription_fill_date')
           .merge(claim_number_fields)
    end

    def stamp_metadata
      return unless Flipper.enabled?(:champva_claims_duty_to_assist) && dta?

      { metadata: build_dta_metadata, attachment_id: 'Duty to Assist' }
    end

    def dta?
      @data['has_claim_docs'] == false
    end

    def build_dta_metadata
      {
        'provider_name' => @data['provider_name'],
        'provider_phone' => @data['provider_phone'],
        'provider_fax' => @data['provider_fax'],
        'provider_email' => @data['provider_email'],
        'service_start_date' => @data['service_start_date'],
        'service_end_date' => @data['service_end_date'],
        'additional_comments' => @data['additional_comments']
      }
    end

    def desired_stamps
      signature = data['statement_of_truth_signature']

      log_missing_stamp_data({
                               'statement_of_truth_signature' => {
                                 value: signature.present? ? 'present' : nil
                               }
                             })

      [{ coords: [250, 135], text: signature, page: 0 }]
    end

    def submission_date_stamps
      [
        {
          coords: [300, 105],
          text: Time.current.in_time_zone('UTC').strftime('%H:%M %Z %D'),
          page: 1,
          font_size: 12
        }
      ]
    end

    def track_user_identity
      identity = data['certifier_role']
      StatsD.increment("#{STATS_KEY}.#{identity}")
      Rails.logger.info('IVC ChampVA Forms - 10-7959A-2027 Submission User Identity', identity:)
    end

    def track_current_user_loa(current_user)
      current_user_loa = current_user&.loa&.[](:current) || 0
      StatsD.increment("#{STATS_KEY}.#{current_user_loa}")
      Rails.logger.info('IVC ChampVA Forms - 10-7959A-2027 Current User LOA', current_user_loa:)
    end

    def track_email_usage
      email_used = metadata&.dig('primaryContactInfo', 'email') ? 'yes' : 'no'
      StatsD.increment("#{STATS_KEY}.#{email_used}")
      Rails.logger.info('IVC ChampVA Forms - 10-7959A-2027 Email Used', email_used:)
    end

    def track_submission(current_user)
      fields = submission_fields(current_user).merge(
        form_version: FORM_VERSION,
        claim_status: @data['claim_status'],
        duty_to_assist: dta?,
        pdi_or_claim_number: @data['pdi_or_claim_number']
      )
      tags = fields.map { |k, v| "#{k}:#{v}" }
      StatsD.increment("#{STATS_KEY}.submission", tags:)
      Rails.logger.info('IVC ChampVA Forms - 10-7959A-2027 Submission', **fields)
    end

    # rubocop:disable Naming/BlockForwarding
    def method_missing(method_name, *args, &block)
      super unless respond_to_missing?(method_name)
      { method: method_name, args: }
    end
    # rubocop:enable Naming/BlockForwarding

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end

    private

    def claim_number_fields
      pdi_or_claim = @data['pdi_or_claim_number']
      identifying_number = @data['identifying_number']

      {
        'pdi_number' => pdi_or_claim == 'PDI number' ? identifying_number : '',
        'claim_number' => pdi_or_claim == 'Control number' ? identifying_number : ''
      }.compact_blank
    end
  end
end
