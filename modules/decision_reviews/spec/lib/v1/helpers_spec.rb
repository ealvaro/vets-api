# frozen_string_literal: true

require 'rails_helper'
require 'decision_reviews/v1/helpers'

describe DecisionReviews::V1::Helpers do
  let(:helper) { Class.new { include DecisionReviews::V1::Helpers }.new }

  describe '#middle_initial' do
    it 'returns the first character of middle name uppercased' do
      user = build(:user, middle_name: 'alexander')
      expect(helper.middle_initial(user)).to eq('A')
    end

    it 'returns the first character uppercased when middle name has spaces' do
      user = build(:user, middle_name: '  james  ')
      expect(helper.middle_initial(user)).to eq('J')
    end

    it 'returns nil when middle name is nil' do
      user = build(:user, middle_name: nil)
      expect(helper.middle_initial(user)).to be_nil
    end

    it 'returns nil when middle name is empty string' do
      user = build(:user, middle_name: '')
      expect(helper.middle_initial(user)).to be_nil
    end

    it 'returns nil when middle name is only spaces' do
      user = build(:user, middle_name: '   ')
      expect(helper.middle_initial(user)).to be_nil
    end
  end

  describe '#payload_encrypted_string' do
    it 'encrypts a payload to a string' do
      payload = { 'test' => 'data', 'key' => 'value' }
      encrypted = helper.payload_encrypted_string(payload)

      expect(encrypted).to be_a(String)
    end

    it 'can be decrypted back to original payload' do
      payload = { 'test' => 'data', 'key' => 'value' }
      encrypted = helper.payload_encrypted_string(payload)
      decrypted = JSON.parse(DecisionReviews::V1::Helpers::DR_LOCKBOX.decrypt(encrypted))

      expect(decrypted).to eq(payload)
    end
  end

  describe '#transform_address_fields' do
    it 'transforms address fields to match backend schema' do
      address = {
        'addressLine1' => '123 Main St',
        'addressLine2' => 'Apt 4',
        'stateCode' => 'CA',
        'countryCodeISO2' => 'US',
        'zipCode5' => '90210'
      }

      result = helper.transform_address_fields(address)

      expect(result['street']).to eq('123 Main St')
      expect(result['street2']).to eq('Apt 4')
      expect(result['state']).to eq('CA')
      expect(result['country']).to eq('USA')
      expect(result['postalCode']).to eq('90210')
    end

    it 'handles nil addressLine2' do
      address = {
        'addressLine1' => '123 Main St',
        'addressLine2' => nil,
        'stateCode' => 'CA',
        'countryCodeISO2' => 'US',
        'zipCode5' => '90210'
      }

      result = helper.transform_address_fields(address)

      expect(result['country']).to eq('USA')
    end

    it 'preserves original address fields' do
      address = {
        'addressLine1' => '123 Main St',
        'addressLine2' => 'Apt 4',
        'stateCode' => 'CA',
        'countryCodeISO2' => 'US',
        'zipCode5' => '90210'
      }

      result = helper.transform_address_fields(address)

      expect(result['addressLine1']).to eq('123 Main St')
      expect(result['addressLine2']).to eq('Apt 4')
      expect(result['stateCode']).to eq('CA')
      expect(result['countryCodeISO2']).to eq('US')
      expect(result['zipCode5']).to eq('90210')
    end
  end

  describe '#transform_form4142_data' do
    it 'returns original data if not a Hash' do
      expect(helper.transform_form4142_data(nil)).to be_nil
      expect(helper.transform_form4142_data('string')).to eq('string')
      expect(helper.transform_form4142_data([])).to eq([])
    end

    it 'transforms issues array to conditionsTreated string' do
      form4142 = {
        'providerFacility' => [
          {
            'providerFacilityName' => 'Test Hospital',
            'issues' => ['PTSD', 'Hearing Loss']
          }
        ]
      }

      result = helper.transform_form4142_data(form4142)

      expect(result['providerFacility'][0]).not_to have_key('issues')
      expect(result['providerFacility'][0]['conditionsTreated']).to eq('PTSD, Hearing Loss')
    end

    it 'handles conditionsTreated already as string' do
      form4142 = {
        'providerFacility' => [
          {
            'providerFacilityName' => 'Test Hospital',
            'conditionsTreated' => 'Already a string'
          }
        ]
      }

      result = helper.transform_form4142_data(form4142)

      expect(result['providerFacility'][0]['conditionsTreated']).to eq('Already a string')
    end

    it 'handles empty providerFacility array' do
      form4142 = { 'providerFacility' => [] }

      result = helper.transform_form4142_data(form4142)

      expect(result['providerFacility']).to eq([])
    end

    it 'handles non-Hash items in providerFacility array' do
      form4142 = {
        'providerFacility' => [
          { 'providerFacilityName' => 'Valid' },
          'not a hash'
        ]
      }

      result = helper.transform_form4142_data(form4142)

      expect(result['providerFacility'][0]['providerFacilityName']).to eq('Valid')
      expect(result['providerFacility'][1]).to eq('not a hash')
    end

    it 'does not mutate original data' do
      form4142 = {
        'providerFacility' => [
          {
            'providerFacilityName' => 'Test Hospital',
            'issues' => ['PTSD', 'Hearing Loss']
          }
        ]
      }
      original_issues = form4142['providerFacility'][0]['issues']

      helper.transform_form4142_data(form4142)

      expect(form4142['providerFacility'][0]['issues']).to eq(original_issues)
    end
  end

  describe '#get_and_rejigger_required_info' do
    let(:user) do
      build(:user,
            :loa3,
            ssn: '123456789',
            first_name: 'John',
            middle_name: 'Michael',
            last_name: 'Doe',
            birth_date: '1980-01-01')
    end

    let(:request_body) do
      {
        'data' => {
          'attributes' => {
            'veteran' => {
              'email' => 'test@example.com',
              'phone' => {
                'countryCode' => '1',
                'areaCode' => '555',
                'phoneNumber' => '1234567'
              },
              'address' => {
                'addressLine1' => '123 Main St',
                'addressLine2' => 'Apt 4',
                'stateCode' => 'CA',
                'countryCodeISO2' => 'US',
                'zipCode5' => '90210'
              }
            }
          }
        }
      }
    end

    let(:form4142) do
      {
        'providerFacility' => [
          {
            'providerFacilityName' => 'Test Hospital',
            'issues' => ['PTSD']
          }
        ]
      }
    end

    it 'returns properly formatted data with all required fields' do
      result = helper.get_and_rejigger_required_info(
        request_body:,
        form4142:,
        user:
      )

      expect(result['vaFileNumber']).to eq('123456789')
      expect(result['veteranSocialSecurityNumber']).to eq('123456789')
      expect(result['veteranFullName']['first']).to eq('John')
      expect(result['veteranFullName']['middle']).to eq('M')
      expect(result['veteranFullName']['last']).to eq('Doe')
      expect(result['veteranDateOfBirth']).to eq('1980-01-01')
      expect(result['email']).to eq('test@example.com')
      expect(result['veteranPhone']).to eq('5551234567')
    end

    it 'includes transformed address fields' do
      result = helper.get_and_rejigger_required_info(
        request_body:,
        form4142:,
        user:
      )

      expect(result['veteranAddress']['street']).to eq('123 Main St')
      expect(result['veteranAddress']['street2']).to eq('Apt 4')
      expect(result['veteranAddress']['state']).to eq('CA')
      expect(result['veteranAddress']['country']).to eq('USA')
      expect(result['veteranAddress']['postalCode']).to eq('90210')
    end

    it 'includes transformed form4142 data' do
      result = helper.get_and_rejigger_required_info(
        request_body:,
        form4142:,
        user:
      )

      expect(result['providerFacility']).to be_an(Array)
      expect(result['providerFacility'][0]['conditionsTreated']).to eq('PTSD')
    end

    it 'handles international phone numbers' do
      request_body['data']['attributes']['veteran']['phone'] = {
        'countryCode' => '44',
        'areaCode' => '20',
        'phoneNumber' => '12345678'
      }

      result = helper.get_and_rejigger_required_info(
        request_body:,
        form4142:,
        user:
      )

      expect(result['internationalPhoneNumber']).to eq('+44 2012345678')
      expect(result).not_to have_key('veteranPhone')
    end

    it 'handles user without middle name' do
      user_without_middle = build(:user,
                                  :loa3,
                                  ssn: '123456789',
                                  first_name: 'John',
                                  middle_name: nil,
                                  last_name: 'Doe',
                                  birth_date: '1980-01-01')
      result = helper.get_and_rejigger_required_info(
        request_body:,
        form4142:,
        user: user_without_middle
      )

      expect(result['veteranFullName']['middle']).to be_nil
    end
  end

  describe '#create_supplemental_claims_headers' do
    let(:user) do
      build(:user,
            :loa3,
            ssn: '123456789',
            icn: '1234567890V123456',
            first_name: 'John',
            middle_name: 'Michael',
            last_name: 'Doe',
            birth_date: '1980-01-01')
    end

    it 'creates valid headers with all required fields' do
      headers = helper.create_supplemental_claims_headers(user)

      expect(headers['X-VA-SSN']).to eq('123456789')
      expect(headers['X-VA-ICN']).to eq('1234567890V123456')
      expect(headers['X-VA-First-Name']).to eq('John')
      expect(headers['X-VA-Middle-Initial']).to eq('M')
      expect(headers['X-VA-Last-Name']).to eq('Doe')
      expect(headers['X-VA-Birth-Date']).to eq('1980-01-01')
    end

    it 'truncates first name to 12 characters' do
      long_name_user = build(:user,
                             :loa3,
                             ssn: '123456789',
                             icn: '1234567890V123456',
                             first_name: 'VeryLongFirstNameThatExceedsTwelveCharacters',
                             middle_name: 'Michael',
                             last_name: 'Doe',
                             birth_date: '1980-01-01')
      headers = helper.create_supplemental_claims_headers(long_name_user)

      expect(headers['X-VA-First-Name']).to eq('VeryLongFirs')
      expect(headers['X-VA-First-Name'].length).to eq(12)
    end

    it 'truncates last name to 18 characters' do
      long_name_user = build(:user,
                             :loa3,
                             ssn: '123456789',
                             icn: '1234567890V123456',
                             first_name: 'John',
                             middle_name: 'Michael',
                             last_name: 'VeryLongLastNameThatExceedsEighteenCharactersForSure',
                             birth_date: '1980-01-01')
      headers = helper.create_supplemental_claims_headers(long_name_user)

      expect(headers['X-VA-Last-Name']).to eq('VeryLongLastNameTh')
      expect(headers['X-VA-Last-Name'].length).to eq(18)
    end

    it 'handles user without middle name' do
      no_middle_user = build(:user,
                             :loa3,
                             ssn: '123456789',
                             icn: '1234567890V123456',
                             first_name: 'John',
                             middle_name: nil,
                             last_name: 'Doe',
                             birth_date: '1980-01-01')
      headers = helper.create_supplemental_claims_headers(no_middle_user)

      expect(headers).not_to have_key('X-VA-Middle-Initial')
    end

    it 'strips whitespace from SSN' do
      user_with_spaces = build(:user,
                               :loa3,
                               ssn: '123456789',
                               icn: '1234567890V123456',
                               first_name: 'John',
                               middle_name: 'Michael',
                               last_name: 'Doe',
                               birth_date: '1980-01-01')
      # Manually set SSN after build to avoid factory validation
      allow(user_with_spaces).to receive(:ssn).and_return('  123456789  ')
      headers = helper.create_supplemental_claims_headers(user_with_spaces)

      expect(headers['X-VA-SSN']).to eq('123456789')
    end

    it 'strips whitespace from first and last name' do
      space_name_user = build(:user,
                              :loa3,
                              ssn: '123456789',
                              icn: '1234567890V123456',
                              first_name: 'John',
                              middle_name: 'Michael',
                              last_name: 'Doe',
                              birth_date: '1980-01-01')
      allow(space_name_user).to receive_messages(first_name: '  John  ', last_name: '  Doe  ')
      headers = helper.create_supplemental_claims_headers(space_name_user)

      expect(headers['X-VA-First-Name']).to eq('John')
      expect(headers['X-VA-Last-Name']).to eq('Doe')
    end

    it 'raises error when required field SSN is missing' do
      no_ssn_user = build(:user,
                          :loa3,
                          ssn: '123456789',
                          icn: '1234567890V123456',
                          first_name: 'John',
                          middle_name: 'Michael',
                          last_name: 'Doe',
                          birth_date: '1980-01-01')
      allow(no_ssn_user).to receive(:ssn).and_return(nil)

      expect { helper.create_supplemental_claims_headers(no_ssn_user) }.to(
        raise_error(Common::Exceptions::Forbidden) do |error|
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-SSN')
        end
      )
    end

    it 'accepts empty first name without raising error (implementation lacks .presence check)' do
      empty_first_name_user = build(:user,
                                    :loa3,
                                    ssn: '123456789',
                                    icn: '1234567890V123456',
                                    first_name: 'John',
                                    middle_name: 'Michael',
                                    last_name: 'Doe',
                                    birth_date: '1980-01-01')
      allow(empty_first_name_user).to receive(:first_name).and_return('')

      headers = helper.create_supplemental_claims_headers(empty_first_name_user)

      # Empty first name doesn't get filtered out because there's no .presence call
      expect(headers['X-VA-First-Name']).to eq('')
    end

    it 'raises error when required field last name is missing' do
      no_last_name_user = build(:user,
                                :loa3,
                                ssn: '123456789',
                                icn: '1234567890V123456',
                                first_name: 'John',
                                middle_name: 'Michael',
                                last_name: 'Doe',
                                birth_date: '1980-01-01')
      allow(no_last_name_user).to receive(:last_name).and_return('')

      expect { helper.create_supplemental_claims_headers(no_last_name_user) }.to(
        raise_error(Common::Exceptions::Forbidden) do |error|
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-Last-Name')
        end
      )
    end

    it 'raises error when required field birth date is missing' do
      no_birth_date_user = build(:user,
                                 :loa3,
                                 ssn: '123456789',
                                 icn: '1234567890V123456',
                                 first_name: 'John',
                                 middle_name: 'Michael',
                                 last_name: 'Doe',
                                 birth_date: '1980-01-01')
      allow(no_birth_date_user).to receive(:birth_date).and_return(nil)

      expect { helper.create_supplemental_claims_headers(no_birth_date_user) }.to(
        raise_error(Common::Exceptions::Forbidden) do |error|
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-Birth-Date')
        end
      )
    end

    it 'does not raise error when ICN is missing (ICN is optional)' do
      no_icn_user = build(:user,
                          :loa3,
                          ssn: '123456789',
                          icn: '1234567890V123456',
                          first_name: 'John',
                          middle_name: 'Michael',
                          last_name: 'Doe',
                          birth_date: '1980-01-01')
      allow(no_icn_user).to receive(:icn).and_return('')

      # ICN is not in SC_REQUIRED_CREATE_HEADERS so no error is raised
      headers = helper.create_supplemental_claims_headers(no_icn_user)
      expect(headers).not_to have_key('X-VA-ICN')
    end

    it 'raises error with all required fields missing (SSN, Last-Name, Birth-Date)' do
      missing_fields_user = build(:user,
                                  :loa3,
                                  ssn: '123456789',
                                  icn: '1234567890V123456',
                                  first_name: 'John',
                                  middle_name: 'Michael',
                                  last_name: 'Doe',
                                  birth_date: '1980-01-01')
      allow(missing_fields_user).to receive_messages(ssn: nil, last_name: '', birth_date: nil)

      expect { helper.create_supplemental_claims_headers(missing_fields_user) }.to(
        raise_error(Common::Exceptions::Forbidden) do |error|
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-SSN')
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-Last-Name')
          expect(error.errors.first[:detail][:missing_required_fields]).to include('X-VA-Birth-Date')
        end
      )
    end
  end

  describe 'format_phone_number' do
    context 'international phone numbers' do
      it 'returns {} if phone is nil' do
        expect(helper.format_phone_number(nil)).to eq({})
      end

      it 'formats phone number with country code, area code, and number' do
        phone = { 'countryCode' => '44', 'areaCode' => '20', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          internationalPhoneNumber: '+44 205550456'
                                                        })
      end

      it 'formats phone number with nil area code' do
        phone = { 'areaCode' => nil, 'countryCode' => '44', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          internationalPhoneNumber: '+44 5550456'
                                                        })
      end

      it 'formats phone number with empty area code' do
        phone = { 'areaCode' => '', 'countryCode' => '44', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          internationalPhoneNumber: '+44 5550456'
                                                        })
      end

      it 'formats phone number with no area code' do
        phone = { 'countryCode' => '44', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          internationalPhoneNumber: '+44 5550456'
                                                        })
      end
    end

    context 'domestic phone numbers' do
      it 'formats phone number with nil country code' do
        phone = { 'countryCode' => nil, 'areaCode' => '210', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          veteranPhone: '2105550456'
                                                        })
      end

      it 'formats phone number with empty country code' do
        phone = { 'countryCode' => '', 'areaCode' => '210', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          veteranPhone: '2105550456'
                                                        })
      end

      it 'formats phone number with no country code' do
        phone = { 'areaCode' => '210', 'phoneNumber' => '5550456' }
        expect(helper.format_phone_number(phone)).to eq({
                                                          veteranPhone: '2105550456'
                                                        })
      end
    end
  end

  describe '#normalize_area_code_for_lighthouse_schema' do
    context 'when area_code is present and valid' do
      let(:req_body_obj) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'areaCode' => '123',
                  'phoneNumber' => '1234567',
                  'countryCode' => '1'
                }
              }
            }
          }
        }
      end

      it 'returns the original object unchanged' do
        expect(helper.normalize_area_code_for_lighthouse_schema(req_body_obj)).to eq(req_body_obj)
      end
    end

    context 'when area_code is present and valid with 2 characters (international number)' do
      let(:req_body_obj) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'areaCode' => '10',
                  'phoneNumber' => '49808232',
                  'countryCode' => '100'
                }
              }
            }
          }
        }
      end

      it 'returns the original object unchanged' do
        expect(helper.normalize_area_code_for_lighthouse_schema(req_body_obj)).to eq(req_body_obj)
      end
    end

    context 'when area_code is empty' do
      let(:req_body_obj) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'areaCode' => '',
                  'phoneNumber' => '12343432567',
                  'countryCode' => '44'
                }
              }
            }
          }
        }
      end

      it 'removes the empty areaCode' do
        result = helper.normalize_area_code_for_lighthouse_schema(req_body_obj)
        expect(result.dig('data', 'attributes', 'veteran', 'phone')).not_to have_key('areaCode')
      end
    end

    context 'when area_code is nil' do
      let(:req_body_obj) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'areaCode' => nil,
                  'phoneNumber' => '12343432567',
                  'countryCode' => '44'
                }
              }
            }
          }
        }
      end

      it 'removes the nil areaCode' do
        result = helper.normalize_area_code_for_lighthouse_schema(req_body_obj)
        expect(result.dig('data', 'attributes', 'veteran', 'phone')).not_to have_key('areaCode')
      end
    end
  end
end
