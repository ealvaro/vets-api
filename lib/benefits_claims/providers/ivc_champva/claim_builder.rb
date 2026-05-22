# frozen_string_literal: true

require 'benefits_claims/claim_status_meta/config_loader'
require 'benefits_claims/responses/claim_response'
require 'benefits_claims/title_generator'

module BenefitsClaims
  module Providers
    module IvcChampva
      # rubocop:disable Metrics/ModuleLength
      module ClaimBuilder
        FORM_TYPE_MAP = {
          'vha1010d' => 'CHAMPVA application',
          'vha_10_10d' => 'CHAMPVA application',
          'vha_10_10d_2027' => 'CHAMPVA application',
          '10-10d' => 'CHAMPVA application',
          '10-10d-extended' => 'CHAMPVA application',
          '10-10d-extended-existing' => 'CHAMPVA application',
          '10-10d-extended-enrollment' => 'CHAMPVA application',
          '10-7959c' => 'Other Health Insurance',
          '10-7959f-1' => 'Foreign Medical Program registration',
          '10-7959f-2' => 'Foreign Medical Program claim',
          '10-7959a' => 'CHAMPVA claim'
        }.freeze

        PROCESSED_STATUSES = ['processed', 'manually processed'].freeze
        CLAIM_RECEIVED_STATUSES = [
          'received',
          'submission received',
          # Applicant action required — non-terminal; applicant may respond and receive a follow-up status
          'additional documentation requested'
        ].freeze
        COMPLETE_STATUSES = [
          'eligiblity denied/additional information needed',  # misspelled — current Pega API
          'eligibility denied/additional information needed', # correctly-spelled — future-proof
          'eligible - issued a card',
          'duplicate application',
          'eligible - reissued a card',
          'processed - eligiblity determination unknown',
          'processed - eligibility determination unknown',
          'document identification error'
        ].freeze
        INTERNAL_DOCS_ONLY_1010D_FILE_NAME_PATTERN = /_vha_10_10d(?:_supporting_doc-\d+)?\.pdf\z/i

        def self.build_claim_response(records, user = nil)
          records = Array(records)
          representative = pick_representative(records)
          claim_type = claim_type_for(representative&.form_number)
          titles = BenefitsClaims::TitleGenerator.generate_titles(claim_type, nil)
          status = status_for(records)

          BenefitsClaims::Responses::ClaimResponse.new(
            id: representative&.form_uuid,
            provider: 'ivc_champva',
            claim_date: format_date(records.min_by(&:created_at)&.created_at),
            claim_phase_dates: claim_phase_dates_for(representative, status),
            close_date: close_date_for(representative),
            claim_type:,
            decision_letter_sent: status == 'vbms',
            display_title: titles[:display_title],
            claim_type_base: titles[:claim_type_base],
            status:,
            claim_status_meta: build_claim_status_meta(records, status, user),
            supporting_documents: build_supporting_documents(records)
          )
        end

        def self.pick_representative(records)
          records.max_by(&:updated_at)
        end

        def self.claim_type_for(form_number)
          normalized = normalize_form_number(form_number)
          FORM_TYPE_MAP[normalized] || form_number
        end

        def self.normalize_form_number(value)
          value.to_s.strip.downcase
        end

        def self.status_for(records)
          representative = pick_representative(records)
          normalize_status(representative&.pega_status, form_uuid: representative&.form_uuid)
        end

        def self.close_date_for(record)
          normalized = record&.pega_status.to_s.downcase.strip
          terminal = PROCESSED_STATUSES.include?(normalized) || COMPLETE_STATUSES.include?(normalized)
          return nil unless normalized.present? && terminal

          format_date(record.updated_at)
        end

        def self.claim_phase_dates_for(representative, status)
          {
            phase_change_date: format_date(representative&.updated_at),
            phase_type: phase_type_for_status(status)
          }
        end

        def self.build_supporting_documents(records)
          records.reject { |record| internal_docs_only_artifact?(record) }.map do |record|
            BenefitsClaims::Responses::SupportingDocument.new(
              document_id: record.id.to_s,
              document_type_label: nil,
              original_file_name: record.file_name,
              tracked_item_id: nil,
              upload_date: format_datetime(record.created_at)
            )
          end
        end

        def self.internal_docs_only_artifact?(record)
          form_number = record.form_number.to_s
          file_name = record.file_name.to_s

          form_number.start_with?('10-10D-EXTENDED-') && file_name.match?(INTERNAL_DOCS_ONLY_1010D_FILE_NAME_PATTERN)
        end

        def self.format_date(value)
          value&.to_date&.iso8601
        end

        def self.format_datetime(value)
          value&.iso8601
        end

        def self.normalize_status(pega_status, form_uuid: nil)
          normalized = pega_status.to_s.downcase.strip
          return 'pending' if normalized.blank?
          return 'vbms' if PROCESSED_STATUSES.include?(normalized)
          return 'claimReceived' if CLAIM_RECEIVED_STATUSES.include?(normalized)
          return 'complete' if COMPLETE_STATUSES.include?(normalized)

          Rails.logger.warn(
            '[BenefitsClaims::Providers::IvcChampva::ClaimBuilder] Unrecognized pega_status received',
            { form_uuid:, raw_pega_status: pega_status }
          )
          'error'
        end

        def self.build_claim_status_meta(records, status, user)
          return nil unless include_champva_custom_content?(user)

          base_meta = load_base_metadata
          veteran_name = [user&.first_name, user&.last_name].compact.join(' ').strip
          applicant_names = records.map do |record|
            [record.first_name, record.last_name].compact.join(' ').strip
          end.compact_blank.uniq

          detail_groups = []
          detail_groups << { 'title' => 'Veteran', 'items' => [veteran_name] } if veteran_name.present?
          detail_groups << { 'title' => 'Applicants', 'items' => applicant_names } if applicant_names.any?

          base_meta['detail'] ||= {}
          base_meta['detail']['sectionGroups'] = detail_groups

          base_meta['whatWeAreDoing'] ||= {}
          base_meta['whatWeAreDoing']['currentStatus'] = status

          base_meta
        end

        def self.include_champva_custom_content?(user)
          return true unless defined?(Flipper)

          Flipper.enabled?(:cst_champva_custom_content, user)
        end

        def self.load_base_metadata
          BenefitsClaims::ClaimStatusMeta::ConfigLoader.load(provider: :ivc_champva)
        rescue ArgumentError => e
          Rails.logger.error(
            '[BenefitsClaims::Providers::IvcChampva::ClaimBuilder] Failed to load metadata config',
            { message: e.message }
          )
          {}
        end

        def self.phase_type_for_status(status)
          return 'COMPLETE' if %w[vbms complete].include?(status)
          return 'REVIEW_OF_EVIDENCE' if status == 'error'

          'UNDER_REVIEW'
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
