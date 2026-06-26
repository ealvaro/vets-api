# frozen_string_literal: true

module AppealsApi
  module PdfConstruction
    module SupplementalClaim
      module V4
        module Pages
          class AdditionalPages
            def initialize(pdf, form_data)
              @pdf = pdf # Prawn::Document
              @form_data = form_data
            end

            # rubocop:disable Metrics/MethodLength
            def build!
              pdf.start_new_page
              if form_data.veteran_long_email?
                pdf.text(
                  "\n<b>Veteran Email:</b>\n#{form_data.veteran_email}\n",
                  inline_format: true
                )
              end

              if form_data.veteran_long_email?
                pdf.text(
                  "\n<b>Claimant Email:</b>\n#{form_data.claimant_email}\n",
                  inline_format: true
                )
              end

              if (table_data = extra_issues_table_data).present?
                pdf.text("\n<b>Additional Issues</b>\n", inline_format: true)
                pdf.table(table_data, width: 540, header: true)
              end

              if (table_data = extra_locations_dates_table_data).present?
                pdf.text("\n<b>Additional Evidence Names and Locations</b>\n", inline_format: true)
                pdf.table(table_data, width: 540, header: true)
              end

              if form_data.long_signature?
                pdf.text(
                  "\n\n\n\n\n<b>Signature of veteran, claimant, or representative:</b>\n #{form_data.signature}",
                  inline_format: true
                )
              end

              pdf
            end
            # rubocop:enable Metrics/MethodLength

            private

            attr_accessor :pdf, :form_data

            def extra_issues_table_data
              data = form_data.contestable_issues.drop(Structure::MAX_ISSUES_ON_MAIN_FORM).map do |issue|
                [issue.text, issue.decision_date, issue.soc_date_formatted]
              end

              data.unshift(['A. Specific Issue(s)', 'B. Date of Decision', 'C. SOC/SSOC Date']) unless data.empty?
            end

            def extra_locations_dates_table_data
              locations = form_data.new_evidence_locations
              dates = form_data.new_evidence_dates
              no_dates = form_data.new_evidence_no_dates

              overflow_indices = locations.each_index.select do |i|
                i >= Structure::MAX_EVIDENCE_LOCATIONS_ON_MAIN_FORM ||
                  locations[i].length > FormData::LONG_EVIDENCE_LOCATION_THRESHOLD
              end

              data = overflow_indices.map do |i|
                [locations[i], dates[i].join(', '), no_dates[i]]
              end

              data.unshift(['A. Name and Location', 'B. Date(s) of Records', "Don't have date"]) unless data.empty?
            end
          end
        end
      end
    end
  end
end
