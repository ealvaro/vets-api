# frozen_string_literal: true

module AccreditedRepresentativePortal
  # Records a single user's admission into the Form 21a limited-release pilot. One row per
  # user, ever (enforced by a unique index on user_account_id). `created_at` doubles as the
  # slot-granted time and the Eastern-month bucket used by the monthly cap count.
  #
  # See Form21aPilotGate for the rules that own reads/writes of these records.
  class Form21aPilotAdmission < ApplicationRecord
    belongs_to :user_account, class_name: '::UserAccount'

    enum :status, { started: 'started', submitted: 'submitted' }
  end
end
