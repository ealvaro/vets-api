# frozen_string_literal: true

module Mobile
  module V0
    ##
    # JSONAPI serializer for a Veteran's diagnostic reports (labs and tests) in
    # the mobile (v0) response shape, exposing category, code, subject, dates,
    # and result.
    #
    class DiagnosticReportsSerializer
      include JSONAPI::Serializer

      set_type :diagnostic_report

      attributes :category,
                 :code,
                 :subject,
                 :effectiveDateTime,
                 :issued,
                 :result
    end
  end
end
