# frozen_string_literal: true

module RepresentationManagement
  module PowerOfAttorney
    class OrganizationSerializer < BaseSerializer
      include JSONAPI::Serializer

      # TODO: Remove respond_to? check when :arc_representative_status_use_accredited_models flag is removed.
      # After removal, set_id should simply use object.poa_code.
      set_id do |object|
        object.respond_to?(:poa_code) ? object.poa_code : object.poa
      end

      attribute :type do
        'organization'
      end

      attribute :name
    end
  end
end
