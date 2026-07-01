# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/v1/poa_pdf_constructor/individual'
require_relative '../../../../support/pdf_matcher'

describe ClaimsApi::V1::PoaPdfConstructor::Individual do
  let(:temp) { create(:power_of_attorney, :with_full_headers) }
  let(:phone_country_codes_temp) { create(:power_of_attorney, :with_full_headers) }
  let(:rep) { create(:veteran_representative, :with_address, representative_id: '12345') }

  before do
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v1_2122a_pdf_form_update).and_return(false)
    Timecop.freeze(Time.zone.parse('2020-01-01T08:00:00Z'))
    b64_image = File.read('modules/claims_api/spec/fixtures/signature_b64.txt')
    temp.form_data = {
      signatures: {
        veteran: b64_image,
        representative: b64_image
      },
      veteran: {
        address: {
          numberAndStreet: '2719 Hyperion Ave',
          city: 'Los Angeles',
          state: 'CA',
          country: 'US',
          zipFirstFive: '92264'
        },
        phone: {
          areaCode: '555',
          phoneNumber: '5551337'
        }
      },
      serviceOrganization: {
        firstName: 'Bob',
        lastName: 'Law',
        address: {
          numberAndStreet: '123 East Main St',
          city: 'My City',
          state: 'ZZ',
          country: 'US',
          zipFirstFive: '12345'
        }
      }
    }
    temp.save

    phone_country_codes_temp.form_data = {
      signatures: {
        veteran: b64_image,
        representative: b64_image
      },
      veteran: {
        address: {
          numberAndStreet: '2719 Hyperion Ave',
          city: 'Los Angeles',
          state: 'CA',
          country: 'US',
          zipFirstFive: '92264'
        },
        phone: {
          countryCode: '1',
          areaCode: '555',
          phoneNumber: '5551337'
        }
      },
      serviceOrganization: {
        firstName: 'Bob',
        lastName: 'Law',
        address: {
          numberAndStreet: '123 East Main St',
          city: 'My City',
          state: 'ZZ',
          country: 'US',
          zipFirstFive: '12345'
        }
      }
    }
    phone_country_codes_temp.save
  end

  after do
    Timecop.return
  end

  it 'construct pdf' do
    power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
    data = power_of_attorney.form_data.deep_merge(
      {
        'veteran' => {
          'firstName' => power_of_attorney.auth_headers['va_eauth_firstName'],
          'lastName' => power_of_attorney.auth_headers['va_eauth_lastName'],
          'ssn' => power_of_attorney.auth_headers['va_eauth_pnid'],
          'birthdate' => power_of_attorney.auth_headers['va_eauth_birthdate']
        },
        'representative' => {
          'type' => rep.user_types[0]
        }
      }
    )

    constructor = ClaimsApi::V1::PoaPdfConstructor::Individual.new
    expected_pdf = Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', '21-22A', 'signed_filled_final.pdf')
    generated_pdf = constructor.construct(data, id: power_of_attorney.id)
    expect(generated_pdf).to match_pdf_content_of(expected_pdf)
  end

  context 'flipper-gated template paths' do
    let(:constructor) { described_class.new }

    [true, false].each do |flipper_enabled|
      context "when flipper is #{flipper_enabled ? 'enabled' : 'disabled'}" do
        before do
          allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v1_2122a_pdf_form_update)
                                              .and_return(flipper_enabled)
        end

        it "#{flipper_enabled ? 'uses rev_07_2023' : 'uses legacy'} template paths" do
          %i[page1_template_path page2_template_path page3_template_path].each do |m|
            if flipper_enabled
              expect(constructor.send(m).to_s).to include('rev_07_2023')
            else
              expect(constructor.send(m).to_s).not_to include('rev_07_2023')
            end
          end
        end
      end
    end
  end

  it 'constructs the pdf when phone country codes are present on form' do
    power_of_attorney = ClaimsApi::PowerOfAttorney.find(phone_country_codes_temp.id)
    data = power_of_attorney.form_data.deep_merge(
      {
        'veteran' => {
          'firstName' => power_of_attorney.auth_headers['va_eauth_firstName'],
          'lastName' => power_of_attorney.auth_headers['va_eauth_lastName'],
          'ssn' => power_of_attorney.auth_headers['va_eauth_pnid'],
          'birthdate' => power_of_attorney.auth_headers['va_eauth_birthdate']
        },
        'representative' => {
          'type' => rep.user_types[0]
        }
      }
    )

    constructor = ClaimsApi::V1::PoaPdfConstructor::Individual.new
    expected_pdf = Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', '21-22A',
                                   'signed_filled_phone_country_codes.pdf')
    generated_pdf = constructor.construct(data, id: power_of_attorney.id)
    expect(generated_pdf).to match_pdf_content_of(expected_pdf)
  end

  context 'when lighthouse_claims_api_v1_2122a_pdf_form_update is enabled' do
    let(:constructor) { described_class.new }
    let(:b64_image) { File.read('modules/claims_api/spec/fixtures/signature_b64.txt') }
    let(:data) do
      {
        'signatures' => { 'veteran' => b64_image, 'representative' => b64_image },
        'veteran' => {
          'firstName' => 'John', 'lastName' => 'Veteran', 'ssn' => '123456789',
          'birthdate' => '1985-01-15', 'serviceBranch' => 'ARMY', 'serviceNumber' => 'SN123',
          'address' => {
            'numberAndStreet' => '123 Main St', 'aptUnitNumber' => 'Apt 4B',
            'city' => 'Washington', 'state' => 'DC', 'country' => 'US',
            'zipFirstFive' => '20001', 'zipLastFour' => '1234'
          },
          'phone' => { 'areaCode' => '202', 'phoneNumber' => '5551234' },
          'email' => 'john.veteran@example.com'
        },
        'claimant' => {
          'firstName' => 'Jane', 'middleInitial' => 'M', 'lastName' => 'Claimant',
          'relationship' => 'Spouse', 'dateOfBirth' => '1990-06-20',
          'address' => {
            'numberAndStreet' => '456 Oak Ave', 'aptUnitNumber' => 'Suite 2',
            'city' => 'Arlington', 'state' => 'VA', 'country' => 'US',
            'zipFirstFive' => '22201', 'zipLastFour' => '5678'
          },
          'phone' => { 'areaCode' => '703', 'phoneNumber' => '5555678' },
          'email' => 'jane.claimant@example.com'
        },
        'serviceOrganization' => {
          'poaCode' => 'A1Q', 'firstName' => 'Bob', 'lastName' => 'Attorney',
          'organizationName' => 'I help vets LLC.',
          'address' => {
            'numberAndStreet' => '789 Legal Blvd', 'aptUnitNumber' => 'Floor 3',
            'city' => 'Richmond', 'state' => 'VA', 'country' => 'US',
            'zipFirstFive' => '23220', 'zipLastFour' => '4321'
          },
          'email' => 'bob@lawfirm.com', 'jobTitle' => 'Veteran Service representative'
        },
        'representative' => { 'type' => 'attorney' },
        'recordConsent' => true, 'consentAddressChange' => true,
        'consentLimits' => ['DRUG ABUSE', 'ALCOHOLISM', 'HIV', 'SICKLE CELL'],
        'consentDisclosureAffiliated' => true, 'firmOrOrgName' => 'Law Firm LLC',
        'consentDisclosureIndividuals' => true, 'individualNames' => %w[Alice Charlie]
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v1_2122a_pdf_form_update).and_return(true)
    end

    describe '#updated_page1_options' do
      subject(:options) { constructor.send(:page1_options, data) }

      it 'maps veteran name fields' do
        expect(options[:'form1[0].#subform[0].Veterans_First_Name[0]']).to eq('John')
        expect(options[:'form1[0].#subform[0].Veterans_Last_Name[0]']).to eq('Veteran')
      end

      it 'maps veteran SSN fields' do
        expect(options[:'form1[0].#subform[0].SocialSecurityNumber_FirstThreeNumbers[0]']).to eq('123')
        expect(options[:'form1[0].#subform[0].SocialSecurityNumber_SecondTwoNumbers[0]']).to eq('45')
        expect(options[:'form1[0].#subform[0].SocialSecurityNumber_LastFourNumbers[0]']).to eq('6789')
      end

      it 'maps veteran DOB fields' do
        expect(options[:'form1[0].#subform[0].Date_Of_Birth_Month[0]']).to eq('01')
        expect(options[:'form1[0].#subform[0].Date_Of_Birth_Day[0]']).to eq('15')
        expect(options[:'form1[0].#subform[0].Date_Of_Birth_Year[0]']).to eq('1985')
      end

      it 'maps service number' do
        expect(options[:'form1[0].#subform[0].Veterans_Service_Number_If_Applicable[1]']).to eq('SN123')
      end

      it 'maps service branch as radio button value' do
        expect(options[:'form1[0].#subform[0].RadioButtonList[1]']).to eq(4)
      end

      it 'maps veteran address fields' do
        expect(options[:'form1[0].#subform[0].MailingAddress_NumberAndStreet[0]']).to eq('123 Main St')
        expect(options[:'form1[0].#subform[0].MailingAddress_ApartmentOrUnitNumber[0]']).to eq('Apt 4B')
        expect(options[:'form1[0].#subform[0].MailingAddress_City[0]']).to eq('Washington')
        expect(options[:'form1[0].#subform[0].MailingAddress_StateOrProvince[0]']).to eq('DC')
        expect(options[:'form1[0].#subform[0].MailingAddress_Country[0]']).to eq('US')
        expect(options[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]']).to eq('20001')
        expect(options[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]']).to eq('1234')
      end

      it 'maps veteran phone as split fields' do
        expect(options[:'form1[0].#subform[0].Telephone_Number_Area_Code[1]']).to eq('202')
        expect(options[:'form1[0].#subform[0].Telephone_Middle_Three_Numbers[0]']).to eq('555')
        expect(options[:'form1[0].#subform[0].Telephone_Last_Four_Numbers[1]']).to eq('1234')
        expect(options[:'form1[0].#subform[0].International_Telephone_Number_If_Applicable[0]']).to be_nil
      end

      it 'maps veteran email' do
        expect(options[:'form1[0].#subform[0].E_Mail_Address_Optional[1]']).to eq('john.veteran@example.com')
      end

      it 'maps claimant name and middle initial' do
        expect(options[:'form1[0].#subform[0].Claimants_First_Name[0]']).to eq('Jane')
        expect(options[:'form1[0].#subform[0].Claimants_Middle_Initial[0]']).to eq('M')
        expect(options[:'form1[0].#subform[0].Claimants_Last_Name[0]']).to eq('Claimant')
      end

      it 'maps claimant DOB fields' do
        expect(options[:'form1[0].#subform[0].Claimants_Date_Of_Birth_Month[0]']).to eq('06')
        expect(options[:'form1[0].#subform[0].Date_Of_Birth_Day[1]']).to eq('20')
        expect(options[:'form1[0].#subform[0].Date_Of_Birth_Year[1]']).to eq('1990')
      end

      it 'maps claimant relationship' do
        expect(options[:'form1[0].#subform[0].RelationshipToVeteran[0]']).to eq('Spouse')
      end

      it 'maps claimant address fields' do
        expect(options[:'form1[0].#subform[0].MailingAddress_NumberAndStreet[1]']).to eq('456 Oak Ave')
        expect(options[:'form1[0].#subform[0].MailingAddress_ApartmentOrUnitNumber[1]']).to eq('Suite 2')
        expect(options[:'form1[0].#subform[0].MailingAddress_City[1]']).to eq('Arlington')
        expect(options[:'form1[0].#subform[0].MailingAddress_StateOrProvince[1]']).to eq('VA')
        expect(options[:'form1[0].#subform[0].MailingAddress_Country[1]']).to eq('US')
        expect(options[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]']).to eq('22201')
        expect(options[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]']).to eq('5678')
      end

      it 'maps claimant phone as split fields' do
        expect(options[:'form1[0].#subform[0].Telephone_Number_Area_Code[0]']).to eq('703')
        expect(options[:'form1[0].#subform[0].Telphone_Middle_Three_Numbers[0]']).to eq('555')
        expect(options[:'form1[0].#subform[0].Telephone_Last_Four_Numbers[0]']).to eq('5678')
        expect(options[:'form1[0].#subform[0].International_Telephone_Number_If_Applicable[1]']).to be_nil
      end

      it 'maps claimant email' do
        expect(options[:'form1[0].#subform[0].E_Mail_Address_Optional[0]']).to eq('jane.claimant@example.com')
      end

      it 'maps representative name from serviceOrganization' do
        expect(options[:'form1[0].#subform[0].Name_Of_Individual_Appointed_As_Representative_First_Name[0]'])
          .to eq('Bob')
        expect(options[:'form1[0].#subform[0].Last_Name[0]']).to eq('Attorney')
      end

      it 'maps representative type as radio button value' do
        expect(options[:'form1[0].#subform[0].RadioButtonList[0]']).to eq(4)
      end
    end

    describe '#updated_page2_options' do
      subject(:options) { constructor.send(:page2_options, data) }

      it 'maps veteran SSN header' do
        expect(options[:'form1[0].#subform[1].SocialSecurityNumber_FirstThreeNumbers[1]']).to eq('123')
        expect(options[:'form1[0].#subform[1].SocialSecurityNumber_SecondTwoNumbers[1]']).to eq('45')
        expect(options[:'form1[0].#subform[1].SocialSecurityNumber_LastFourNumbers[1]']).to eq('6789')
      end

      it 'maps representative address from serviceOrganization' do
        expect(options[:'form1[0].#subform[1].MailingAddress_NumberAndStreet[2]']).to eq('789 Legal Blvd')
        expect(options[:'form1[0].#subform[1].MailingAddress_ApartmentOrUnitNumber[2]']).to eq('Floor 3')
        expect(options[:'form1[0].#subform[1].MailingAddress_City[2]']).to eq('Richmond')
        expect(options[:'form1[0].#subform[1].MailingAddress_StateOrProvince[2]']).to eq('VA')
        expect(options[:'form1[0].#subform[1].MailingAddress_Country[2]']).to eq('US')
        expect(options[:'form1[0].#subform[1].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[2]']).to eq('23220')
        expect(options[:'form1[0].#subform[1].MailingAddress_ZIPOrPostalCode_LastFourNumbers[2]']).to eq('4321')
      end

      it 'maps consent fields' do
        expect(options[:'form1[0].#subform[1].AuthorizationForRepAccessToRecords[0]']).to eq(1)
        expect(options[:'form1[0].#subform[1].AuthorizationForRepActClaimantsBehalf[0]']).to eq(1)
        expect(options[:'form1[0].#subform[1].RelationshipToVeteran[1]'])
          .to eq('DRUG ABUSE, ALCOHOLISM, HIV, SICKLE CELL')
      end

      it 'maps disclosure to affiliated personnel' do
        key = 'form1[0].#subform[1].Checkbox_I_Authorize_VA_To_Disclose_All_My_Records' \
              '_Other_Than_As_Provided_In_Items_20_And_21[0]'
        expect(options[key.to_sym]).to eq(1)
        expect(options[:'form1[0].#subform[1].Provide_The_Name_Of_The_Firm_Or_Organization_Here[0]'])
          .to eq('Law Firm LLC')
      end

      it 'maps disclosure to named individuals' do
        key = 'form1[0].#subform[1].Checkbox_I_Authorize_VA_To_Disclose_All_My_Records' \
              '_Other_Than_As_Provided_In_Items_20_And_21[1]'
        expect(options[key.to_sym]).to eq(1)
        expect(options[:'form1[0].#subform[1].Provide_The_Names_Of_The_Individuals_Here[0]'])
          .to eq('Alice, Charlie')
      end
    end

    describe '#updated_page3_options' do
      subject(:options) { constructor.send(:page3_options, data) }

      it 'maps veteran SSN header' do
        expect(options[:'form1[0].#subform[2].SocialSecurityNumber_FirstThreeNumbers[2]']).to eq('123')
        expect(options[:'form1[0].#subform[2].SocialSecurityNumber_SecondTwoNumbers[2]']).to eq('45')
        expect(options[:'form1[0].#subform[2].SocialSecurityNumber_LastFourNumbers[2]']).to eq('6789')
      end

      it 'maps veteran/claimant date signed fields using current date' do
        expect(options[:'form1[0].#subform[2].Date_Signed_Month[2]']).to eq('01')
        expect(options[:'form1[0].#subform[2].Date_Signed_Day[2]']).to eq('01')
        expect(options[:'form1[0].#subform[2].Date_Signed_Year[2]']).to eq('2020')
      end

      it 'maps representative date signed fields using current date' do
        expect(options[:'form1[0].#subform[2].Date_Signed_Month[3]']).to eq('01')
        expect(options[:'form1[0].#subform[2].Date_Signed_Day[3]']).to eq('01')
        expect(options[:'form1[0].#subform[2].Date_Signed_Year[3]']).to eq('2020')
      end
    end

    describe '#page3_signatures' do
      it 'returns signature objects for page 3' do
        sigs = constructor.send(:page3_signatures, data['signatures'])
        expect(sigs.length).to eq(2)
        expect(sigs[0].x).to eq(35)
        expect(sigs[0].y).to eq(642)
        expect(sigs[1].x).to eq(35)
        expect(sigs[1].y).to eq(541)
      end
    end

    describe 'phone helper methods' do
      it 'returns nil for international phone when domestic' do
        result = constructor.send(:international_phone, data.dig('veteran', 'phone'))
        expect(result).to be_nil
      end

      it 'returns international format when country code is not 1' do
        intl_phone = { 'countryCode' => '44', 'areaCode' => '20', 'phoneNumber' => '71234567' }
        result = constructor.send(:international_phone, intl_phone)
        expect(result).to eq('+44 20 71234567')
      end

      it 'returns nil for domestic_phone_part when phone is international' do
        intl_phone = { 'countryCode' => '44', 'areaCode' => '20', 'phoneNumber' => '71234567' }
        result = constructor.send(:domestic_phone_part, intl_phone, 'areaCode')
        expect(result).to be_nil
      end
    end

    describe 'service_branch_radio_value' do
      it 'maps all service branches to correct radio values' do
        expect(constructor.send(:service_branch_radio_value, 'ARMY')).to eq(4)
        expect(constructor.send(:service_branch_radio_value, 'AIR FORCE')).to eq(6)
        expect(constructor.send(:service_branch_radio_value, 'COAST GUARD')).to eq(8)
        expect(constructor.send(:service_branch_radio_value, 'SPACE FORCE')).to eq(9)
        expect(constructor.send(:service_branch_radio_value, 'NOAA')).to eq(10)
        expect(constructor.send(:service_branch_radio_value, 'USPHS')).to eq(11)
      end

      it 'returns Off for unknown branch' do
        expect(constructor.send(:service_branch_radio_value, 'UNKNOWN')).to eq('Off')
      end
    end

    it 'constructs a complete PDF without errors' do
      generated_pdf = constructor.construct(data)
      expect(File.exist?(generated_pdf)).to be(true)
      expect(PDF::Reader.new(generated_pdf).pages.size).to eq(3)
      expect(File.size(generated_pdf)).to be_positive
    end
  end
end
