# frozen_string_literal: true

class Form21p530aCemeterySerializer
  include JSONAPI::Serializer

  set_type :form21p530a_cemetery
  set_id :id

  attribute :name
  attribute :street
  attribute :street2
  attribute :city
  attribute :state
  attribute :zip_code
  attribute :phone

  CemeteryRecord = Struct.new(:id, :name, :street, :street2, :city, :state, :zip_code, :phone, keyword_init: true)

  def initialize(cemeteries, options = {})
    records = cemeteries.map.with_index do |c, idx|
      CemeteryRecord.new(
        id: idx,
        name: c[:org_nm],
        street: c[:addr_line_one],
        street2: c[:addr_line_two],
        city: c[:city_nm],
        state: c[:state],
        zip_code: c[:zip_code],
        phone: build_phone(c[:day_phone_area_nbr], c[:day_phone_phone_nbr])
      )
    end
    super(records, options)
  end

  private

  def build_phone(area_code, number)
    return nil if area_code.blank? || number.blank?

    digits = "#{area_code}#{number}".gsub(/\D/, '')
    return nil unless digits.length == 10

    "#{digits[0..2]}-#{digits[3..5]}-#{digits[6..9]}"
  end
end
