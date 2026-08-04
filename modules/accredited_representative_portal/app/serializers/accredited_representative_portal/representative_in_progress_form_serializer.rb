# frozen_string_literal: true

module AccreditedRepresentativePortal
  class RepresentativeInProgressFormSerializer
    include JSONAPI::Serializer

    set_id { '' }
    set_type :representative_in_progress_forms

    attribute :formId, &:form_id
    attribute :claimantId do |form|
      IcnTemporaryIdentifier.save_icn(form.veteran_icn).id
    end
    attribute :createdAt, &:created_at
    attribute :updatedAt, &:updated_at

    # The platform SIP save action reads `json.data.attributes.metadata.expiresAt`
    # and `json.data.attributes.metadata.inProgressFormId` to update its store.
    attribute :metadata do |form|
      (form.metadata || {}).merge(
        'expiresAt' => form.expires_at&.to_i,
        'inProgressFormId' => form.id
      )
    end
  end
end
