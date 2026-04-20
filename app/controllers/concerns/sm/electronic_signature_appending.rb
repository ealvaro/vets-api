# frozen_string_literal: true

module SM
  module ElectronicSignatureAppending
    extend ActiveSupport::Concern

    private

    def append_electronic_signature!(params_h)
      name = params_h.delete(:signature_name)
      date_string = params_h.delete(:signature_date_user_local)

      return unless name.present? && date_string.present?
      return unless date_string.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      signed_date = Date.iso8601(date_string).strftime('%Y-%m-%d')
      params_h[:body] = "#{params_h[:body]}\n\n" \
                        "--------------------------------------------------\n\n" \
                        "#{name}\n" \
                        "Signed electronically on #{signed_date}."
    rescue ArgumentError
      nil
    end
  end
end
