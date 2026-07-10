# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA210788 do
  subject(:form) { described_class.new(data) }

  let(:fixture_file) { 'vba_21_0788.json' }

  let(:fixture_path) do
    Rails.root.join(
      'modules',
      'simple_forms_api',
      'spec',
      'fixtures',
      'form_json',
      fixture_file
    )
  end

  let(:data) { JSON.parse(fixture_path.read) }

  describe '#data' do
    subject { form.data }

    it { is_expected.to match(data) }
  end

  describe '#address' do
    subject(:address) { form.address }

    it { is_expected.to be_a(FormEngine::Address) }

    it 'maps correctly' do
      expect(address.address_line1).to eq data.dig('address', 'street')
      expect(address.address_line2).to eq data.dig('address', 'street2')
      expect(address.city).to eq data.dig('address', 'city')
      expect(address.state_code).to eq data.dig('address', 'state')
      expect(address.zip_code).to eq data.dig('address', 'postal_code')
      expect(address.country_code_iso3).to eq data.dig('address', 'country')
    end
  end

  describe '#first_name' do
    subject { form.first_name }

    it { is_expected.to eq data.dig('full_name', 'first') }
  end

  describe '#middle_name' do
    subject { form.middle_name }

    it { is_expected.to eq data.dig('full_name', 'middle') }
  end

  describe '#last_name' do
    subject { form.last_name }

    it { is_expected.to eq data.dig('full_name', 'last') }
  end

  describe '#full_name' do
    subject { form.full_name }

    it 'joins name parts' do
      expect(subject).to eq(
        [
          data.dig('full_name', 'first'),
          data.dig('full_name', 'middle'),
          data.dig('full_name', 'last')
        ].compact.join(' ')
      )
    end
  end

  describe '#full_name(name_object)' do
    it 'joins name parts of provided object' do
      name_obj = {
        'first' => 'Testy',
        'middle' => 'T',
        'last' => 'McTestFace'
      }.to_json
      form.full_name(name_obj)
      expect(subject).to eq('Testy T McTestFace')
    end
  end

  describe '#notification_first_name' do
    subject { form.notification_first_name }

    it { is_expected.to eq data.dig('full_name', 'first') }
  end

  describe '#notification_last_name' do
    subject { form.notification_last_name }

    it { is_expected.to eq data.dig('full_name', 'last') }
  end

  describe '#notification_email_address' do
    subject { form.notification_email_address }

    it { is_expected.to eq data['email_address'] }

    context 'when email_address is blank' do
      let(:data) { super().merge('email_address' => '') }

      it { is_expected.to be_nil }
    end
  end

  describe '#track_user_identity' do
    it 'tracks the 21-0788 submission identity' do
      confirmation_number = 'ABC123'

      expect(StatsD).to receive(:increment).with('api.simple_forms_api.21_0788.submission')
      expect(Rails.logger).to receive(:info).with(
        'Simple forms api - 21-0788 submission user identity',
        identity: 'submission',
        confirmation_number:
      )

      described_class.new({}).track_user_identity(confirmation_number)
    end
  end

  describe '#full_address' do
    subject { form.full_address }

    it 'joins address parts with commas and removes nil values' do
      expect(subject).to eq(
        [
          form.address.address_line1,
          form.address.address_line2,
          form.address.city,
          form.address.state_code,
          form.address.zip_code
        ].compact.join(', ')
      )
    end
  end

  describe '#zip_code' do
    subject { form.zip_code }

    it { is_expected.to eq data.dig('address', 'postal_code') }
  end

  describe '#zip_code_is_us_based' do
    subject { form.zip_code_is_us_based }

    context 'when country is USA' do
      it { is_expected.to be true }
    end

    context 'when country is not USA' do
      let(:data) do
        super().merge(
          'address' => super()['address'].merge('country' => 'CAN')
        )
      end

      it { is_expected.to be false }
    end
  end

  describe '#ssn' do
    subject { form.ssn }

    it { is_expected.to eq data['ssn'] }
  end

  describe '#file_number' do
    subject { form.file_number }

    it { is_expected.to eq data['va_file_number'] }
  end

  describe '#metadata_file_number' do
    subject { form.metadata_file_number }

    context 'when VA file number is present' do
      let(:data) { super().merge('va_file_number' => 'C12345678') }

      it 'strips non-digits from the VA file number' do
        expect(subject).to eq '12345678'
      end
    end

    context 'when VA file number is numeric' do
      let(:data) { super().merge('va_file_number' => '123456789') }

      it { is_expected.to eq '123456789' }
    end

    context 'when VA file number is missing' do
      let(:data) { super().merge('va_file_number' => nil) }

      it 'falls back to SSN digits' do
        expect(subject).to eq data['ssn'].gsub(/\D/, '')
      end
    end
  end

  describe '#relationship' do
    subject { form.relationship }

    it { is_expected.to eq data['relationship_to_veteran'] }
  end

  describe '#phone' do
    subject { form.phone }

    it { is_expected.to match(/\d{3}-\d{3}-\d{4}/) }
  end

  describe '#email' do
    subject { form.email }

    it { is_expected.to eq data['email'] }
  end

  describe '#legally_adopted?' do
    subject { form.legally_adopted? }

    it { is_expected.to eq data['legally_adopted'] }
  end

  describe '#stepchild_living_in_household?' do
    subject { form.stepchild_living_in_household? }

    it { is_expected.to eq data['stepchild_living_in_household'] }
  end

  describe 'INCARCERATION_BLOCKS' do
    it 'has correct mapping for veteran incarcerated' do
      expect(described_class::INCARCERATION_BLOCKS[:veteran_incarcerated]).to eq(
        {
          main: 2,
          felony: 3,
          misdemeanor: 4
        }
      )
    end

    it 'has correct mapping for spouse or child incarcerated' do
      expect(described_class::INCARCERATION_BLOCKS[:spouse_or_child_incarcerated]).to eq(
        {
          main: 5,
          felony: 6,
          misdemeanor: 7
        }
      )
    end
  end

  describe 'SINGLE_REASONS' do
    it 'matches expected mapping' do
      expect(described_class::SINGLE_REASONS).to eq(
        {
          veteran_incompetent_no_fiduciary: 8,
          veteran_pension_care_facility: 9,
          enemy_territory_resident: 10,
          veteran_disappeared: 11
        }
      )
    end
  end

  describe '#incarceration_fields' do
    subject(:result) { form.incarceration_fields }

    context 'veteran incarcerated with felony and misdemeanor' do
      let(:data) do
        super().merge(
          'reason' => 'veteran_incarcerated',
          'incarceration' => {
            'felony' => true,
            'misdemeanor' => true
          }
        )
      end

      it 'sets veteran incarceration block correctly' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[2]' => '0',
          'form1[0].Page_2[0].RadioButtonList[3]' => '0',
          'form1[0].Page_2[0].RadioButtonList[4]' => '0'
        )
      end
    end

    context 'spouse or child incarcerated without felony/misdemeanor' do
      let(:data) do
        super().merge(
          'reason' => 'spouse_or_child_incarcerated',
          'incarceration' => {
            'felony' => false,
            'misdemeanor' => false
          }
        )
      end

      it 'sets spouse/child block correctly' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[5]' => '0',
          'form1[0].Page_2[0].RadioButtonList[6]' => 'Off',
          'form1[0].Page_2[0].RadioButtonList[7]' => 'Off'
        )
      end
    end

    context 'single reason: veteran disappeared' do
      let(:data) do
        super().merge('reason' => 'veteran_disappeared')
      end

      it 'sets correct single reason radio' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[11]' => '0'
        )
      end
    end
  end

  describe '#facility_name' do
    subject { form.facility_name }

    it { is_expected.to eq data['facility_name'] }
  end

  describe '#facility_address' do
    subject { form.facility_address }

    it { is_expected.to eq data['facility_address'] }
  end

  describe '#remarks' do
    subject { form.remarks }

    # rubocop:disable Layout/LineLength
    it 'returns string if under limit' do
      under_limit_string =
        'King Arthur is the legendary King of Britain who united the realm from Camelot. Advised by Merlin, he wielded Excalibur and led the Knights of the Round Table—elite warriors bound by chivalry. His most honorable knights include: Lancelot (bravest but flawed by love for Guinevere), Gawain, Galahad, Perceval, and others. They quested for the Holy Grail until betrayal and civil war ended the golden age. Arthur was taken to Avalon, destined to return'
      data['remarks'] = under_limit_string

      expect(form.remarks).to eq(under_limit_string)
    end

    it "returns 'See Additional Page' if over the limit" do
      over_limit_string =
        "The Charge of the Winged Hussars Battle of Vienna (1683)
        This is one of history's most legendary cavalry moments. In September 1683, the Ottoman Empire under Grand Vizier Kara Mustafa besieged Vienna for two months, coming close to capturing the city and potentially opening the way for further expansion into Europe. The Habsburg defenders held out desperately, but relief arrived when King John III Sobieski of Poland led a coalition force to the rescue.
        The climax was the largest cavalry charge in recorded history: around 18,000 horsemen"
      data['remarks'] = over_limit_string

      expect(form.remarks).to eq('See Additional Page')
    end
    # rubocop:enable Layout/LineLength

    it 'a blank string if not present' do
      data['remarks'] = nil
      expect(form.remarks).to eq('')
    end
  end

  describe '#signature' do
    subject { form.signature }

    it { is_expected.to eq data['statement_of_truth_signature'] }
  end

  describe '#signature_date' do
    subject { form.signature_date }

    context 'when present' do
      it { is_expected.to match(%r{\d{2}/\d{2}/\d{4}}) }
    end

    context 'when missing' do
      let(:data) { super().merge('signature_date' => nil) }

      it { is_expected.to match(%r{\d{2}/\d{2}/\d{4}}) }

      it 'autofills with the current data' do
        expect(form.signature_date).to eq(Time.current.in_time_zone('America/Chicago').strftime('%m/%d/%Y'))
      end
    end
  end

  describe '#other_relationship_text' do
    it 'clips text for the relationship fields' do
      # under limit
      str = "father's, brother's, nephew's, cousin's, former roommate, but for only one semester aboard in canada12345"
      data['other_relationship_description'] = str
      expect(form.other_relationship_text).to eq(str)

      # over limit
      str = "father's, brother's, nephew's, cousin's, former roommate, but for only one semester aboard in canada123456"
      data['other_relationship_description'] = str
      expect(form.other_relationship_text).to eq("See Add'l page")
    end
  end

  describe '#apportionment_fields_relationship' do
    it 'formats and uses the correct relationship text for people in the table' do
      person = { 'relationship' => 'child' }
      expect(form.apportionment_fields_relationship(person)).to eq('child')

      person = { 'relationship' => 'other', 'other_relationship_description' => 'under the limit' }
      expect(form.apportionment_fields_relationship(person)).to eq('under the limit')

      person = { 'relationship' => 'other', 'other_relationship_description' => 'over the 25 character limit' }
      expect(form.apportionment_fields_relationship(person)).to eq("See Add'l page")
    end
  end

  describe '#apportionment_fields' do
    it 'Maps field to json for the pdf' do
      data['apportionment_people'] = [
        {
          'full_name' => 'Lancelot',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => false,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2001-01-11'
        },
        {
          'full_name' => 'Gawain',
          'ssn' => '123-12-2134',
          'relationship' => 'other',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => true,
          'other_relationship_description' => 'captain',
          'stepchild_departure_date' => '2020-02-12'
        },
        {
          'full_name' => 'Percival',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2013-03-13'
        },
        {
          'full_name' => 'Sagramor',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => false,
          'stepchild_lives_with_veteran' => true,
          'stepchild_departure_date' => '2024-24-14'
        }
      ]
      mapped = form.apportionment_fields
      expect(mapped).to eq(
        {
          'form1[0].Page_1[0].NAMEVETERAN[3]' => 'Lancelot',
          'form1[0].Page_1[0].NAMEVETERAN[7]' => '123-12-2134',
          'form1[0].Page_1[0].NAMEVETERAN[11]' => 'child',
          'form1[0].Page_1[0].RadioButtonList[6]' => '1',
          'form1[0].Page_1[0].NAMEVETERAN[4]' => 'Gawain',
          'form1[0].Page_1[0].NAMEVETERAN[8]' => '123-12-2134',
          'form1[0].Page_1[0].NAMEVETERAN[12]' => 'captain',
          'form1[0].Page_1[0].RadioButtonList[10]' => '1',
          'form1[0].Page_1[0].NAMEVETERAN[5]' => 'Percival',
          'form1[0].Page_1[0].NAMEVETERAN[9]' => '123-12-2134',
          'form1[0].Page_1[0].NAMEVETERAN[13]' => 'child',
          'form1[0].Page_1[0].RadioButtonList[9]' => '1',
          'form1[0].Page_1[0].NAMEVETERAN[6]' => 'Sagramor',
          'form1[0].Page_1[0].NAMEVETERAN[10]' => '123-12-2134',
          'form1[0].Page_1[0].NAMEVETERAN[14]' => 'child',
          'form1[0].Page_1[0].RadioButtonList[11]' => '1'
        }
      )
    end
  end

  describe '#metadata' do
    subject { form.metadata }

    it 'returns expected structure when bugfix is off' do
      allow(Flipper).to receive(:enabled?).with(:simple_forms_s3_mms_prefix_bugfix).and_return(false)
      expect(subject).to include(
        'veteranFirstName' => form.first_name,
        'veteranLastName' => form.last_name,
        'fileNumber' => form.metadata_file_number,
        'zipCode' => form.zip_code,
        'source' => 'VA Platform Digital Forms',
        'docType' => data['form_number'],
        'businessLine' => 'CMP'
      )
    end

    it 'returns expected structure when bug fix is on' do
      allow(Flipper).to receive(:enabled?).with(:simple_forms_s3_mms_prefix_bugfix).and_return(true)
      expect(subject).to include(
        'veteranFirstName' => form.first_name,
        'veteranLastName' => form.last_name,
        'fileNumber' => form.metadata_file_number,
        'zipCode' => form.zip_code,
        'source' => 'VA Platform Digital Forms',
        'docType' => "StructuredData:#{data['form_number']}",
        'businessLine' => 'CMP'
      )
    end
  end

  describe '#format_phone' do
    it 'formats phone correctly' do
      expect(form.format_phone('1234567890')).to eq('123-456-7890')
    end
  end

  describe '#departure_date' do
    it 'extracts and formats dates from people' do
      data['apportionment_people'] = [
        {
          'full_name' => 'Philip J Fry',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-03-15'
        }
      ]

      expect(form.departure_date).to eq('03/15/2000')
    end

    it 'extracts and formats dates from multiple people' do
      data['apportionment_people'] = [
        {
          'full_name' => 'Lancelot',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-03-11'
        },
        {
          'full_name' => 'Gawain',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-03-12'
        },
        {
          'full_name' => 'Percival',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-03-13'
        },
        {
          'full_name' => 'Sagramor',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-03-14'
        }
      ]

      expect(form.departure_date).to eq('03/11/2000,03/12/2000,03/13/2000,03/14/2000')
    end

    it 'extracts and formats dates from multiple people when there is a date to parse' do
      data['apportionment_people'] = [
        {
          'full_name' => 'Lancelot',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-13-13' # <- invaid date
        },
        {
          'full_name' => 'Galahad',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2000-32-32' # <- invaid date
        },
        {
          'full_name' => 'Percival',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => 'Not a Date String'
        },
        {
          'full_name' => 'Sagramor',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => ''
        }
      ]

      expect(form.departure_date).to eq('')
    end

    it 'extracts and formats dates from only childs who meet criteria' do
      data['apportionment_people'] = [
        {
          'full_name' => 'Lancelot',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => false,
          'stepchild_lives_with_veteran' => false,
          'stepchild_departure_date' => '2001-01-11'
        },
        {
          'full_name' => 'Gawain',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => true,
          'stepchild_lives_with_veteran' => true,
          'stepchild_departure_date' => '2020-02-12'
        },
        {
          'full_name' => 'Percival',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => true,
          'is_stepchild' => true, # <- needs to be false
          'stepchild_lives_with_veteran' => false, # <-needs to be true
          'stepchild_departure_date' => '2013-03-13'
        },
        {
          'full_name' => 'Sagramor',
          'ssn' => '123-12-2134',
          'relationship' => 'child',
          'currently_receiving' => false,
          'is_stepchild' => false,
          'stepchild_lives_with_veteran' => true,
          'stepchild_departure_date' => '2024-24-14'
        }
      ]

      expect(form.departure_date).to eq('03/13/2013')
    end
  end

  describe '#format_date_mm_dd_yyyy' do
    it 'turns date strings into MM/DD/YYYY format' do
      # Parseable
      expect(form.format_date_mm_dd_yyyy('1948-11-17')).to eq('11/17/1948')
      expect(form.format_date_mm_dd_yyyy('1948/11/17')).to eq('11/17/1948')

      # Not parseable
      expect(form.format_date_mm_dd_yyyy('11-17-1948')).to eq('')
      expect(form.format_date_mm_dd_yyyy('11/17/1948')).to eq('')
      expect(form.format_date_mm_dd_yyyy('')).to eq('')
      expect(form.format_date_mm_dd_yyyy(12)).to eq('')
      expect(form.format_date_mm_dd_yyyy(true)).to eq('')
      expect(form.format_date_mm_dd_yyyy(false)).to eq('')
      expect(form.format_date_mm_dd_yyyy('99-99-99')).to eq('')
    end
  end
end
