# frozen_string_literal: true

module IvcChampva
  # Reformats multi-line address strings so a full three-street-line address still fits
  # within the fixed number of visible lines the PDF text fields were designed for
  # (e.g. street/street2/street3/city, state/zip), preventing the zip code from being
  # pushed out of the field. See #152932.
  #
  # NOTE: lines are rejoined with the literal two-character sequence '\n' (not a real
  # newline) because this output is interpolated directly into a JSON.erb template and
  # later parsed with JSON.parse - '\n' is the JSON escape sequence for a newline, while
  # an actual newline character would be stripped to a space by PdfFiller#escape_json_string.
  module PdfAddressFormatter
    def self.format(str)
      return str if str.nil?

      lines = str.split("\n")

      return lines.join('\n') unless Flipper.enabled?(:champva_pdf_address_overflow_fix)

      if lines.length > 3
        street_lines = lines[0...-2]
        city_state_and_zip = lines.last(2)
        lines = [street_lines.join(', ')] + city_state_and_zip
      end

      lines.join('\n')
    end
  end
end
