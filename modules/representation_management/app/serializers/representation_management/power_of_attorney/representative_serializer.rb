# frozen_string_literal: true

module RepresentationManagement
  module PowerOfAttorney
    class RepresentativeSerializer < BaseSerializer
      include JSONAPI::Serializer

      # TODO: Remove respond_to? check when :arc_representative_status_use_accredited_models flag is removed.
      # After removal, set_id should simply use object.registration_number.
      set_id do |object|
        object.respond_to?(:registration_number) ? object.registration_number : object.representative_id
      end

      attribute :type do
        'representative'
      end

      # TODO: Remove respond_to? checks when :arc_representative_status_use_accredited_models flag is removed.
      # After removal, use object.individual_type directly.
      attribute :individual_type do |object|
        object.respond_to?(:individual_type) ? object.individual_type : object.user_types.first
      end

      attribute :email
      attribute :name, &:full_name

      # TODO: Remove respond_to? check when :arc_representative_status_use_accredited_models flag is removed.
      # After removal, use object.phone directly.
      attribute :phone do |object|
        object.respond_to?(:phone_number) ? object.phone_number : object.phone
      end
    end
  end
end
