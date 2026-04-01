# frozen_string_literal: true

module DependentsBenefits::Helper
  # Helper methods to interact with models
  module Models
    private

    # Returns the parent claim group
    #
    # @return [SavedClaimGroup] The parent claim group record
    # @raise [ActiveRecord::RecordNotFound] if parent claim group not found
    def parent_group
      @parent_group ||= SavedClaimGroup.by_parent_id(parent_claim_id).last!&.parent_claim_group_for_child
    end

    # Returns the parent claim
    #
    # @return [SavedClaim, nil] The parent SavedClaim record
    def parent_claim
      @parent_claim ||= ::SavedClaim.find(parent_claim_id)
    end

    # Collects a memoized list of child claims
    # @return [Array<DependentClaim>]
    def child_claims
      @child_claims ||= collect_child_claims
    end

    # Collects all child claims associated with the parent claim
    #
    # Retrieves child claim IDs from SavedClaimGroup and loads the corresponding
    # SavedClaim records. Raises error if no child claims are found.
    #
    # @return [ActiveRecord::Relation<SavedClaim>] Collection of child claims
    # @raise [StandardError] if no child claims found for parent claim
    def collect_child_claims
      claim_ids = SavedClaimGroup.child_claims_for(parent_claim_id).pluck(:saved_claim_id)
      children = ::SavedClaim.where(id: claim_ids)
      raise StandardError, "No child claims found for parent claim #{parent_claim_id}" if children.empty?

      monitor.track_info_event('Collected child claims for processing',
                               action: 'collect_children', component:,
                               parent_claim_id:, child_claims_count: children.count)

      children
    end

    # Checks if all child claims have succeeded and parent group is not yet completed
    # @return [Boolean]
    def all_claims_succeeded?
      child_claims.all?(&:submissions_succeeded?) && !parent_group.completed?
    end

    # Checks if the parent claim group has already failed
    #
    # Prevents wasted work when sibling jobs have determined failure.
    # If the parent claim group is already failed, all jobs are considered failed.
    #
    # @return [Boolean] true if parent group has failed status
    def parent_group_failed?
      parent_group&.failed?
    end

    # Records successful enqueueing by updating claim group status
    #
    # Marks the claim group as ACCEPTED after jobs are successfully enqueued.
    # Currently unused but available for future implementation.
    #
    # @return [Boolean, nil] Result of the update, or nil if claim group not found
    def mark_parent_group_enqueued
      parent_group&.update!(status: SavedClaimGroup::STATUSES[:ACCEPTED])
    end

    # Marks the parent claim group as succeeded
    #
    # @return [Boolean] result of the update operation
    def mark_parent_group_succeeded
      parent_group&.update!(status: SavedClaimGroup::STATUSES[:SUCCESS])
    end

    # Marks the parent claim group as failed
    #
    # @return [Boolean] result of the update operation
    def mark_parent_group_failed
      parent_group&.update!(status: SavedClaimGroup::STATUSES[:FAILURE])
    end

    # Marks the parent claim group as processing
    #
    # @return [Boolean] result of the update operation
    def mark_parent_group_processing
      parent_group&.update!(status: SavedClaimGroup::STATUSES[:PROCESSING])
    end

    # Resolves InProgressForm lookup attributes for the parent claim
    # @return [Hash, nil] Attributes with :form_id and :user_uuid, or nil when unavailable
    def in_progress_form_lookup_attributes
      user_uuid = parent_claim&.user_data&.dig('veteran_information', 'uuid')
      form_id = parent_claim&.form_id
      return if user_uuid.blank? || form_id.blank?

      { form_id:, user_uuid: }
    end

    # Marks in-progress form as pending after an error
    # @return [void]
    def mark_in_progress_form_pending
      attributes = in_progress_form_lookup_attributes
      return unless attributes

      InProgressForm.find_by(**attributes)&.submission_pending!
    end

    # Removes in-progress form after completion/failure handling
    # @return [void]
    def destroy_in_progress_form
      attributes = in_progress_form_lookup_attributes
      return unless attributes

      InProgressForm.destroy_by(**attributes)
    end
  end
end
