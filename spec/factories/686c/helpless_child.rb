# frozen_string_literal: true

FactoryBot.define do
  factory :helpless_child, class: Hash do
    initialize_with do
      {
        'view:selectable686_options' => {
          'add_disabled_child' => true
        },
        'dependents_application' => {
          'household_income' => true,
          'veteran_contact_information' => {
            'phone_number' => '1112223333',
            'international_phone_number' => '1112223333',
            'email_address' => 'foo@foo.com',
            'electronic_correspondence' => true,
            'veteran_address' => {
              'country' => 'USA',
              'street' => '8200 Doby LN',
              'city' => 'Pasadena',
              'state' => 'CA',
              'postal_code' => '21122'
            }
          },
          'children_to_add' => [{
            'does_child_have_disability' => true,
            'does_child_have_permanent_disability' => true,
            'income_in_last_year' => false,
            'does_child_live_with_you' => true,
            'has_child_ever_been_married' => false,
            'relationship_to_child' => { 'biological' => true },
            'birth_location' => {
              'location' => {
                'state' => 'CA',
                'city' => 'Slawson',
                'postal_code' => '90043'
              }
            },
            'ssn' => '370947143',
            'full_name' => {
              'first' => 'helpless first name',
              'middle' => 'helpless middle name',
              'last' => 'helpless last name',
              'suffix' => 'Sr.'
            },
            'birth_date' => '2010-03-03'
          }],
          'veteran_information' => {
            'birth_date' => '1809-02-12',
            'full_name' => {
              'first' => 'Wesley',
              'last' => 'Ford',
              'middle' => nil
            },
            'ssn' => '987654321',
            'va_file_number' => '987654321'
          },
          'days_till_expires' => 365,
          'privacy_agreement_accepted' => true
        },
        'veteran_information' => {
          'birth_date' => '1809-02-12',
          'full_name' => {
            'first' => 'Wesley',
            'last' => 'Ford',
            'middle' => nil
          },
          'ssn' => '987654321',
          'va_file_number' => '987654321'
        }
      }
    end
  end
end
