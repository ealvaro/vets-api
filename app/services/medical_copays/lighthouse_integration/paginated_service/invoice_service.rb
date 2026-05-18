# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module PaginatedService
      class InvoiceService
        include PagedResource

        # TODO: move collect_invoices_in_range here (mirror ChargeItemService)
      end
    end
  end
end
