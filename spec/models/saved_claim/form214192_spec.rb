# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::Form214192, type: :model do
  let(:valid_form_data) { JSON.parse(Rails.root.join('spec', 'fixtures', 'form214192', 'valid_form.json').read) }
  let(:invalid_form_data) do
    JSON.parse(Rails.root.join('spec', 'fixtures', 'form214192', 'invalid_form.json').read)
  end

  let(:claim) { described_class.new(form: valid_form_data.to_json) }

  describe 'validations' do
    let(:claim) { described_class.new(form: form.to_json) }
    let(:form) { valid_form_data.dup }

    context 'with valid form data' do
      it 'validates successfully' do
        claim = described_class.new(form: valid_form_data.to_json)
        expect(claim).to be_valid
      end
    end

    context 'with invalid form data from fixture' do
      it 'fails validation for multiple reasons' do
        claim = described_class.new(form: invalid_form_data.to_json)
        expect(claim).not_to be_valid
        # Should fail because:
        # - middle name exceeds maxLength of 1
        # - missing SSN or VA file number
        # - missing required employment fields
      end
    end

    context 'OpenAPI schema validation' do
      it 'rejects middle name longer than 1 character' do
        form['veteranInformation']['fullName']['middle'] = 'AB'
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 1')
      end

      it 'rejects first name longer than 12 characters' do
        form['veteranInformation']['fullName']['first'] = 'A' * 31
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 30')
      end

      it 'rejects last name longer than 18 characters' do
        form['veteranInformation']['fullName']['last'] = 'A' * 31
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 30')
      end

      it 'rejects invalid SSN format' do
        form['veteranInformation']['ssn'] = '12345' # Too short
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('pattern')
      end

      it 'rejects address street exceeding maxLength' do
        form['veteranInformation']['address']['street'] = 'A' * 31 # Max is 30
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 30')
      end

      it 'accepts veteran address street2 up to 30 characters' do
        form['veteranInformation']['address']['street2'] = 'A' * 30
        expect(claim).to be_valid
      end

      it 'rejects veteran address street2 longer than 30 characters' do
        form['veteranInformation']['address']['street2'] = 'A' * 31
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 30')
      end

      it 'accepts employer address street2 up to 30 characters' do
        form['employmentInformation']['employerAddress']['street2'] = 'A' * 30
        expect(claim).to be_valid
      end

      it 'rejects employer address street2 longer than 30 characters' do
        form['employmentInformation']['employerAddress']['street2'] = 'A' * 31
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('string length')
        expect(claim.errors.full_messages.join).to include('is greater than: 30')
      end

      it 'requires country field in address' do
        form['veteranInformation']['address'].delete('country')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires veteran information' do
        form.delete('veteranInformation')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires employment information' do
        form.delete('employmentInformation')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires veteran full name' do
        form['veteranInformation'].delete('fullName')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires veteran date of birth' do
        form['veteranInformation'].delete('dateOfBirth')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires employer name' do
        form['employmentInformation'].delete('employerName')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires employer address' do
        form['employmentInformation'].delete('employerAddress')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires type of work performed' do
        form['employmentInformation'].delete('typeOfWorkPerformed')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      it 'requires beginning date of employment' do
        form['employmentInformation'].delete('beginningDateOfEmployment')
        expect(claim).not_to be_valid
        expect(claim.errors.full_messages.join).to include('missing required properties')
      end

      # New validation rules added in schema alignment
      context 'SSN or VA file number validation (anyOf)' do
        it 'accepts form with only SSN' do
          form['veteranInformation'].delete('vaFileNumber')
          expect(claim).to be_valid
        end

        it 'accepts form with only VA file number' do
          form['veteranInformation'].delete('ssn')
          expect(claim).to be_valid
        end

        it 'accepts form with both SSN and VA file number' do
          # Default fixture has both
          expect(claim).to be_valid
        end

        it 'rejects form with neither SSN nor VA file number' do
          form['veteranInformation'].delete('ssn')
          form['veteranInformation'].delete('vaFileNumber')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end
      end

      context 'militaryDutyStatus validation' do
        it 'accepts form without militaryDutyStatus (optional at top level)' do
          form.delete('militaryDutyStatus')
          expect(claim).to be_valid
        end

        it 'requires currentDutyStatus within militaryDutyStatus' do
          form['militaryDutyStatus'].delete('currentDutyStatus')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'requires veteranDisabilitiesPreventMilitaryDuties' do
          form['militaryDutyStatus'].delete('veteranDisabilitiesPreventMilitaryDuties')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'accepts valid militaryDutyStatus with all required fields' do
          form['militaryDutyStatus'] = {
            'currentDutyStatus' => 'Active Duty',
            'veteranDisabilitiesPreventMilitaryDuties' => false
          }
          expect(claim).to be_valid
        end
      end

      context 'employmentInformation required fields' do
        it 'requires concessions' do
          form['employmentInformation'].delete('concessions')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'requires timeLostLast12MonthsOfEmployment' do
          form['employmentInformation'].delete('timeLostLast12MonthsOfEmployment')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'requires amountEarnedLast12MonthsOfEmployment' do
          form['employmentInformation'].delete('amountEarnedLast12MonthsOfEmployment')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'requires hoursWorkedDaily' do
          form['employmentInformation'].delete('hoursWorkedDaily')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end

        it 'requires hoursWorkedWeekly' do
          form['employmentInformation'].delete('hoursWorkedWeekly')
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('missing required properties')
        end
      end

      context 'numeric field validation (minimum/maximum)' do
        it 'accepts amountEarnedLast12MonthsOfEmployment at minimum (0)' do
          form['employmentInformation']['amountEarnedLast12MonthsOfEmployment'] = 0
          expect(claim).to be_valid
        end

        it 'accepts amountEarnedLast12MonthsOfEmployment at maximum (999999999)' do
          form['employmentInformation']['amountEarnedLast12MonthsOfEmployment'] = 999_999_999
          expect(claim).to be_valid
        end

        it 'rejects negative amountEarnedLast12MonthsOfEmployment' do
          form['employmentInformation']['amountEarnedLast12MonthsOfEmployment'] = -1
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to match(/minimum|less than/)
        end

        it 'rejects amountEarnedLast12MonthsOfEmployment exceeding maximum' do
          form['employmentInformation']['amountEarnedLast12MonthsOfEmployment'] = 1_000_000_000
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to match(/maximum|greater than/)
        end

        it 'accepts hoursWorkedDaily at minimum (0)' do
          form['employmentInformation']['hoursWorkedDaily'] = 0
          expect(claim).to be_valid
        end

        it 'rejects negative hoursWorkedDaily' do
          form['employmentInformation']['hoursWorkedDaily'] = -1
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to match(/minimum|less than/)
        end

        it 'accepts hoursWorkedWeekly at minimum (0)' do
          form['employmentInformation']['hoursWorkedWeekly'] = 0
          expect(claim).to be_valid
        end

        it 'rejects negative hoursWorkedWeekly' do
          form['employmentInformation']['hoursWorkedWeekly'] = -1
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to match(/minimum|less than/)
        end

        it 'accepts grossMonthlyAmountOfBenefit within valid range' do
          form['benefitEntitlementPayments'] = {
            'sickRetirementOtherBenefits' => true,
            'typeOfBenefit' => 'Retirement',
            'grossMonthlyAmountOfBenefit' => 5000,
            'dateBenefitBegan' => '2020-01-01',
            'dateFirstPaymentIssued' => '2020-02-01'
          }
          expect(claim).to be_valid
        end

        it 'rejects negative grossMonthlyAmountOfBenefit' do
          form['benefitEntitlementPayments'] = {
            'sickRetirementOtherBenefits' => true,
            'typeOfBenefit' => 'Retirement',
            'grossMonthlyAmountOfBenefit' => -100,
            'dateBenefitBegan' => '2020-01-01',
            'dateFirstPaymentIssued' => '2020-02-01'
          }
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to match(/minimum|less than/)
        end
      end

      context 'string maxLength validation' do
        it 'accepts employerName at maxLength (100)' do
          form['employmentInformation']['employerName'] = 'A' * 100
          expect(claim).to be_valid
        end

        it 'rejects employerName exceeding maxLength (100)' do
          form['employmentInformation']['employerName'] = 'A' * 101
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('string length')
          expect(claim.errors.full_messages.join).to include('is greater than: 100')
        end

        it 'accepts typeOfWorkPerformed at maxLength (1000)' do
          form['employmentInformation']['typeOfWorkPerformed'] = 'A' * 1000
          expect(claim).to be_valid
        end

        it 'rejects typeOfWorkPerformed exceeding maxLength (1000)' do
          form['employmentInformation']['typeOfWorkPerformed'] = 'A' * 1001
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('string length')
          expect(claim.errors.full_messages.join).to include('is greater than: 1000')
        end

        it 'accepts currentDutyStatus at maxLength (500)' do
          form['militaryDutyStatus']['currentDutyStatus'] = 'A' * 500
          expect(claim).to be_valid
        end

        it 'rejects currentDutyStatus exceeding maxLength (500)' do
          form['militaryDutyStatus']['currentDutyStatus'] = 'A' * 501
          expect(claim).not_to be_valid
          expect(claim.errors.full_messages.join).to include('string length')
          expect(claim.errors.full_messages.join).to include('is greater than: 500')
        end
      end
    end
  end

  describe '#send_confirmation_email' do
    it 'does not send email (MVP does not include email)' do
      expect(VANotify::EmailJob).not_to receive(:perform_async)
      claim.send_confirmation_email
    end
  end

  describe '#business_line' do
    it 'returns CMP for compensation claims' do
      expect(claim.business_line).to eq('CMP')
    end
  end

  describe '#document_type' do
    it 'returns 119 for employment information' do
      expect(claim.document_type).to eq(119)
    end
  end

  describe '#regional_office' do
    it 'returns empty array' do
      expect(claim.regional_office).to eq([])
    end
  end

  describe '#process_attachments!' do
    it 'queues Lighthouse submission job without attachments' do
      expect(Lighthouse::SubmitBenefitsIntakeClaim).to receive(:perform_async).with(claim.id)
      claim.process_attachments!
    end
  end

  describe '#attachment_keys' do
    it 'returns empty array (no attachments in MVP)' do
      expect(claim.attachment_keys).to eq([])
    end
  end

  describe '#to_pdf' do
    let(:pdf_path) { '/tmp/test_form.pdf' }
    let(:stamped_pdf_path) { '/tmp/test_form_stamped.pdf' }

    before do
      allow(PdfFill::Filler).to receive(:fill_form).and_return(pdf_path)
      allow(PdfFill::Forms::Va214192).to receive(:stamp_signature).and_return(stamped_pdf_path)
    end

    it 'generates PDF and stamps the signature' do
      result = claim.to_pdf

      expect(PdfFill::Filler).to have_received(:fill_form).with(claim, nil, {})
      expect(PdfFill::Forms::Va214192).to have_received(:stamp_signature).with(pdf_path, claim.parsed_form)
      expect(result).to eq(stamped_pdf_path)
    end

    it 'passes fill_options to the filler' do
      fill_options = { extras_redesign: true }
      claim.to_pdf('test-id', fill_options)

      expect(PdfFill::Filler).to have_received(:fill_form).with(claim, 'test-id', fill_options)
    end
  end

  describe '#metadata_for_benefits_intake' do
    context 'with all fields present' do
      it 'returns correct metadata hash' do
        metadata = claim.metadata_for_benefits_intake

        expect(metadata).to eq(
          veteranFirstName: 'John',
          veteranLastName: 'Doe',
          fileNumber: '987654321',
          zipCode: '54321',
          businessLine: 'CMP',
          docType: 'StructuredData:21-4192'
        )
      end
    end

    context 'when vaFileNumber is present' do
      it 'prefers vaFileNumber over ssn' do
        form_data = valid_form_data.dup
        form_data['veteranInformation']['vaFileNumber'] = '12345678'
        form_data['veteranInformation']['ssn'] = '999999999'
        claim_with_both = described_class.new(form: form_data.to_json)

        metadata = claim_with_both.metadata_for_benefits_intake

        expect(metadata[:fileNumber]).to eq('12345678')
      end
    end

    context 'when vaFileNumber is missing' do
      it 'falls back to ssn' do
        form_data = valid_form_data.dup
        form_data['veteranInformation'].delete('vaFileNumber')
        form_data['veteranInformation']['ssn'] = '111223333'
        claim_without_va_file = described_class.new(form: form_data.to_json)

        metadata = claim_without_va_file.metadata_for_benefits_intake

        expect(metadata[:fileNumber]).to eq('111223333')
      end
    end

    context 'when zipCode is missing' do
      it 'defaults to 00000 when employerAddress postalCode is missing' do
        form_data = valid_form_data.dup
        form_data['employmentInformation']['employerAddress'].delete('postalCode')
        claim_without_zip = described_class.new(form: form_data.to_json)

        metadata = claim_without_zip.metadata_for_benefits_intake

        expect(metadata[:zipCode]).to eq('00000')
      end

      it 'defaults to 00000 when employerAddress is missing' do
        form_data = valid_form_data.dup
        form_data['employmentInformation'].delete('employerAddress')
        claim_without_address = described_class.new(form: form_data.to_json)

        metadata = claim_without_address.metadata_for_benefits_intake

        expect(metadata[:zipCode]).to eq('00000')
      end
    end

    it 'always includes businessLine from business_line method' do
      metadata = claim.metadata_for_benefits_intake

      expect(metadata[:businessLine]).to eq('CMP')
      expect(metadata[:businessLine]).to eq(claim.business_line)
    end
  end

  describe '#to_ibm' do
    let(:claim) { described_class.new(form: valid_form_data.to_json) }
    let(:ibm_payload) { claim.to_ibm }

    it 'returns a hash with exactly 3 VBA Data Dictionary fields' do
      expect(ibm_payload).to be_a(Hash)
      expect(ibm_payload.keys.length).to eq(3)
    end

    it 'includes employer name and address combined field' do
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS']).to include('Acme Corporation')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS']).to include('456 Business Ave')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS']).to include('Commerce City, CA')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS']).to include('54321')
    end

    it 'includes form metadata' do
      expect(ibm_payload).to include(
        'FORM_TYPE' => 'VA FORM 21-4192, AUG 2024',
        'FORM_TYPE_1' => 'VA FORM 21-4192, AUG 2024'
      )
    end

    it 'handles missing employer address street2' do
      form_data = valid_form_data.dup
      form_data['employmentInformation']['employerAddress'].delete('street2')
      claim = described_class.new(form: form_data.to_json)
      payload = claim.to_ibm

      expect(payload['EMPLOYER_NAME_ADDRESS']).to include('Acme Corporation')
      expect(payload['EMPLOYER_NAME_ADDRESS']).not_to include('200')
    end
  end

  describe 'FORM constant' do
    it 'is set to 21-4192' do
      expect(described_class::FORM).to eq('21-4192')
    end
  end
end
