# frozen_string_literal: true

FactoryBot.define do
  factory :pensions_saved_claim, class: 'Pensions::SavedClaim' do
    form_id { '21P-527EZ' }
    # TODO: add this back when the DB migration is done
    # user_account_id { '123567788' }
    form do
      {
        veteranFullName: {
          first: 'Test',
          last: 'User'
        },
        email: 'foo@foo.com',
        veteranDateOfBirth: '1989-12-13',
        veteranSocialSecurityNumber: '111223333',
        veteranAddress: {
          country: 'USA',
          state: 'CA',
          postalCode: '90210',
          street: '123 Main St',
          city: 'Anytown'
        },
        statementOfTruthCertified: true,
        statementOfTruthSignature: 'Test User'
      }.to_json
    end

    trait :v2 do
      form do
        {
          # Section I: Veteran's Identification Information
          veteranFullName: {
            first: 'Chicken',
            middle: 'X',
            last: 'DuBois'
          },
          veteranDateOfBirth: '1989-12-13',
          veteranSocialSecurityNumber: '111223333',
          vaFileNumber: '111223333',
          vaClaimsHistory: true,
          # Section II: Veteran's Contact Information
          email: 'randall@foo.com',
          mobilePhone: '5551234567',
          internationalPhone: '123x456',
          veteranAddress: {
            country: 'USA',
            state: 'CA',
            postalCode: '90210',
            street: '123 Main St',
            city: 'Anytown'
          },
          # Section III: Veteran's Service Information
          previousNames: [
            {
              previousFullName: {
                first: 'Joseph',
                last: 'Doe'
              }
            }
          ],
          activeServiceDateRange: {
            from: '2003-03-02',
            to: '2007-03-20'
          },
          serviceNumber: '123456',
          serviceBranch: {
            army: true,
            navy: true
          },
          placeOfSeparation: 'West Brookfield, MA',
          powDateRange: {
            from: '1971-02-26',
            to: '1973-03-02'
          },
          # Section IV: Pension Information
          socialSecurityDisability: false,
          medicalCondition: false,
          nursingHome: false,
          medicaidStatus: true,
          specialMonthlyPension: false,
          isOver65: true,
          vaTreatmentHistory: true,
          vaMedicalCenters: [
            {
              medicalCenter: 'Memphis Health Care'
            }
          ],
          federalTreatmentHistory: true,
          federalMedicalCenters: [
            {
              medicalCenter: 'Memphis Health Care'
            }
          ],
          # Section V: Employment History
          currentEmployment: true,
          currentEmployers: [
            {
              jobType: 'Customer service',
              jobHoursWeek: '20'
            }
          ],
          previousEmployers: [
            {
              jobType: 'BBQ Technician',
              jobHoursWeek: '20',
              jobTitle: 'Assistant',
              jobDate: '2026-01-31'
            }
          ],
          # Section VI: Marital Status
          maritalStatus: 'MARRIED',
          currentSpouse: {
            spouseFullName: {
              first: 'Jessica',
              middle: 'Middle',
              last: 'Doe'
            },
            locationOfMarriage: 'Austin, TX',
            dateOfMarriage: '2001-01-01',
            marriageType: 'OTHER',
            otherExplanation: 'Lizard Tribunal'
          },
          spouseDateOfBirth: '1989-12-13',
          spouseIsVeteran: true,
          spouseVaFileNumber: '23423444',
          spouseSocialSecurityNumber: '333224444',
          reasonForCurrentSeparation: 'OTHER',
          otherExplanation: 'Personal reason',
          spouseAddress: {
            street: '123 7th st',
            street2: 'Apt 3',
            city: 'Pittsfield',
            country: 'USA',
            state: 'MA',
            postalCode: '01050'
          },
          currentSpouseMonthlySupport: 100.75,
          # Section VII: Prior Marital History
          marriages: [
            {
              spouseFullName: {
                first: 'Spongebob',
                middle: 'Middle',
                last: 'Doe'
              },
              dateOfMarriage: '1989-03-02',
              locationOfMarriage: 'Dallas',
              reasonForSeparation: 'OTHER',
              otherExplanation: 'Had to return to home planet',
              dateOfSeparation: '2026-03-02',
              locationOfSeparation: 'San Antonio, TX'
            },
            {
              spouseFullName: {
                first: 'Jane',
                middle: 'Middle',
                last: 'Doe'
              },
              dateOfMarriage: '1989-03-02',
              locationOfMarriage: 'Dallas',
              reasonForSeparation: 'DIVORCE',
              dateOfSeparation: '1990-03-02',
              locationOfSeparation: 'San Antonio, TX'
            }
          ],
          spouseMarriages: [
            {
              spouseFullName: {
                first: 'Spongebob',
                middle: 'Middle',
                last: 'Doe'
              },
              dateOfMarriage: '1989-03-02',
              locationOfMarriage: 'Dallas',
              reasonForSeparation: 'OTHER',
              otherExplanation: 'Vanished into thin air',
              dateOfSeparation: '2026-03-02',
              locationOfSeparation: 'San Antonio, TX'
            },
            {
              spouseFullName: {
                first: 'Jane',
                middle: 'Middle',
                last: 'Doe'
              },
              dateOfMarriage: '1989-03-02',
              locationOfMarriage: 'Dallas',
              reasonForSeparation: 'DIVORCE',
              dateOfSeparation: '1990-03-02',
              locationOfSeparation: 'San Antonio, TX'
            }
          ],
          # Section 8: Depdendent Children
          dependents: [
            {
              childInHousehold: false,
              childAddress: {
                street: '123 8th st',
                city: 'Hadley',
                country: 'USA',
                state: 'ME',
                postalCode: '01050'
              },
              personWhoLivesWithChild: {
                first: 'Joe',
                middle: 'Middle',
                last: 'Smith'
              },
              monthlyPayment: 3444,
              childPlaceOfBirth: 'Tallahassee, FL',
              childSocialSecurityNumber: '333224444',
              childRelationship: 'BIOLOGICAL',
              previouslyMarried: true,
              disabled: false,
              married: true,
              fullName: {
                first: 'Emily',
                middle: 'Anne',
                last: 'Doe'
              },
              childDateOfBirth: '2000-03-03'
            },
            {
              childInHousehold: true,
              childPlaceOfBirth: 'Tallahassee, FL',
              childSocialSecurityNumber: '333224444',
              childRelationship: 'BIOLOGICAL',
              previouslyMarried: true,
              disabled: false,
              married: true,
              fullName: {
                first: 'Emily',
                middle: 'Anne',
                last: 'Doe'
              },
              childDateOfBirth: '2000-03-03'
            }
          ],
          # Section IX: Income and Assets
          totalNetWorth: false,
          netWorthEstimation: 10.99,
          transferredAssets: true,
          homeOwnership: true,
          homeAcreageMoreThanTwo: true,
          homeAcreageValue: 75_000,
          landMarketable: true,
          incomeSourceCount: 'ONE_TO_FOUR',
          incomeSources: [
            {
              typeOfIncome: 'SOCIAL_SECURITY',
              receiver: 'DEPENDENT',
              dependentName: 'Chuck E. Cheese',
              payer: 'John Doe',
              amount: 278.05
            },
            {
              typeOfIncome: 'INTEREST_DIVIDEND',
              receiver: 'VETERAN',
              payer: 'John Doe',
              amount: 78.5
            },
            {
              typeOfIncome: 'OTHER',
              otherTypeExplanation: 'part-time Uber',
              receiver: 'SPOUSE',
              payer: 'John Doe',
              amount: 278.99
            },
            {
              typeOfIncome: 'PENSION_RETIREMENT',
              receiver: 'VETERAN',
              payer: 'John Doe',
              amount: 55.27
            }
          ],
          # Section X: Unreimbursed Medical Expenses
          # A: Care Expenses
          hasCareExpenses: true,
          careExpenses: [
            {
              recipients: 'VETERAN',
              provider: 'NYC Care Provider Family Medical Facility',
              careType: 'CARE_FACILITY',
              ratePerHour: 100.75,
              hoursPerWeek: '20',
              careDateRange: {
                from: '2020-08-01',
                to: '2023-05-25'
              },
              paymentFrequency: 'ONCE_MONTH',
              paymentAmount: 2500
            },
            {
              recipients: 'SPOUSE',
              provider: 'MA Care Provider',
              careType: 'IN_HOME_CARE_PROVIDER',
              ratePerHour: 150,
              hoursPerWeek: '15',
              careDateRange: {
                from: '2021-08-01',
                to: '2022-05-25'
              },
              paymentFrequency: 'ONCE_MONTH',
              paymentAmount: 1500
            },
            {
              recipients: 'DEPENDENT',
              childName: 'Joe Doe',
              provider: 'LA Care Provider',
              careType: 'CARE_FACILITY',
              ratePerHour: 200,
              hoursPerWeek: '10',
              careDateRange: {
                from: '2020-08-01'
              },
              noCareEndDate: true,
              paymentFrequency: 'ONCE_YEAR',
              paymentAmount: 22_500
            }
          ],
          # B: Medical Expenses
          hasMedicalExpenses: true,
          medicalExpenses: [
            {
              recipients: 'VETERAN',
              provider: 'Funeral Home',
              purpose: 'Burial expenses',
              paymentDate: '2020-03-15',
              paymentFrequency: 'ONE_TIME',
              paymentAmount: 10_000
            },
            {
              recipients: 'DEPENDENT',
              childName: 'Joe Doe',
              provider: 'Health Provider',
              purpose: 'Medical expenses',
              paymentDate: '2023-07-01',
              paymentFrequency: 'ONE_TIME',
              paymentAmount: 10_000
            },
            {
              recipients: 'SPOUSE',
              provider: 'Health Provider',
              purpose: 'Medical expenses',
              paymentDate: '2023-07-01',
              paymentFrequency: 'ONCE_MONTH',
              paymentAmount: 500
            },
            {
              recipients: 'DEPENDENT',
              childName: 'Joe Doe',
              provider: 'Health Provider',
              purpose: 'Medical expenses',
              paymentDate: '2023-07-01',
              paymentFrequency: 'ONCE_YEAR',
              paymentAmount: 5000
            },
            {
              recipients: 'SPOUSE',
              provider: 'Health Provider',
              purpose: 'Medical expenses',
              paymentDate: '2023-07-01',
              paymentFrequency: 'ONCE_MONTH',
              paymentAmount: 200
            },
            {
              recipients: 'DEPENDENT',
              childName: 'Joe Doe',
              provider: 'Health Provider',
              purpose: 'Medical fee',
              paymentDate: '2023-07-01',
              paymentFrequency: 'ONE_TIME',
              paymentAmount: 100
            }
          ],
          # Section XI: Direct Deposit Information
          bankAccount: {
            accountType: 'checking',
            bankName: 'Best Bank',
            accountNumber: '001122334455',
            routingNumber: '123123123'
          },
          # Section XII: Claim Certification and Signature
          signatureDate: '2026-07-01',
          statementOfTruthCertified: true,
          statementOfTruthSignature: 'Test User'
        }.to_json
      end
    end

    trait :pending do
      after(:create) do |pension_claim|
        create(:lighthouse_submission, :pending, saved_claim_id: pension_claim.id)
      end
    end

    trait :submitted do
      after(:create) do |pension_claim|
        create(:lighthouse_submission, :submitted, saved_claim_id: pension_claim.id)
      end
    end

    trait :failure do
      after(:create) do |pension_claim|
        create(:lighthouse_submission, :failure, saved_claim_id: pension_claim.id)
      end
    end
  end
end
