# frozen_string_literal: true

module Openapi
  module Requests
    class Form214192
      FORM_SCHEMA = {
        '$schema': 'json-schemer://openapi30/schema',
        type: :object,
        properties: {
          veteranInformation: {
            type: :object,
            required: %i[fullName dateOfBirth],
            # FE requires either ssn or vaFileNumber to be present
            anyOf: [
              { required: [:ssn] },
              { required: [:vaFileNumber] }
            ],
            properties: {
              fullName: { '$ref' => '#/components/schemas/FirstMiddleLastName' },
              ssn: {
                type: :string,
                pattern: '^\\d{9}$',
                description: 'Social Security Number (9 digits)',
                example: '123456789'
              },
              vaFileNumber: { type: :string, pattern: '^\\d{8,9}$', example: '987654321' },
              dateOfBirth: { type: :string, format: :date, example: '1980-01-01' },
              address: { '$ref' => '#/components/schemas/SimpleAddress' }
            }
          },
          employmentInformation: {
            type: :object,
            required: %i[employerName employerAddress typeOfWorkPerformed amountEarnedLast12MonthsOfEmployment
                         timeLostLast12MonthsOfEmployment hoursWorkedDaily hoursWorkedWeekly
                         beginningDateOfEmployment concessions],
            properties: {
              employerName: { type: :string, maxLength: 100 },
              employerAddress: { '$ref' => '#/components/schemas/SimpleAddress' },
              typeOfWorkPerformed: { type: :string, maxLength: 1000 },
              beginningDateOfEmployment: { type: :string, format: :date },
              endingDateOfEmployment: { type: :string, format: :date },
              amountEarnedLast12MonthsOfEmployment: { type: :number, minimum: 0,
                                                      maximum: 999_999_999 },
              timeLostLast12MonthsOfEmployment: { type: :string, maxLength: 100 },
              hoursWorkedDaily: { type: :number, minimum: 0 },
              hoursWorkedWeekly: { type: :number, minimum: 0 },
              concessions: { type: :string, maxLength: 1000 },
              terminationReason: { type: :string, maxLength: 1000 },
              dateLastWorked: { type: :string, format: :date },
              lastPaymentDate: { type: :string, format: :date },
              lastPaymentGrossAmount: { type: :number, minimum: 0, maximum: 999_999_999 },
              lumpSumPaymentMade: { type: :boolean },
              grossAmountPaid: { type: :number, minimum: 0, maximum: 999_999_999 },
              datePaid: { type: :string, format: :date }
            }
          },
          militaryDutyStatus: {
            type: :object,
            required: %i[currentDutyStatus veteranDisabilitiesPreventMilitaryDuties],
            properties: {
              currentDutyStatus: { type: :string, maxLength: 500 },
              veteranDisabilitiesPreventMilitaryDuties: { type: :boolean }
            }
          },
          benefitEntitlementPayments: {
            type: :object,
            properties: {
              sickRetirementOtherBenefits: { type: :boolean },
              typeOfBenefit: { type: :string, maxLength: 500 },
              grossMonthlyAmountOfBenefit: { type: :number, minimum: 0, maximum: 999_999_999 },
              dateBenefitBegan: { type: :string, format: :date },
              dateFirstPaymentIssued: { type: :string, format: :date },
              dateBenefitWillStop: { type: :string, format: :date },
              remarks: { type: :string, maxLength: 2000 }
            }
          },
          certification: {
            type: :object,
            required: %i[signature certified],
            properties: {
              signature: {
                type: :string,
                description: 'Signature of employer or supervisor',
                example: 'John Doe'
              },
              certified: {
                type: :boolean,
                enum: [true],
                description: 'Certified by the employer or supervisor (must be true)',
                example: true
              }
            }
          }
        },
        required: %i[veteranInformation employmentInformation certification]
      }.freeze
    end
  end
end
