# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Rules
        # Cross-section: veteranIdentification.dateOfBirth × serviceInformation.servicePeriods.entryDate
        module ServiceAfter13thBirthday
          module_function

          def call(entry_date, source:, veteran_birth_date:, errors:)
            return if veteran_birth_date.blank? || entry_date.blank?

            date = Fields::FullDate.new(entry_date, source: "#{source}/entryDate")
            return unless date.valid?

            thirteenth_birthday = veteran_birth_date.to_datetime.next_year(13).to_date

            if date.parse < thirteenth_birthday
              errors.add(
                source: "#{source}/entryDate",
                detail: "entryDate cannot be before Veteran's thirteenth birthday."
              )
            end
          end
        end
      end
    end
  end
end
