# frozen_string_literal: true

module AccreditedRepresentativePortal
  class VeteranIdentity
    # Builds the duck-typed identity object BGS::DependentService expects in place of a
    # signed-in veteran User (see BGS::DependentService#initialize for the required interface).
    # common_name is intentionally left nil - it isn't present on the raw MPI profile, and
    # BGS::DependentService already tolerates a nil common_name (falls back to email as the
    # external_key). Notification email is set to the rep's address rather than the veteran's,
    # since BGS::SubmitForm686cV2Job sends its confirmation email to user.va_profile_email and
    # the job itself isn't being modified.

    attr_reader :first_name, :middle_name, :last_name, :ssn, :birth_date,
                :common_name, :email, :va_profile_email, :icn, :participant_id, :uuid

    def initialize(mpi_profile, current_user, claimant_uuid)
      @first_name = mpi_profile.given_names&.first
      @middle_name = mpi_profile.given_names&.second
      @last_name = mpi_profile.family_name
      @ssn = mpi_profile.ssn
      @birth_date = mpi_profile.birth_date
      @common_name = nil
      @email = current_user.email
      @va_profile_email = current_user.email
      @icn = mpi_profile.icn
      @participant_id = mpi_profile.participant_id
      @uuid = claimant_uuid
    end
  end
end
