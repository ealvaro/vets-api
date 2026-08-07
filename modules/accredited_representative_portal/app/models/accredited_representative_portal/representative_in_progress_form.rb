# frozen_string_literal: true

module AccreditedRepresentativePortal
  class RepresentativeInProgressForm < ApplicationRecord
    belongs_to :rep_user_account,
               class_name: 'UserAccount',
               inverse_of: false

    has_kms_key
    has_encrypted :form_data, key: :kms_key, **lockbox_options

    validates :form_id, :veteran_icn, presence: true

    before_create :set_expires_at

    def self.for_rep_and_veteran(form_id, rep_user_account_id, veteran_icn)
      find_by(form_id:, rep_user_account_id:, veteran_icn:)
    end

    def self.build_for_rep_and_veteran(form_id, rep_user_account_id, veteran_icn)
      find_or_initialize_by(form_id:, rep_user_account_id:, veteran_icn:).tap do |form|
        form.form_data ||= form.build_form_data(veteran_icn)
      end
    end

    def self.for_rep(rep_user_account_id)
      where(rep_user_account_id:)
    end

    # Mirrors InProgressForm#expires_after's per-form_id branching. Every
    # rep-facing form defaults to 60 days today; add a `case form_id` here if
    # a future form needs a different duration.
    def expires_after
      60.days
    end

    def next_expires_at
      Time.current + expires_after
    end

    def build_form_data(veteran_icn)
      return form_data if form_data.present?

      claimant_profile ||= MPI::Service.new.find_profile_by_identifier(
        identifier: veteran_icn,
        identifier_type: MPI::Constants::ICN
      )&.profile

      serialize_profile(claimant_profile) if claimant_profile
    end

    def serialize_profile(claimant_profile)
      address = claimant_profile.address
      self.form_data = {
        veteranFullName: {
          first: claimant_profile.given_names&.first,
          last: claimant_profile.family_name
        },
        address: {
          'view:militaryBaseDescription': {},
          postalCode: address&.postal_code,
          country: address&.country,
          street: address&.street,
          city: address&.city,
          state: address&.state
        },
        veteranSsn: claimant_profile&.ssn,
        veteranDateOfBirth: claimant_profile&.birth_date
      }.to_json
    end

    def data_and_metadata
      return {} if form_data.blank?

      {
        formData: JSON.parse(form_data),
        metadata: (metadata || {}).merge(
          'expiresAt' => expires_at&.to_i,
          'lastUpdated' => updated_at.to_i,
          'inProgressFormId' => id
        )
      }
    end

    private

    def set_expires_at
      self.expires_at ||= next_expires_at
    end
  end
end
