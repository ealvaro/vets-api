# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/v1/poa_pdf_constructor/organization'
require_relative '../../../../support/pdf_matcher'

describe ClaimsApi::V1::PoaPdfConstructor::Organization do
  let(:b64_image) { File.read('modules/claims_api/spec/fixtures/signature_b64.txt') }

  let(:veteran_form_data) do
    {
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
        },
        email: 'veteran@nonsensedomain.org'
      },
      serviceOrganization: {
        address: {
          numberAndStreet: '2719 Hyperion Ave',
          city: 'Los Angeles',
          state: 'CA',
          country: 'US',
          zipFirstFive: '92264'
        },
        organizationName: 'Official Service Organization',
        firstName: 'Igor',
        lastName: 'Sikorsky',
        jobTitle: 'Veteran Service representative',
        email: 'attorneyatlaw@nonsensedomain.org'
      },
      recordConsent: true,
      consentLimits: ['DRUG ABUSE', 'SICKLE CELL'],
      consentAddressChange: true
    }
  end

  let(:international_phone_form_data) do
    {
      phone: {
        countryCode: '1',
        areaCode: '555',
        phoneNumber: '5551337'
      }
    }
  end

  let(:claimant_form_data) do
    {
      claimant: {
        firstName: 'Wally',
        middleInitial: 'J',
        lastName: 'Morrell',
        dateOfBirth: '1980-01-01',
        address: {
          numberAndStreet: '456 Elm Ave',
          aptUnitNumber: '12',
          city: 'Salem',
          state: 'MA',
          country: 'US',
          zipFirstFive: '97301',
          zipLastFour: '5678',
          additionalProperties: true
        },
        phone: {
          countryCode: '1',
          areaCode: '541',
          phoneNumber: '5551234',
          phoneNumberExt: '99'
        },
        email: 'claimant@example.com',
        relationship: 'Spouse'
      }
    }
  end

  let(:constructor) { described_class.new }
  let(:base_form_data) { veteran_form_data }
  let(:form_data_overrides) { {} }
  let(:form_data) { base_form_data.deep_merge(form_data_overrides) }
  let(:fixed_auth_headers) do
    {
      va_eauth_pnid: '796378881',
      va_eauth_pid: '796378881',
      va_eauth_birthdate: '1953-12-05',
      va_eauth_firstName: 'JESSE',
      va_eauth_lastName: 'GRAY'
    }
  end
  # ralph has a claimant in test data, so using his auth headers to test claimant mapping
  let(:ralph_auth_headers) do
    {
      va_eauth_pnid: '796378782',
      va_eauth_pid: '796378782',
      va_eauth_birthdate: '1948-10-30',
      va_eauth_firstName: 'Ralph',
      va_eauth_lastName: 'Lee'
    }
  end
  let(:power_of_attorney) do
    create(:power_of_attorney, :with_full_headers).tap do |record|
      record.update!(form_data:, auth_headers: fixed_auth_headers)
    end
  end
  let(:data) do
    power_of_attorney.form_data.deep_merge(
      {
        'veteran' => {
          'firstName' => power_of_attorney.auth_headers['va_eauth_firstName'],
          'lastName' => power_of_attorney.auth_headers['va_eauth_lastName'],
          'ssn' => power_of_attorney.auth_headers['va_eauth_pnid'],
          'birthdate' => power_of_attorney.auth_headers['va_eauth_birthdate']
        }
      }
    )
  end

  describe 'with lighthouse_claims_api_2122_pdf_form_update_v1 feature flag disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122_pdf_form_update_v1).and_return(false)
      Timecop.freeze(Time.zone.parse('2020-01-01T08:00:00Z'))
    end

    after do
      Timecop.return
    end

    it 'construct pdf' do
      expected_pdf = Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', '21-22', 'signed_filled_final.pdf')
      generated_pdf = constructor.construct(data, id: power_of_attorney.id)
      expect(generated_pdf).to match_pdf_content_of(expected_pdf)
    end

    it 'uses original page 2 signature coordinates' do
      signatures = constructor.send(:page2_signatures, data['signatures'])

      expect(signatures.map { |signature| [signature.x, signature.y] }).to eq([[35, 263], [35, 216]])
    end

    context 'when phone country codes are present on form' do
      let(:form_data_overrides) do
        {
          veteran: international_phone_form_data
        }
      end

      it 'constructs the pdf' do
        expected_pdf = Rails.root.join(
          'modules', 'claims_api', 'spec', 'fixtures', '21-22',
          'signed_filled_phone_country_codes.pdf'
        )
        generated_pdf = constructor.construct(data, id: power_of_attorney.id)
        expect(generated_pdf).to match_pdf_content_of(expected_pdf)
      end
    end
  end

  describe 'with lighthouse_claims_api_2122_pdf_form_update_v1 feature flag enabled' do
    let(:fixed_auth_headers) { ralph_auth_headers }

    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122_pdf_form_update_v1).and_return(true)
      Timecop.freeze(Time.zone.parse('2026-06-25T08:00:00Z'))
    end

    after do
      Timecop.return
    end

    it 'constructs pdf with the veteran information' do
      expected_pdf = Rails.root.join(
        'modules', 'claims_api', 'spec', 'fixtures', '21-22', 'v1_revised', 'revised_veteran_2122.pdf'
      )
      generated_pdf = constructor.construct(data, id: power_of_attorney.id)
      expect(generated_pdf).to match_pdf_content_of(expected_pdf)
    end

    it 'uses revised page 2 signature coordinates' do
      signatures = constructor.send(:page2_signatures, data['signatures'])

      expect(signatures.map { |signature| [signature.x, signature.y] }).to eq([[35, 328], [35, 281]])
    end

    it 'maps revised page 2 SSN and consent checkbox indexes correctly' do
      base_form = 'form1[0].#subform[1]'
      page2_options = constructor.send(:page2_options, data)

      expect(page2_options[:"#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]"]).to eq('796')
      expect(page2_options[:"#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]"]).to eq('37')
      expect(page2_options[:"#{base_form}.SocialSecurityNumber_LastFourNumbers[1]"]).to eq('8782')
      expect(page2_options[:"#{base_form}.I_Authorize[0]"]).to eq(1)
      expect(page2_options[:"#{base_form}.I_Authorize[1]"]).to eq(1)
      expect(page2_options).not_to have_key(:"#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]")
    end

    it 'uses revised date field names' do
      page1_base_form = 'form1[0].#subform[0]'
      page2_base_form = 'form1[0].#subform[1]'
      page1_options = constructor.send(:page1_options, data)
      page2_options = constructor.send(:page2_options, data)

      expect(page1_options[:"#{page1_base_form}.DateAppt[0]"]).to eq('06/25/2026')
      expect(page2_options[:"#{page2_base_form}.DateSigned[0]"]).to eq('06/25/2026')
      expect(page2_options[:"#{page2_base_form}.DateSigned[1]"]).to eq('06/25/2026')
      expect(page2_options).not_to have_key(:"#{page2_base_form}.Date_Signed[0]")
    end

    it 'uses revised phone and email field names' do
      base_form = 'form1[0].#subform[0]'
      page1_options = constructor.send(:page1_options, data)

      expect(page1_options[:"#{base_form}.Phone[0]"]).to eq('555 5551337')
      expect(page1_options[:"#{base_form}.EmailAddress_Optional[0]"]).to eq('veteran@nonsensedomain.org')
      expect(page1_options).not_to have_key(:"#{base_form}.TelephoneNumber_IncludeAreaCode[1]")
    end

    context 'when phone country codes are present on form' do
      let(:form_data_overrides) do
        {
          veteran: international_phone_form_data
        }
      end

      it 'maps revised veteran phone with country code into Phone[0]' do
        base_form = 'form1[0].#subform[0]'
        page1_options = constructor.send(:page1_options, data)

        expect(page1_options[:"#{base_form}.Phone[0]"]).to eq('+1 555 5551337')
      end

      it 'constructs the pdf' do
        expected_pdf = Rails.root.join(
          'modules', 'claims_api', 'spec', 'fixtures', '21-22', 'v1_revised',
          'revised_phone_country_codes.pdf'
        )
        generated_pdf = constructor.construct(data, id: power_of_attorney.id)
        expect(generated_pdf).to match_pdf_content_of(expected_pdf)
      end
    end

    context 'when claimant information is present on form' do
      let(:base_form_data) { veteran_form_data.deep_merge(claimant_form_data) }

      it 'maps claimant date of birth fields on the revised form' do
        base_form = 'form1[0].#subform[0]'
        page1_options = constructor.send(:page1_options, data)

        expect(page1_options[:"#{base_form}.DOBmonth[1]"]).to eq('01')
        expect(page1_options[:"#{base_form}.DOBday[1]"]).to eq('01')
        expect(page1_options[:"#{base_form}.DOByear[1]"]).to eq('1980')
      end

      it 'maps claimant contact and zip last four fields on the revised form' do
        base_form = 'form1[0].#subform[0]'
        page1_options = constructor.send(:page1_options, data)

        expect(page1_options[:"#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]"]).to eq('5678')
        expect(page1_options[:"#{base_form}.Phone[1]"]).to eq('+1 541 5551234')
        expect(page1_options[:"#{base_form}.EmailAddress_Optional[1]"]).to eq('claimant@example.com')
      end

      it 'constructs the pdf with the claimant information' do
        expected_pdf = Rails.root.join(
          'modules', 'claims_api', 'spec', 'fixtures', '21-22', 'v1_revised', 'revised_claimant_2122.pdf'
        )
        generated_pdf = constructor.construct(data, id: power_of_attorney.id)
        expect(generated_pdf).to match_pdf_content_of(expected_pdf)
      end
    end

    context 'when veteran birthdate is missing' do
      # NOTE: Without safe navigation (&.), the original (flag-disabled) form path would raise
      # NoMethodError here. That path has been patched and will be removed once this flag is fully live.
      it 'does not raise and returns nil for DOB fields' do
        data_without_birthdate = data.deep_merge('veteran' => { 'birthdate' => nil })
        base_form = 'form1[0].#subform[0]'

        result = nil
        expect { result = constructor.send(:page1_options, data_without_birthdate) }.not_to raise_error
        expect(result[:"#{base_form}.DOBmonth[0]"]).to be_nil
        expect(result[:"#{base_form}.DOBday[0]"]).to be_nil
        expect(result[:"#{base_form}.DOByear[0]"]).to be_nil
      end
    end

    context 'when service organization representative name is partial or missing' do
      let(:base_form) { 'form1[0].#subform[0]' }
      let(:rep_name_field) { :"#{base_form}.Name_Of_Official_Representative[0]" }

      { 'nil' => nil, 'an empty string' => '' }.each do |label, blank|
        context "when name fields are #{label}" do
          it 'omits a blank firstName without a leading space' do
            options = constructor.send(
              :page1_options, data.deep_merge('serviceOrganization' => { 'firstName' => blank })
            )
            expect(options[rep_name_field]).to eq('Sikorsky')
          end

          it 'omits a blank lastName without a trailing space' do
            options = constructor.send(
              :page1_options, data.deep_merge('serviceOrganization' => { 'lastName' => blank })
            )
            expect(options[rep_name_field]).to eq('Igor')
          end

          it 'returns an empty string when both name fields are blank' do
            options = constructor.send(
              :page1_options, data.deep_merge('serviceOrganization' => { 'firstName' => blank, 'lastName' => blank })
            )
            expect(options[rep_name_field]).to eq('')
          end
        end
      end
    end
  end
end
