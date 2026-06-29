# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/v2/poa_pdf_constructor/individual'
require_relative '../../../../support/pdf_matcher'

describe ClaimsApi::V2::PoaPdfConstructor::Individual do
  subject { ClaimsApi::V2::PoaPdfConstructor::Individual.new }

  let(:power_of_attorney) { create(:power_of_attorney, :with_full_headers) }
  let(:signatures) do
    { 'page2' => [
      { 'signature' => 'Lillian Disney - signed via api.va.gov', 'x' => 35, 'y' => 306 },
      { 'signature' => 'Bob Law - signed via api.va.gov', 'x' => 35, 'y' => 200 }
    ] }
  end
  let(:rep_attributes) do
    {
      'firstName' => 'Bob',
      'lastName' => 'Law'
    }
  end
  let(:dependent_attributes) do
    {
      'first_name' => 'Lillian',
      'last_name' => 'Disney'
    }
  end
  let(:date_signed) { '01/01/2020' }
  # we do not do anything for item 3
  let(:item_one) { %w[GRAY JESSE] } # veteran name
  let(:item_two) { %w[796 37 8881] } # vet ssn
  let(:item_four) { %w[12 05 1953] } # vet birthdate
  let(:item_five) { '987654321' } # insurance number
  let(:item_six) { [1, 0, 0, 0, 0, 0, 0, nil] } # service branch:
  let(:item_seven) { ['2719 Hyperion Ave', nil, 'Los Angeles', 'CA', 'US', '92264', nil] } # vet address
  let(:item_eight) { '+1 555 5551337' } # telephone
  let(:item_nine) { 'test@example.com' } # email
  let(:item_ten) { %w[Lillian Disney] } # claimant's name
  let(:item_eleven) { ['2688 S Camino Real', nil, 'Palm Springs', 'CA', 'US', '92264', nil] } # claimant's address
  let(:item_twelve) { '+44 555 5551337' } # claimant's telephone
  let(:item_thirteen) { 'lillian@disney.com' } # claimant's email
  let(:item_fourteen) { 'Spouse' } # claimant's relationship to vet
  let(:item_fifteen_a) { 'Bob Law' } # representative name
  let(:item_fifteen_b) { [1, 0] } # representative type: ATTORNEY or AGENT
  let(:item_eighteen) { '2719 Hyperion Ave, Los Angeles CA 92264' } # address of rep
  let(:item_nineteen) { 1 } # record consent
  let(:item_twenty) { %(DRUG ABUSE, SICKLE CELL) } # consent limits
  let(:item_twenty_one) { 1 } # consentAddressChange
  # 22b and 24b are date signed
  let(:item_twenty_three) { %(Condition 1, Condition 2) } # conditionsOfAppointment
  let(:expected_page1_values) do
    [
      *item_one, *item_two, *item_four, item_five, *item_six, *item_seven,
      item_eight, item_nine, *item_ten, *item_eleven, item_twelve,
      item_thirteen, item_fourteen, item_fifteen_a, *item_fifteen_b,
      item_eighteen
    ]
  end
  let(:expected_page2_values) do
    [
      *item_two, item_nineteen, *item_twenty, item_twenty_one, date_signed,
      *item_twenty_three, date_signed
    ]
  end

  before do
    Timecop.freeze(Time.zone.parse('2020-01-01T08:00:00Z'))
    power_of_attorney.form_data = {
      veteran: {
        serviceNumber: '987654321',
        serviceBranch: 'ARMY',
        address: {
          addressLine1: '2719 Hyperion Ave',
          city: 'Los Angeles',
          stateCode: 'CA',
          country: 'US', # legacy code digs 'country'
          countryCode: 'US', # updated code digs 'countryCode'
          zipCode: '92264'
        },
        phone: {
          countryCode: '1',
          areaCode: '555',
          phoneNumber: '5551337'
        },
        email: 'test@example.com'
      },
      claimant: {
        claimantId: '00000000V0000',
        email: 'lillian@disney.com',
        relationship: 'Spouse',
        dateOfBirth: '1955-03-15', # updated form only
        address: {
          addressLine1: '2688 S Camino Real',
          city: 'Palm Springs',
          stateCode: 'CA',
          country: 'US', # legacy code digs 'country'
          countryCode: 'US', # updated code digs 'countryCode'
          zipCode: '92264'
        },
        phone: {
          countryCode: '44',
          areaCode: '555',
          phoneNumber: '5551337'
        }
      },
      representative: {
        poaCode: 'A1Q',
        registrationNumber: '1234',
        type: 'ATTORNEY',
        address: {
          addressLine1: '2719 Hyperion Ave',
          city: 'Los Angeles',
          stateCode: 'CA',
          country: 'US', # legacy code digs 'country'
          countryCode: 'US', # updated code digs 'countryCode'
          zipCode: '92264'
        }
      },
      recordConsent: true,
      consentAddressChange: true,
      consentLimits: %w[DRUG_ABUSE SICKLE_CELL],
      consentDisclosureAffiliated: true, # updated form only
      firmOrOrgName: 'Law Offices of Bob', # updated form only
      consentDisclosureIndividuals: true, # updated form only
      individualNames: ['Alice Smith', 'Charlie Brown'], # updated form only
      conditionsOfAppointment: ['Condition 1', 'Condition 2']
    }
    power_of_attorney.form_data.deep_merge!(
      {
        'veteran' => veteran_attributes(power_of_attorney.auth_headers),
        'representative' => rep_attributes,
        'dependent' => dependent_attributes,
        'appointmentDate' => power_of_attorney.created_at,
        'text_signatures' => signatures
      }
    )
    power_of_attorney.save!
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122a_pdf_form_update).and_return(false)
  end

  after do
    Timecop.return
  end

  context 'pdf_template_subdir' do
    context 'when lighthouse_claims_api_2122a_pdf_form_update is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122a_pdf_form_update).and_return(true)
      end

      it 'uses the rev_07_2023 template paths' do
        expect(subject.send(:page1_template_path).to_s).to include('rev_07_2023/1.pdf')
        expect(subject.send(:page2_template_path).to_s).to include('rev_07_2023/2.pdf')
        expect(subject.send(:page3_template_path).to_s).to include('rev_07_2023/3.pdf')
      end
    end

    context 'when lighthouse_claims_api_2122a_pdf_form_update is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122a_pdf_form_update).and_return(false)
      end

      it 'uses the original template paths' do
        expect(subject.send(:page1_template_path).to_s).not_to include('rev_07_2023')
        expect(subject.send(:page2_template_path).to_s).to end_with('21-22A/2.pdf')
        expect(subject.send(:page3_template_path).to_s).to end_with('21-22A/3.pdf')
      end
    end
  end

  context 'page1_options' do
    it 'returns the expected values' do
      res = subject.send(:page1_options, power_of_attorney.form_data)

      expect(res.values).to match(expected_page1_values)
    end
  end

  context 'page2_options' do
    it 'returns the expected values' do
      res = subject.send(:page2_options, power_of_attorney.form_data)

      expect(res.values).to match(expected_page2_values)
    end
  end

  context 'when lighthouse_claims_api_2122a_pdf_form_update is enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122a_pdf_form_update).and_return(true)
    end

    context 'page1_options' do
      it 'maps all fields to updated field names' do
        res = subject.send(:page1_options, power_of_attorney.form_data)

        # Section I - Veteran
        # Item 1 - Veteran Name: JESSE GRAY
        expect(res[:'form1[0].#subform[0].Veterans_First_Name[0]']).to eq('JESSE')
        expect(res[:'form1[0].#subform[0].Veterans_Last_Name[0]']).to eq('GRAY')
        # Item 2 - SSN: 796-37-8881
        expect(res[:'form1[0].#subform[0].SocialSecurityNumber_FirstThreeNumbers[0]']).to eq('796')
        expect(res[:'form1[0].#subform[0].SocialSecurityNumber_SecondTwoNumbers[0]']).to eq('37')
        expect(res[:'form1[0].#subform[0].SocialSecurityNumber_LastFourNumbers[0]']).to eq('8881')
        # Item 4 - DOB: 12/05/1953
        expect(res[:'form1[0].#subform[0].Date_Of_Birth_Month[0]']).to eq('12')
        expect(res[:'form1[0].#subform[0].Date_Of_Birth_Day[0]']).to eq('05')
        expect(res[:'form1[0].#subform[0].Date_Of_Birth_Year[0]']).to eq('1953')
        # Item 5 - Service Number: 987654321
        expect(res[:'form1[0].#subform[0].Veterans_Service_Number_If_Applicable[1]']).to eq('987654321')
        # Item 6 - Service Branch: ARMY (radio 4)
        expect(res[:'form1[0].#subform[0].RadioButtonList[1]']).to eq(4)
        # Item 7 - Veteran Address: 2719 Hyperion Ave, Los Angeles, CA, US 92264
        expect(res[:'form1[0].#subform[0].MailingAddress_NumberAndStreet[0]']).to eq('2719 Hyperion Ave')
        expect(res[:'form1[0].#subform[0].MailingAddress_ApartmentOrUnitNumber[0]']).to be_nil
        expect(res[:'form1[0].#subform[0].MailingAddress_City[0]']).to eq('Los Angeles')
        expect(res[:'form1[0].#subform[0].MailingAddress_StateOrProvince[0]']).to eq('CA')
        expect(res[:'form1[0].#subform[0].MailingAddress_Country[0]']).to eq('US')
        expect(res[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]']).to eq('92264')
        expect(res[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]']).to be_nil
        # Item 8 - Veteran Phone (domestic): 555-555-1337
        expect(res[:'form1[0].#subform[0].Telephone_Number_Area_Code[1]']).to eq('555')
        expect(res[:'form1[0].#subform[0].Telephone_Middle_Three_Numbers[0]']).to eq('555')
        expect(res[:'form1[0].#subform[0].Telephone_Last_Four_Numbers[1]']).to eq('1337')
        expect(res[:'form1[0].#subform[0].International_Telephone_Number_If_Applicable[0]']).to be_nil
        # Item 9 - Veteran Email: test@example.com
        expect(res[:'form1[0].#subform[0].E_Mail_Address_Optional[1]']).to eq('test@example.com')

        # Section II - Claimant
        # Item 10 - Claimant Name: Lillian Disney
        expect(res[:'form1[0].#subform[0].Claimants_First_Name[0]']).to eq('Lillian')
        expect(res[:'form1[0].#subform[0].Claimants_Last_Name[0]']).to eq('Disney')
        # Item 11 - Claimant DOB: 03/15/1955
        expect(res[:'form1[0].#subform[0].Claimants_Date_Of_Birth_Month[0]']).to eq('03')
        expect(res[:'form1[0].#subform[0].Date_Of_Birth_Day[1]']).to eq('15')
        expect(res[:'form1[0].#subform[0].Date_Of_Birth_Year[1]']).to eq('1955')
        # Item 12 - Relationship: Spouse
        expect(res[:'form1[0].#subform[0].RelationshipToVeteran[0]']).to eq('Spouse')
        # Item 13 - Claimant Address: 2688 S Camino Real, Palm Springs, CA, US 92264
        expect(res[:'form1[0].#subform[0].MailingAddress_NumberAndStreet[1]']).to eq('2688 S Camino Real')
        expect(res[:'form1[0].#subform[0].MailingAddress_ApartmentOrUnitNumber[1]']).to be_nil
        expect(res[:'form1[0].#subform[0].MailingAddress_City[1]']).to eq('Palm Springs')
        expect(res[:'form1[0].#subform[0].MailingAddress_StateOrProvince[1]']).to eq('CA')
        expect(res[:'form1[0].#subform[0].MailingAddress_Country[1]']).to eq('US')
        expect(res[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]']).to eq('92264')
        expect(res[:'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]']).to be_nil
        # Item 14 - Claimant Phone (international): +44 555 5551337
        expect(res[:'form1[0].#subform[0].Telephone_Number_Area_Code[0]']).to be_nil
        expect(res[:'form1[0].#subform[0].Telphone_Middle_Three_Numbers[0]']).to be_nil
        expect(res[:'form1[0].#subform[0].Telephone_Last_Four_Numbers[0]']).to be_nil
        expect(res[:'form1[0].#subform[0].International_Telephone_Number_If_Applicable[1]']).to eq('+44 555 5551337')
        # Item 15 - Claimant Email: lillian@disney.com
        expect(res[:'form1[0].#subform[0].E_Mail_Address_Optional[0]']).to eq('lillian@disney.com')

        # Section III - Representative
        # Item 16A - Rep Name: Bob Law
        expect(res[:'form1[0].#subform[0].Name_Of_Individual_Appointed_As_Representative_First_Name[0]']).to eq('Bob')
        expect(res[:'form1[0].#subform[0].Last_Name[0]']).to eq('Law')
        # Item 16B - Rep Type: ATTORNEY (radio 4)
        expect(res[:'form1[0].#subform[0].RadioButtonList[0]']).to eq(4)
      end
    end

    context 'page2_options' do
      it 'maps all consent and rep address fields' do
        res = subject.send(:page2_options, power_of_attorney.form_data)

        # SSN header: 796-37-8881
        expect(res[:'form1[0].#subform[1].SocialSecurityNumber_FirstThreeNumbers[1]']).to eq('796')
        expect(res[:'form1[0].#subform[1].SocialSecurityNumber_SecondTwoNumbers[1]']).to eq('37')
        expect(res[:'form1[0].#subform[1].SocialSecurityNumber_LastFourNumbers[1]']).to eq('8881')
        # Item 16C - Rep Address: 2719 Hyperion Ave, Los Angeles, CA, US 92264
        expect(res[:'form1[0].#subform[1].MailingAddress_NumberAndStreet[2]']).to eq('2719 Hyperion Ave')
        expect(res[:'form1[0].#subform[1].MailingAddress_ApartmentOrUnitNumber[2]']).to be_nil
        expect(res[:'form1[0].#subform[1].MailingAddress_City[2]']).to eq('Los Angeles')
        expect(res[:'form1[0].#subform[1].MailingAddress_StateOrProvince[2]']).to eq('CA')
        expect(res[:'form1[0].#subform[1].MailingAddress_Country[2]']).to eq('US')
        expect(res[:'form1[0].#subform[1].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[2]']).to eq('92264')
        expect(res[:'form1[0].#subform[1].MailingAddress_ZIPOrPostalCode_LastFourNumbers[2]']).to be_nil
        # Item 19a - Disclosure to affiliated: 1, firm='Law Offices of Bob'
        disclosure_checkbox = 'form1[0].#subform[1].Checkbox_I_Authorize_VA_To_Disclose' \
                              '_All_My_Records_Other_Than_As_Provided_In_Items_20_And_21'
        expect(res[:"#{disclosure_checkbox}[0]"]).to eq(1)
        firm_field = 'form1[0].#subform[1].Provide_The_Name_Of_The_Firm_Or_Organization_Here[0]'
        expect(res[firm_field.to_sym]).to eq('Law Offices of Bob')
        # Item 19b - Disclosure to individuals: 1, names='Alice Smith, Charlie Brown'
        expect(res[:"#{disclosure_checkbox}[1]"]).to eq(1)
        names_field = 'form1[0].#subform[1].Provide_The_Names_Of_The_Individuals_Here[0]'
        expect(res[names_field.to_sym]).to eq('Alice Smith, Charlie Brown')
        # Item 20 - Record Consent: 1
        expect(res[:'form1[0].#subform[1].AuthorizationForRepAccessToRecords[0]']).to eq(1)
        # Item 21 - Consent Limits: DRUG ABUSE, SICKLE CELL
        expect(res[:'form1[0].#subform[1].RelationshipToVeteran[1]']).to eq('DRUG ABUSE, SICKLE CELL')
        # Item 22 - Address Change: 1
        expect(res[:'form1[0].#subform[1].AuthorizationForRepActClaimantsBehalf[0]']).to eq(1)
      end
    end

    context 'page3_options' do
      it 'maps all SSN header, date, and limitation fields' do
        res = subject.send(:page3_options, power_of_attorney.form_data)

        # SSN header: 796-37-8881
        expect(res[:'form1[0].#subform[2].SocialSecurityNumber_FirstThreeNumbers[2]']).to eq('796')
        expect(res[:'form1[0].#subform[2].SocialSecurityNumber_SecondTwoNumbers[2]']).to eq('37')
        expect(res[:'form1[0].#subform[2].SocialSecurityNumber_LastFourNumbers[2]']).to eq('8881')
        # Item 23B - Date Signed (Veteran/Claimant): 01/01/2020
        expect(res[:'form1[0].#subform[2].Date_Signed_Month[2]']).to eq('01')
        expect(res[:'form1[0].#subform[2].Date_Signed_Day[2]']).to eq('01')
        expect(res[:'form1[0].#subform[2].Date_Signed_Year[2]']).to eq('2020')
        # Item 24 - Limitations: Condition 1, Condition 2
        expect(res[:'form1[0].#subform[2].LIMITATIONS[0]']).to eq('Condition 1, Condition 2')
        # Item 25B - Date Signed (Representative): 01/01/2020
        expect(res[:'form1[0].#subform[2].Date_Signed_Month[3]']).to eq('01')
        expect(res[:'form1[0].#subform[2].Date_Signed_Day[3]']).to eq('01')
        expect(res[:'form1[0].#subform[2].Date_Signed_Year[3]']).to eq('2020')
      end

      it 'places signatures on page3 at the correct coordinates' do
        coords = described_class.signature_coordinates
        expect(coords[:page]).to eq('page3')
        expect(coords[:veteran]).to eq({ x: 35, y: 626 })
        expect(coords[:representative]).to eq({ x: 35, y: 525 })
      end
    end

    context 'service_branch_radio_value' do
      it 'maps known branches to radio values' do
        expect(subject.send(:service_branch_radio_value, 'ARMY')).to eq(4)
        expect(subject.send(:service_branch_radio_value, 'NAVY')).to eq(5)
        expect(subject.send(:service_branch_radio_value, 'AIR_FORCE')).to eq(6)
        expect(subject.send(:service_branch_radio_value, 'MARINE_CORPS')).to eq(7)
        expect(subject.send(:service_branch_radio_value, 'COAST_GUARD')).to eq(8)
        expect(subject.send(:service_branch_radio_value, 'SPACE_FORCE')).to eq(9)
      end

      it 'returns Off for unknown branches' do
        expect(subject.send(:service_branch_radio_value, 'UNKNOWN')).to eq('Off')
      end
    end

    context 'rep_type_radio_value' do
      it 'maps known types to radio values' do
        expect(subject.send(:rep_type_radio_value, 'ATTORNEY')).to eq(4)
        expect(subject.send(:rep_type_radio_value, 'AGENT')).to eq(1)
      end

      it 'returns Off for unknown types' do
        expect(subject.send(:rep_type_radio_value, 'UNKNOWN')).to eq('Off')
      end
    end

    context 'international_phone' do
      it 'returns nil for domestic phones' do
        phone = { 'countryCode' => '1', 'areaCode' => '555', 'phoneNumber' => '5551337' }
        expect(subject.send(:international_phone, phone)).to be_nil
      end

      it 'returns formatted string for international phones' do
        phone = { 'countryCode' => '44', 'areaCode' => '555', 'phoneNumber' => '5551337' }
        expect(subject.send(:international_phone, phone)).to eq('+44 555 5551337')
      end

      it 'returns nil for blank phone' do
        expect(subject.send(:international_phone, nil)).to be_nil
      end
    end

    context 'fill_pdf' do
      it 'invokes pdftk fill_form for page 3' do
        pdftk = instance_double(PdfForms::PdftkWrapper)
        allow(PdfForms).to receive(:new).and_return(pdftk)
        allow(pdftk).to receive(:fill_form)

        subject.send(:fill_pdf, power_of_attorney.form_data)

        expect(pdftk).to have_received(:fill_form).exactly(3).times
      end
    end
  end

  private

  def veteran_attributes(auth_headers)
    {
      'firstName' => auth_headers['va_eauth_firstName'],
      'lastName' => auth_headers['va_eauth_lastName'],
      'ssn' => auth_headers['va_eauth_pnid'],
      'birthdate' => auth_headers['va_eauth_birthdate']
    }
  end

  def data_for_poa(poa)
    {
      'veteran' => veteran(poa.auth_headers),
      'appointmentDate' => poa.created_at,
      'text_signatures' => signatures,
      'representative' => representative
    }
  end
end
