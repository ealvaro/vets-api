# frozen_string_literal: true

require 'va_profile/models/validation_address'

FactoryBot.define do
  factory :va_profile_validation_address, class: 'VAProfile::Models::ValidationAddress' do
    address_pou { VAProfile::Models::Address::RESIDENCE }
    address_type { VAProfile::Models::Address::DOMESTIC }
    country_name { 'USA' }
    country_code_iso3 { 'USA' }

    trait :multiple_matches do
      address_line1 { '37 1st st' }
      city { 'Brooklyn' }
      state_code { 'NY' }
      country_name {}
      zip_code { '11249' }
    end

    trait :override do
      address_pou { VAProfile::Models::Address::CORRESPONDENCE }
      address_line1 { '1494 Martin Luther King Rd' }
      address_line2 { 'c/o foo' }
      city { 'Fulton' }
      state_code { 'MS' }
      zip_code { '38843' }
    end
  end

  factory :va_profile_validation_address_international, class: 'VAProfile::Models::ValidationAddress' do
    address_pou { VAProfile::Models::Address::RESIDENCE }
    address_type { VAProfile::Models::Address::INTERNATIONAL }
    address_line1 { '10 Downing St' }
    country_name { 'United Kingdom' }
    country_code_iso3 { 'GBR' }
    province { 'England' }
    international_postal_code { 'SW1A 1AA' }
    city { 'London' }
  end
end
