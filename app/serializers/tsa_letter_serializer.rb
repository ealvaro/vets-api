# frozen_string_literal: true

class TsaLetterSerializer
  include JSONAPI::Serializer

  set_id { '' }
  attribute :document_id, :document_version, :modified_datetime

  attribute :name, if: proc { |record| record.name.present? }
  attribute :description, if: proc { |record| record.description.present? }
end
