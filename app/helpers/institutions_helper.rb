# frozen_string_literal: false

module InstitutionsHelper
  def remove_sco_contact_details!(data)
    cert_officials = data[:data][:attributes][:versioned_school_certifying_officials]
    if cert_officials.present?
      cert_officials.map! do |official|
        official.except(:email, :phone_number, :phone_area_code, :phone_extension)
      end
    end
  end
end
