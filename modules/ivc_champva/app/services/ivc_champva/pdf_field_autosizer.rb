# frozen_string_literal: true

require 'hexapdf'

module IvcChampva
  # Sets the font size to "auto" (0) on known single-line, narrow street-address fields
  # so pdftk shrinks the text to fit the field's width instead of clipping it when an
  # address uses all three street lines. See #152932.
  module PdfFieldAutosizer
    AUTOSIZE_FIELDS = {
      'vha_10_10d' => %w[
        form1[0].#subform[0].VeteransStreetAddress[0]
        form1[0].#subform[0].StreetAddress1[0]
        form1[0].#subform[0].StreetAddress2[0]
        form1[0].#subform[0].StreetAddress3[0]
        form1[0].#subform[0].StreetAddress4[0]
      ].freeze,
      'vha_10_10d_2027' => %w[
        form1[0].#subform[0].STREETADDRESS[0]
        form1[0].#subform[0].APPLICANTSTREETADDRESS1[0]
        form1[0].#subform[0].APPLICANTSTREETADDRESS2[0]
        form1[0].#subform[0].APPLICANTSTREETADDRESS3[0]
        form1[0].#subform[0].OTHERTSTREETADDRESS[0]
      ].freeze,
      'vha_10_7959c' => %w[
        form1[0].#subform[0].applicantStreetAddress2[0]
      ].freeze,
      'vha_10_7959c_rev2025' => %w[
        form1[0].#subform[0].applicantStreetAddress2[0]
      ].freeze
    }.freeze

    def self.apply!(template_path, form_number)
      field_names = AUTOSIZE_FIELDS[form_number]
      return if field_names.blank?

      doc = HexaPDF::Document.open(template_path)
      acro_form = doc.acro_form
      return if acro_form.blank?

      fields_by_name = acro_form.each_field.index_by(&:full_field_name)
      changed = false

      field_names.each do |name|
        field = fields_by_name[name]
        next unless field&.[](:DA)

        field[:DA] = field[:DA].sub(/[\d.]+(?=\s+Tf)/, '0')
        changed = true
      end

      doc.write(template_path) if changed
    end
  end
end
