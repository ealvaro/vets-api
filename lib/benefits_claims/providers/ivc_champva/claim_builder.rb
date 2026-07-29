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
          '10-10d-supplemental' => 'CHAMPVA application',
          '10-10d-supplemental-existing' => 'CHAMPVA application',
          '10-10d-supplemental-enrollment' => 'CHAMPVA application',
          '10-7959c' => 'Other Health Insurance',
          '10-7959f-1' => 'Foreign Medical Program registration',
          '10-7959f-2' => 'Foreign Medical Program claim',
          '10-7959a' => 'CHAMPVA claim'
        }.freeze

        PROCESSED_STATUSES = ['processed', 'manually processed'].freeze
        CLAIM_RECEIVED_STATUSES = [
          'received',
          'submission received',
          # Set by CST file uploader after successful S3 upload, before PEGA picks it up
          'submitted',
          # Applicant action required — non-terminal; applicant may respond and receive a follow-up status
          'additional documentation requested'
        ].freeze
        INTERNAL_DOCS_ONLY_1010D_FILE_NAME_PATTERN = /_vha_10_10d_supporting_doc-\d+\.pdf\z/i

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
          return 'complete' if IvcChampvaApplicant.all_resolved_for?(representative&.transaction_uuid)

          normalize_status(representative&.pega_status, form_uuid: representative&.form_uuid)
        end

        # Returns true when VES has been queried (at least one applicant exists) and every
        # applicant for the given transaction UUID has received an eligibility determination.
        def self.close_date_for(record)
          return format_date(record.updated_at) if IvcChampvaApplicant.all_resolved_for?(record&.transaction_uuid)

          normalized = record&.pega_status.to_s.downcase.strip
          return nil unless normalized.present? && PROCESSED_STATUSES.include?(normalized)

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
          file_name = record.file_name.to_s
          file_name.match?(INTERNAL_DOCS_ONLY_1010D_FILE_NAME_PATTERN)
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
          applicant_names = applicant_names_for(records)
          normalized_veteran_name = normalize_name(veteran_name)
          applicant_names = applicant_names.reject do |name|
            normalized_veteran_name.present? && normalize_name(name) == normalized_veteran_name
          end

          detail_groups = []
          detail_groups << { 'title' => 'Veteran', 'items' => [veteran_name] } if veteran_name.present?
          detail_groups << { 'title' => 'Applicants', 'items' => applicant_names } if applicant_names.any?

          base_meta['detail'] ||= {}
          base_meta['detail']['sectionGroups'] = detail_groups

          base_meta['whatWeAreDoing'] ||= {}
          base_meta['whatWeAreDoing']['currentStatus'] = status

          base_meta
        end

        def self.applicant_names_for(records)
          names = records.flat_map { |record| applicant_names_from_request_json(record) }.compact_blank.uniq
          return names if names.any?

          records.map do |record|
            [record.first_name, record.last_name].compact.join(' ').strip
          end.compact_blank.uniq
        end

        def self.applicant_names_from_request_json(record)
          payload = parse_request_json(record&.request_json)
          applicants = payload['applicants'] || payload[:applicants]
          return [] unless applicants.is_a?(Array)

          applicants.map do |applicant|
            name = if applicant.is_a?(Hash)
                     applicant['applicantName'] || applicant[:applicantName] ||
                       applicant['applicant_name'] || applicant[:applicant_name]
                   end
            next nil unless name.is_a?(Hash)

            [
              name['first'] || name[:first],
              name['last'] || name[:last]
            ].compact.join(' ').strip
          end.compact_blank
        end

        def self.parse_request_json(request_json)
          return request_json if request_json.is_a?(Hash)
          return {} if request_json.blank?

          JSON.parse(request_json)
        rescue JSON::ParserError
          {}
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

        def self.normalize_name(value)
          value.to_s.strip.downcase.gsub(/\s+/, ' ')
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
