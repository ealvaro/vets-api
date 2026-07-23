# frozen_string_literal: true

require 'pensions/engine'

##
# Pension 21P-527EZ Module
#
module Pensions
  # The form_id
  FORM_ID = '21P-527EZ'

  # The module path
  MODULE_PATH = 'modules/pensions'

  # Path to the V1 PDF
  V1_PDF_PATH = "#{MODULE_PATH}/lib/pensions/pdf_fill/pdfs/#{FORM_ID}.pdf".freeze
  # Path to the V2 PDF
  V2_PDF_PATH = "#{MODULE_PATH}/lib/pensions/pdf_fill/pdfs/#{FORM_ID}-V2.pdf".freeze

  # Whether flipper is enabled to use V2 PDF
  def self.use_v2?
    Flipper.enabled?(:pension_pdf_form_alignment)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    false
  end

  # PDF path depending on if V1 or V2 enabled
  def self.pdf_path
    Flipper.enabled?(:pension_pdf_form_alignment) ? V2_PDF_PATH : V1_PDF_PATH
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    V1_PDF_PATH
  end

  # API Version 0
  module V0
  end

  # BenefitsIntake
  # @see lib/lighthouse/benefits_intake
  module BenefitsIntake
  end

  # PdfFill
  # @see lib/pdf_fill
  module PdfFill
  end

  # ZeroSilentFailures
  # @see lib/zero_silent_failures
  module ZeroSilentFailures
  end
end
