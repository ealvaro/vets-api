# frozen_string_literal: true

require 'benefits_claims/claim_status_meta/config_loader'
require 'benefits_claims/responses/claim_response'
require 'benefits_claims/title_generator'
require 'benefits_claims/providers/ivc_champva/ves_reason_translator'
require 'benefits_claims/providers/ivc_champva/repeat_ineligibility_letter_activity'

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

        INTERNAL_DOCS_ONLY_1010D_FILE_NAME_PATTERN = /_vha_10_10d_supporting_doc-\d+\.pdf\z/i

        def self.build_claim_response(records, user = nil)
          records = Array(records)
          representative = pick_representative(records)
          eligibility_transaction_uuid = transaction_uuid_for(records, representative)
          all_resolved = IvcChampvaApplicant.all_resolved_for?(eligibility_transaction_uuid)
          status = status_for(all_resolved)
          champva_applicants, champva_sponsor, application_decided, ves_status_updated_date,
            repeat_ineligibility_alert = champva_eligibility_summary(eligibility_transaction_uuid, user)

          BenefitsClaims::Responses::ClaimResponse.new(
            **claim_response_attributes(records, representative, status, user, all_resolved),
            cst_champva_applicants: champva_applicants,
            cst_champva_sponsor: champva_sponsor,
            application_decided:,
            ves_status_updated_date:,
            repeat_ineligibility_alert:
          )
        end

        def self.claim_response_attributes(records, representative, status, user, all_resolved)
          claim_type = claim_type_for(representative&.form_number)
          titles = BenefitsClaims::TitleGenerator.generate_titles(claim_type, nil)
          {
            id: representative&.form_uuid,
            provider: 'ivc_champva',
            claim_date: format_date(records.min_by(&:created_at)&.created_at),
            claim_phase_dates: claim_phase_dates_for(representative, status),
            close_date: close_date_for(representative, all_resolved),
            claim_type:,
            decision_letter_sent: status == 'complete',
            display_title: titles[:display_title],
            claim_type_base: titles[:claim_type_base],
            status:,
            claim_status_meta: build_claim_status_meta(records, status, user),
            supporting_documents: build_supporting_documents(records)
          }
        end

        def self.pick_representative(records)
          records.max_by(&:updated_at)
        end

        # Prefer latest row with a transaction_uuid. file-upload rows have none (FormRecorder#insert_form).
        def self.transaction_uuid_for(records, representative)
          return representative.transaction_uuid if representative&.transaction_uuid.present?

          records.select { |record| record.transaction_uuid.present? }.max_by(&:updated_at)&.transaction_uuid
        end

        def self.claim_type_for(form_number)
          normalized = normalize_form_number(form_number)
          FORM_TYPE_MAP[normalized] || form_number
        end

        def self.normalize_form_number(value)
          value.to_s.strip.downcase
        end

        def self.status_for(all_resolved)
          all_resolved ? 'complete' : 'claimReceived'
        end

        def self.close_date_for(record, all_resolved)
          format_date(record.updated_at) if all_resolved
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

        def self.build_claim_status_meta(records, status, user)
          return nil unless include_champva_custom_content?(user)

          base_meta = load_base_metadata
          apply_detail_groups!(base_meta, records, user)

          base_meta['whatWeAreDoing'] ||= {}
          base_meta['whatWeAreDoing']['currentStatus'] = status

          base_meta
        end

        def self.apply_detail_groups!(base_meta, records, user)
          veteran_name = [user&.first_name, user&.last_name].compact.join(' ').strip
          normalized_veteran_name = normalize_name(veteran_name)
          applicant_names = applicant_names_for(records).reject do |name|
            normalized_veteran_name.present? && normalize_name(name) == normalized_veteran_name
          end

          detail_groups = []
          detail_groups << { 'title' => 'Veteran', 'items' => [veteran_name] } if veteran_name.present?
          detail_groups << { 'title' => 'Applicants', 'items' => applicant_names } if applicant_names.any?

          base_meta['detail'] ||= {}
          base_meta['detail']['sectionGroups'] = detail_groups
        end

        # Single applicant/sponsor path: consumed at the response root (cstChampvaApplicants/
        # cstChampvaSponsor) rather than duplicated under claimStatusMeta. repeatIneligibilityAlert
        # is likewise a single response-root field, not duplicated onto each applicant, since it
        # speaks to the application's decision as a whole and may name more than one applicant.
        def self.champva_eligibility_summary(transaction_uuid, user)
          return [[], nil, nil, nil, nil] unless ves_eligibility_on_demand?(user)
          return [[], nil, nil, nil, nil] if transaction_uuid.blank?

          applicants = applicants_for(transaction_uuid)
          decided = applicants.any? && applicants.all?(&:eligibility_resolved)
          ves_date = decided ? format_date(applicants.filter_map(&:ves_status_updated_date).max) : nil

          repeat_letter_data_by_applicant = repeat_letter_data_by_applicant_for(applicants)
          repeat_ineligibility_alert = repeat_ineligibility_alert_for(applicants, repeat_letter_data_by_applicant)

          [
            build_applicant_data(applicants, repeat_letter_data_by_applicant),
            sponsor_details_for(transaction_uuid),
            decided,
            ves_date,
            repeat_ineligibility_alert
          ]
        end

        def self.build_applicant_data(applicants, repeat_letter_data_by_applicant)
          applicants.map do |applicant|
            applicant_data_hash(applicant, repeat_letter_data_by_applicant[applicant])
          end
        end

        # @return [Hash{IvcChampvaApplicant => Hash}] each applicant's RepeatIneligibilityLetterActivity.evaluate result
        def self.repeat_letter_data_by_applicant_for(applicants)
          applicants.index_with { |applicant| RepeatIneligibilityLetterActivity.evaluate(applicant) }
        end

        # Shared across every flagged applicant on this application — names all of them, not just one.
        #
        # @return [Hash, nil]
        def self.repeat_ineligibility_alert_for(applicants, repeat_letter_data_by_applicant)
          flagged = applicants.select do |applicant|
            repeat_letter_data_by_applicant[applicant]['hasRepeatIneligibilityLetter']
          end
          RepeatIneligibilityLetterActivity.alert_for(flagged)
        end

        # vesEligibilityReason is intentionally left as the applicant's normal plain-language
        # reason (from ves_eligibility_reason_map.json via VesReasonTranslator) even when
        # hasRepeatIneligibilityLetter is true — repeat-letter activity is surfaced entirely via
        # the response-root repeatIneligibilityAlert (a separate alert card on the FE), not by
        # overriding the existing eligibility card's body text.
        def self.applicant_data_hash(applicant, repeat_letter_data)
          applicant_eligibility_hash(applicant).merge(
            'personType' => applicant.person_type,
            'documentsRequested' => applicant.documents_requested,
            'vesStatusUpdatedDate' => format_date(applicant.ves_status_updated_date),
            'letters' => letters_for(applicant)
          ).merge(repeat_letter_data)
        end

        # @return [Array<Hash>] this applicant's mail-correspondence letters, oldest first
        def self.letters_for(applicant)
          applicant.ivc_champva_letters.sort_by(&:mail_status_date).map do |letter|
            {
              'formNumber' => letter.form_number,
              'letterName' => letter.letter_name,
              'mailStatus' => letter.mail_status,
              'mailStatusDate' => format_datetime(letter.mail_status_date)
            }
          end
        end

        # @return [Array<IvcChampvaApplicant>]
        def self.applicants_for(transaction_uuid)
          IvcChampvaApplicant.where(transaction_uuid:).order(:created_at).includes(:ivc_champva_letters).to_a
        end

        # Common applicant fields merged into build_applicant_data's output.
        def self.applicant_eligibility_hash(applicant)
          reason, link = reason_and_link_for(applicant.ves_eligibility_reason, applicant.applicant_first_name)
          {
            'firstName' => applicant.applicant_first_name,
            'lastName' => applicant.applicant_last_name,
            'vesEligibilityStatus' => applicant.ves_eligibility_status,
            'vesEligibilityReason' => reason,
            'vesEligibilityReasonLink' => link
          }
        end

        def self.sponsor_details_for(transaction_uuid)
          return nil if transaction_uuid.blank?

          sponsor = IvcChampvaSponsor.find_by(transaction_uuid:)
          return nil if sponsor.blank?

          reason, link = reason_and_link_for(sponsor.reason, sponsor.first_name)
          {
            'firstName' => sponsor.first_name,
            'lastName' => sponsor.last_name,
            'eligibilityStatus' => sponsor.eligibility_status,
            'eligibilityReason' => reason,
            'eligibilityReasonLink' => link
          }
        end

        # Shared by applicant_eligibility_hash and sponsor_details_for so translation/link lookup
        # only happens in one place.
        def self.reason_and_link_for(raw_reason, first_name)
          [translate_ves_reason(raw_reason, first_name), ves_eligibility_reason_link_for(raw_reason)]
        end

        def self.translate_ves_reason(raw_reason, first_name = nil)
          VesReasonTranslator.translate(raw_reason, first_name)
        end

        def self.ves_eligibility_reason_link_for(raw_reason)
          VesReasonTranslator.link_for(raw_reason)
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

        def self.ves_eligibility_on_demand?(user)
          return false unless defined?(Flipper)

          Flipper.enabled?(:ivc_champva_ves_eligibility_on_demand, user)
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
          status == 'complete' ? 'COMPLETE' : 'UNDER_REVIEW'
        end

        def self.normalize_name(value)
          value.to_s.strip.downcase.gsub(/\s+/, ' ')
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
