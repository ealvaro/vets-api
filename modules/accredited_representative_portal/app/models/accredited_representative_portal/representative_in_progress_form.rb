# frozen_string_literal: true

require 'json_marshal/marshaller'

module AccreditedRepresentativePortal
  class RepresentativeInProgressForm < ApplicationRecord
    belongs_to :rep_user_account,
               class_name: 'UserAccount',
               inverse_of: false

    has_kms_key
    has_encrypted :form_data, key: :kms_key, **lockbox_options
    serialize :form_data, coder: JsonMarshal::Marshaller

    validates :form_id, :veteran_icn, presence: true

    before_save :serialize_form_data
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
      existing_form_data = safe_form_data
      return existing_form_data if existing_form_data.present?

      claimant_profile = fetch_claimant_profile(veteran_icn)
      serialize_profile(claimant_profile) if claimant_profile
    end

    # Shaped to match veteranSubPage in
    # containers/form686c/686cVeteranInformation.jsx exactly (including which
    # address fields exist) so this is indistinguishable from a real saved draft.
    def serialize_profile(claimant_profile)
      self.form_data = {
        veteranSubPage: {
          veteranFullName: {
            first: claimant_profile.given_names&.first,
            last: claimant_profile.family_name
          },
          address: {
            postalCode: claimant_profile.address&.postal_code
          },
          veteranSsn: claimant_profile.ssn,
          veteranDateOfBirth: formatted_birth_date(claimant_profile.birth_date)
        }
      }.to_json
    end

    def data_and_metadata
      data = safe_form_data
      return {} if data.blank?

      {
        formData: parsed_form_data(data),
        metadata: (metadata || {}).merge(
          'expiresAt' => expires_at&.to_i,
          'lastUpdated' => updated_at.to_i,
          'inProgressFormId' => id,
          # True when this data was just synthesized from MPI and nothing has
          # ever been saved for this rep/veteran pair (mirrors the vet-facing
          # InProgressForm SIP convention of an explicit `prefill` metadata
          # flag). formData is schema-shaped either way; the frontend only
          # uses this to decide whether to resume at metadata.returnUrl.
          'prefill' => !persisted?
        )
      }
    end

    private

    # find_profile_by_identifier already rescues connection/timeout errors
    # internally and returns a FindProfileResponse with #error set rather
    # than raising, but wrap it anyway since a form save is about to happen
    # with claimant_profile possibly nil either way -- better to degrade to
    # a blank form than to let a save-time exception bubble up as a 500.
    def fetch_claimant_profile(veteran_icn)
      response = MPI::Service.new.find_profile_by_identifier(
        identifier: veteran_icn,
        identifier_type: MPI::Constants::ICN
      )
      return log_mpi_error(response.error) if response.error

      warn_if_profile_missing_key_fields(response.profile, veteran_icn)
      response.profile
    rescue => e
      Rails.logger.error(
        'ARP: RepresentativeInProgressForm - unexpected error during MPI lookup for prefill',
        { error: e.class.name }
      )
      nil
    end

    def log_mpi_error(error)
      Rails.logger.warn(
        'ARP: RepresentativeInProgressForm - MPI lookup failed while building prefill',
        { error: error.class.name }
      )
      nil
    end

    # Better to know a prefill silently shipped with mostly-null fields than
    # to find out from a confused rep filling out a "blank" form.
    def warn_if_profile_missing_key_fields(profile, veteran_icn)
      return if profile.blank?
      return unless profile.given_names.blank? && profile.family_name.blank? && profile.ssn.blank?

      Rails.logger.warn(
        'ARP: RepresentativeInProgressForm - MPI profile missing key prefill fields', { icn: veteran_icn }
      )
    end

    def parsed_form_data(data)
      JSON.parse(data)
    rescue JSON::ParserError => e
      Rails.logger.error(
        "ARP: RepresentativeInProgressForm - failed to parse form_data for id=#{id}. Error: #{e.message}"
      )
      {}
    end

    # Lockbox raises DecryptionError if the ciphertext is corrupted or the
    # KMS data key can't be unwrapped. Treat that the same as "no draft data
    # exists yet" rather than letting it raise through show/build_form_data
    # mid-request.
    def safe_form_data
      form_data
    rescue Lockbox::DecryptionError => e
      Rails.logger.error(
        "ARP: RepresentativeInProgressForm - failed to decrypt form_data for id=#{id}. Error: #{e.class}"
      )
      nil
    end

    # The update endpoint hands us params[:formData] straight from the
    # request body, which is an ActionController::Parameters (or plain Hash)
    # rather than a String -- Lockbox can't encrypt that directly. Mirrors
    # InProgressForm#serialize_form_data.
    def serialize_form_data
      self.form_data = form_data.to_json unless form_data.is_a?(String)
    end

    # MPI's birth_date is validated (Time.parse-able) but not normalized, so
    # it can arrive as HL7's YYYYMMDD or already-dashed YYYY-MM-DD. The form
    # schema (dateOfBirthSchema) needs the latter.
    def formatted_birth_date(birth_date)
      return if birth_date.blank?

      Date.parse(birth_date).iso8601
    rescue ArgumentError
      nil
    end

    def set_expires_at
      self.expires_at ||= next_expires_at
    end
  end
end
