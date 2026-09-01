# frozen_string_literal: true

module Eps
  ##
  # Reads phone numbers out of a Wellhive +contactDetails+ array.
  #
  # Wellhive's ContactPoint schema carries the channel in +type+ ("phone", "fax",
  # "email", ...) and the intended audience in +use+ ("for-patient", "work", ...).
  # Earlier revisions of this code selected on a FHIR-style +system+ key and an
  # underscored +for_patient+ value, neither of which Wellhive has ever published,
  # so provider phone numbers always resolved to nil.
  #
  # +system+ is still accepted as a fallback channel key and +use+ is compared with
  # separators stripped, so a payload that diverges from the published spec still
  # yields a number instead of silently returning nil.
  #
  module ContactPoint
    PHONE_TYPE = 'phone'

    # +for-patient+ with separators stripped, so +for_patient+ matches too.
    PATIENT_USE = 'forpatient'

    class << self
      ##
      # The best phone number for a patient to call, preferring the entry marked
      # for patient use and falling back to the first phone entry.
      #
      # @param contact_details [Array<Hash>] Wellhive +contactDetails+ entries
      # @return [String, nil] the phone number, or nil when there is no phone entry
      #
      def phone_number(contact_details)
        phones = phone_contacts(contact_details)
        return nil if phones.blank?

        preferred = phones.find { |contact| patient_facing?(contact) } || phones.first
        preferred[:value].presence
      end

      private

      def phone_contacts(contact_details)
        return [] if contact_details.blank?

        Array(contact_details).select do |contact|
          contact.is_a?(Hash) && channel(contact) == PHONE_TYPE
        end
      end

      ##
      # Wellhive documents the channel as +type+; a FHIR-style +system+ key is also
      # accepted, and wins when an entry somehow carries both.
      #
      def channel(contact)
        (contact[:system].presence || contact[:type].presence).to_s.downcase
      end

      def patient_facing?(contact)
        contact[:use].to_s.downcase.gsub(/[^a-z]/, '') == PATIENT_USE
      end
    end
  end
end
