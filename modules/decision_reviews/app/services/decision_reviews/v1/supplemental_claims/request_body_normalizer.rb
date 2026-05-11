# frozen_string_literal: true

module DecisionReviews
  module V1
    module SupplementalClaims
      # Service class that encapsulates all schema transformation logic for
      # Supplemental Claims request bodies. Transforms frontend payload format
      # to match the Lighthouse API schema.
      class RequestBodyNormalizer
        def initialize(request_body)
          @request_body = request_body
          @redesign = sc_redesign_enabled?
        end

        def normalize
          if @redesign
            format_evidence_data_for_lighthouse_schema
            @request_body['form4142'] = format_private_evidence_entries(@request_body['form4142'])
          end

          normalize_evidence_retrieval_for_lighthouse_schema
          normalize_area_code_for_lighthouse_schema

          @request_body
        end

        private

        # Schema reference: https://va.ghe.com/software/vets-json-schema/blob/master/src/schemas/SC-create-request-body_v1/schema.json#L193-L201
        def set_evidence_types(evidence_submission, has_uploaded_evidence, has_va_evidence)
          evidence_submission['evidenceType'] << 'retrieval' if has_va_evidence
          evidence_submission['evidenceType'] << 'upload' if has_uploaded_evidence
          evidence_submission['evidenceType'] << 'none' if !has_uploaded_evidence && !has_va_evidence

          evidence_submission
        end

        # Schema reference: https://va.ghe.com/software/vets-json-schema/blob/master/src/schemas/SC-create-request-body_v1/schema.json#L173-L192
        def set_treatment_locations(evidence_submission)
          treatment_locations = @request_body.dig('data', 'attributes', 'treatmentLocations')
          treatment_location_other = @request_body.dig('data', 'attributes', 'treatmentLocationOther')

          if treatment_locations.is_a?(Array) && treatment_locations.any?
            evidence_submission['treatmentLocations'] = treatment_locations
          end

          if treatment_location_other.is_a?(String) && !treatment_location_other.empty?
            evidence_submission['treatmentLocationOther'] = treatment_location_other
          end

          # Remove treatmentLocations and treatmentLocationOther from their original location
          # since they have moved into evidenceSubmission
          @request_body['data']['attributes'].delete('treatmentLocations')
          @request_body['data']['attributes'].delete('treatmentLocationOther')

          evidence_submission
        end

        # Schema reference: https://va.ghe.com/software/vets-json-schema/blob/master/src/schemas/SC-create-request-body_v1/schema.json#L203-L238
        def set_va_evidence(evidence_submission, va_evidence)
          formatted_va_evidence = format_va_evidence_entries(va_evidence)
          evidence_submission['retrieveFrom'] = formatted_va_evidence
          evidence_submission
        end

        # For the new array builder UI, we are passing the raw FE evidence data as-is to the BE,
        # so we need to transform it to match the Lighthouse schema here
        def format_evidence_data_for_lighthouse_schema
          evidence_submission = { 'evidenceType' => [] }

          uploaded_evidence = @request_body['additionalDocuments']
          va_evidence = @request_body.dig('data', 'attributes', 'vaEvidence')

          has_uploaded_evidence = uploaded_evidence.is_a?(Array) && uploaded_evidence.any?
          has_va_evidence = va_evidence.is_a?(Array) && va_evidence.any?

          set_evidence_types(evidence_submission, has_uploaded_evidence, has_va_evidence)
          set_treatment_locations(evidence_submission)
          set_va_evidence(evidence_submission, va_evidence) if has_va_evidence

          @request_body['data']['attributes']['evidenceSubmission'] = evidence_submission

          # Remove vaEvidence from its original location since it has moved into evidenceSubmission
          @request_body['data']['attributes'].delete('vaEvidence')
        end

        def validate_and_format_va_treatment_date(date_string)
          return nil unless date_string.match?(/^\d{4}-\d{2}$/)

          "#{date_string}-01"
        end

        def format_va_evidence_entries(va_evidence)
          return if va_evidence.blank?

          va_evidence.map { |entry| build_va_evidence_entry(entry) }
        end

        def build_va_evidence_entry(entry)
          treated_pre2005 = entry['treatmentBefore2005'] == 'Y'
          evidence_dates = format_va_evidence_dates(entry) if treated_pre2005

          attributes = { 'locationAndName' => entry['vaTreatmentLocation'] }
          attributes['evidenceDates'] = evidence_dates if evidence_dates
          attributes['noTreatmentDates'] = !treated_pre2005 || evidence_dates.nil?

          { 'type' => 'retrievalEvidence', 'attributes' => attributes }
        end

        def format_va_evidence_dates(entry)
          treatment_date = validate_and_format_va_treatment_date(entry['treatmentMonthYear'].to_s)
          return unless treatment_date

          [{ 'startDate' => treatment_date, 'endDate' => treatment_date }]
        end

        def make_issues_list(issues_hash)
          return [] if issues_hash.blank?

          issues_hash.select { |_key, value| value == true }.keys
        end

        def format_private_evidence_entries(private_evidence)
          return if private_evidence.blank?

          authorization = private_evidence['authorization']
          limited_consent_prompt = private_evidence['lcPrompt']
          limited_consent_details = private_evidence['lcDetails']
          evidence_entries = private_evidence['evidenceEntries']

          private_evidence_data = { 'providerFacility' => [] }

          # Set top-level fields once (not per-facility)
          private_evidence_data['privacyAgreementAccepted'] = true if authorization
          if limited_consent_prompt && limited_consent_details.present?
            private_evidence_data['limitedConsent'] = limited_consent_details
          end

          return private_evidence_data unless evidence_entries.is_a?(Array)

          evidence_entries.each do |entry|
            private_evidence_data['providerFacility'] << build_facility_data(entry)
          end

          private_evidence_data
        end

        def build_facility_data(entry)
          {
            'providerFacilityName' => entry['privateTreatmentLocation'] || '',
            'providerFacilityAddress' => {
              'country' => entry.dig('address', 'country') || '',
              'street' => entry.dig('address', 'street') || '',
              'street2' => entry.dig('address', 'street2') || '',
              'city' => entry.dig('address', 'city') || '',
              'state' => entry.dig('address', 'state') || '',
              'postalCode' => entry.dig('address', 'postalCode') || ''
            },
            'issues' => make_issues_list(entry['issues']),
            'treatmentDateRange' => [{
              'from' => entry['treatmentStart'] || '',
              'to' => entry['treatmentEnd'] || ''
            }]
          }
        end

        def normalize_area_code_for_lighthouse_schema
          phone = @request_body.dig('data', 'attributes', 'veteran', 'phone')
          area_code = phone&.dig('areaCode')

          return if area_code.is_a?(String) && !area_code.empty?

          phone_hash = @request_body.dig('data', 'attributes', 'veteran', 'phone')
          phone_hash.delete('areaCode') if phone_hash.is_a?(Hash)
        end

        # To conform to the LH schema, we need to ensure that if the evidenceType includes 'retrieval',
        # then the retrieveFrom array must have facilities with unique facility location names
        def normalize_evidence_retrieval_for_lighthouse_schema
          evidence_submission = @request_body.dig('data', 'attributes', 'evidenceSubmission')
          evidence_type = evidence_submission&.dig('evidenceType')
          retrieve_from = evidence_submission&.dig('retrieveFrom')

          # Return if evidenceType is nil or doesn't include 'retrieval'
          return unless evidence_type.is_a?(Array) && evidence_type.include?('retrieval')
          # Return if retrieveFrom is nil, not an array, or only one item
          return unless retrieve_from.is_a?(Array) && retrieve_from.length > 1

          grouped_entries = retrieve_from.group_by do |entry|
            entry.dig('attributes', 'locationAndName')
          end

          merged_entries = grouped_entries.map do |_, entries|
            if entries.length == 1
              entries.first
            else
              merge_evidence_entries(entries)
            end
          end

          @request_body['data']['attributes']['evidenceSubmission']['retrieveFrom'] = merged_entries
        end

        def merge_evidence_entries(entries)
          merged_entry = entries.first.deep_dup
          merged_attributes = merged_entry['attributes']

          all_evidence_dates = []
          entries.each do |entry|
            attributes = entry['attributes']
            if attributes && attributes['evidenceDates'].is_a?(Array)
              all_evidence_dates.concat(attributes['evidenceDates'])
            end
          end

          unique_evidence_dates = all_evidence_dates.uniq.sort_by { |date_range| date_range['startDate'] }

          # Apply schema constraints (maxItems: 4) -- this should be unlikely,
          # as we should only be collecting dates for pre-2005 treatment
          unique_evidence_dates = unique_evidence_dates.first(4)

          # Only set evidenceDates if we have dates to include
          # Lighthouse accepts missing evidenceDates key but rejects empty array
          merged_attributes['evidenceDates'] = unique_evidence_dates unless unique_evidence_dates.empty?
          merged_entry
        end

        # Gate on payload value, not Flipper toggle. This ensures users who started
        # forms under the redesign can complete submissions even if toggle is turned off.
        def sc_redesign_enabled?
          ActiveModel::Type::Boolean.new.cast(@request_body['scRedesign'])
        end
      end
    end
  end
end
