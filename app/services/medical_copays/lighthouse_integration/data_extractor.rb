# frozen_string_literal: true

require_relative 'exceptions'

module MedicalCopays
  module LighthouseIntegration
    module DataExtractor
      def extract_charge_item_ids(invoice_data)
        line_items = invoice_data['lineItem'] || []
        line_items.filter_map do |li|
          ref = li.dig('chargeItemReference', 'reference')
          extract_id_from_reference(ref) if ref
        end
      end

      def extract_org_id_from_invoice(invoice_data, optional_org_data: false)
        org_ref = invoice_data.dig('issuer', 'reference')
        return nil if optional_org_data && org_ref.blank?

        unless org_ref
          raise MedicalCopays::LighthouseIntegration::Exceptions::MissingOrganizationRefError,
                'No organization reference found'
        end

        org_id = org_ref.split('/').last
        unless org_id
          raise MedicalCopays::LighthouseIntegration::Exceptions::MissingOrganizationIdError,
                'No organization ID found'
        end

        org_id
      end

      def extract_id_from_reference(reference)
        return nil unless reference

        reference.split('/').last
      end

      def extract_statement_generated_day(account_data)
        return nil unless account_data

        extensions = account_data['extension'] || []
        statement_day_ext = extensions.find { |ext| ext['url'].include?('account-statementGeneratedDay') }
        return nil unless statement_day_ext

        statement_day_ext['valueInteger']&.to_i
      end
    end
  end
end
