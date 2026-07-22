# frozen_string_literal: true

require 'rails_helper'
require 'common/file_helpers'
require 'pdf/reader'

RSpec.describe MedicalExpenseReports::SavedClaim do
  subject { described_class.new }

  let(:instance) { build(:medical_expense_reports_claim) }

  it 'responds to #confirmation_number' do
    expect(subject.confirmation_number).to eq(subject.guid)
  end

  it 'has necessary constants' do
    expect(described_class).to have_constant(:FORM)
  end

  it 'descends from saved_claim' do
    expect(described_class.ancestors).to include(SavedClaim)
  end

  describe '#email' do
    it 'returns the users email' do
      expect(instance.email).to eq('test@example.com')
    end
  end

  describe '#business_line' do
    it 'returns the correct business line' do
      expect(subject.business_line).to eq('VBA')
    end
  end

  describe '#veteran_first_name' do
    it 'returns the first name of the veteran from parsed_form' do
      allow(instance).to receive(:parsed_form).and_return({ 'veteranFullName' => { 'first' => 'John' } })
      expect(instance.veteran_first_name).to eq('John')
    end

    it 'returns nil if the key does not exist' do
      allow(instance).to receive(:parsed_form).and_return({})
      expect(instance.veteran_first_name).to be_nil
    end
  end

  describe '#veteran_last_name' do
    it 'returns the last name of the veteran from parsed_form' do
      allow(instance).to receive(:parsed_form).and_return({ 'veteranFullName' => { 'last' => 'Doe' } })
      expect(instance.veteran_last_name).to eq('Doe')
    end

    it 'returns nil if the key does not exist' do
      allow(instance).to receive(:parsed_form).and_return({})
      expect(instance.veteran_last_name).to be_nil
    end
  end

  describe '#claimant_first_name' do
    it 'returns the first name of the claimant from parsed_form' do
      allow(instance).to receive(:parsed_form).and_return({ 'claimantFullName' => { 'first' => 'Derrick' } })
      expect(instance.claimant_first_name).to eq('Derrick')
    end

    it 'returns nil if the key does not exist' do
      allow(instance).to receive(:parsed_form).and_return({})
      expect(instance.claimant_first_name).to be_nil
    end
  end

  it 'inherits init callsbacks from saved_claim' do
    expect(subject.form_id).to eq(MedicalExpenseReports::FORM_ID)
    expect(subject.guid).not_to be_nil
    expect(subject.type).to eq(MedicalExpenseReports::SavedClaim.to_s)
  end

  describe '#process_attachments!' do
    it 'does NOT start a job to submit the saved claim via Benefits Intake' do
      expect(Lighthouse::SubmitBenefitsIntakeClaim).not_to receive(:perform_async)
      instance.process_attachments!
    end
  end

  describe '#to_pdf' do
    it 'calls PdfFill::Filler.fill_form' do
      expect(PdfFill::Filler).to receive(:fill_form).with(subject, nil, {})
      subject.to_pdf
    end

    [true, false].each do |extras_redesign|
      it "calls PdfFill::Filler.fill_form with extras_redesign: #{extras_redesign}" do
        expect(PdfFill::Filler).to receive(:fill_form).with(subject, nil, { extras_redesign: })
        subject.to_pdf(nil, { extras_redesign: })
      end
    end

    context 'when the claim has a cave_submission' do
      let(:claim) { create(:medical_expense_reports_claim) }
      let(:base_pdf_path) { 'tmp/pdfs/base.pdf' }
      let(:statement_pdf_path) { 'tmp/pdfs/statement.pdf' }
      let(:combined_path) { "tmp/pdfs/#{MedicalExpenseReports::FORM_ID}_#{claim.guid}_combined.pdf" }

      before do
        CaveSubmission.create!(saved_claim: claim, cave_response: { 'VETERAN_NAME' => 'JON A DOE' }.to_json)
        allow(PdfFill::Filler).to receive(:fill_form).and_return(base_pdf_path)
        allow(claim).to receive(:fill_ancillary_pdf).and_return(statement_pdf_path)
        allow(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_signature).and_return(combined_path)
      end

      # Guards the merge_pdfs call: its signature is (*file_paths, new_file_path), so passing a 4th
      # options hash (the original bug) bound new_file_path to the hash and pushed the real output
      # path into file_paths as a source, raising when merge tried to open the unwritten output.
      it 'merges the base and ancillary PDFs into the combined path with no extra arguments' do
        expect(PdfFill::Filler).to receive(:merge_pdfs).with(base_pdf_path, statement_pdf_path, combined_path)

        expect(claim.to_pdf).to eq(combined_path)
      end
    end
  end

  describe '#send_email' do
    it 'calls MedicalExpenseReports::NotificationEmail with the claim id and delivers the email' do
      claim = build(:medical_expense_reports_claim)
      email_type = :error
      notification_double = instance_double(MedicalExpenseReports::NotificationEmail)

      expect(MedicalExpenseReports::NotificationEmail).to receive(:new).with(claim.id).and_return(notification_double)
      expect(notification_double).to receive(:deliver).with(email_type)

      claim.send_email(email_type)
    end
  end

  describe '#to_ibm' do
    context 'when building structured data raises an error' do
      it 'logs an error and returns nil' do
        allow(instance).to receive(:build_ibm_payload).and_raise(StandardError.new('Structured data error'))
        expect(Rails.logger).to receive(:error)
          .with('Error building IBM payload: Structured data error', claim_id: instance.id)
        expect(instance.to_ibm).to be_nil
      end
    end
  end

  describe '#build_ibm_payload' do
    let(:base_form_data) do
      {
        'claimantFullName' => { 'first' => 'Jane', 'middle' => 'Q', 'last' => 'Public' },
        'claimantAddress' => {
          'street' => '100 Main St',
          'street2' => 'Apt 2',
          'city' => 'City',
          'state' => 'VA',
          'postalCode' => '22206',
          'country' => 'USA'
        },
        'claimantEmail' => 'claimant@example.com',
        'careExpenses' => [
          {
            'recipient' => 'VETERAN',
            'recipientName' => 'Vet Care',
            'provider' => 'Primary Care',
            'careDate' => { 'from' => '2023-01-01', 'to' => '2023-01-31' },
            'monthlyAmount' => '1000',
            'hourlyRate' => '25',
            'weeklyHours' => '30'
          },
          {
            'recipient' => 'CHILD',
            'recipientName' => 'Child Care',
            'provider' => 'Child Provider',
            'careDate' => { 'from' => '2023-02-01', 'to' => '2023-02-28' },
            'monthlyAmount' => '1200.5',
            'hourlyRate' => '30',
            'weeklyHours' => '20'
          }
        ],
        'primaryPhone' => { 'countryCode' => 'US', 'contact' => '(555) 123-4567' },
        'veteranFullName' => { 'first' => 'John', 'middle' => 'Q', 'last' => 'Public' },
        'veteranSocialSecurityNumber' => '123456789',
        'vaFileNumber' => '987654321',
        'veteranAddress' => {
          'street' => '1 Main Street',
          'street2' => 'A1',
          'city' => 'City',
          'state' => 'VA',
          'postalCode' => '22206',
          'country' => 'USA'
        },
        'statementOfTruthSignature' => 'Jane Public',
        'dateSigned' => '2024-04-01',
        'medicalExpenses' => [
          {
            'recipient' => 'SPOUSE',
            'recipientName' => 'Spouse Expense',
            'provider' => 'Medical Lab',
            'purpose' => 'Labs',
            'paymentDate' => '2024-02-02',
            'paymentFrequency' => 'ONCE_MONTH',
            'paymentAmount' => '123456.78'
          }
        ],
        'mileageExpenses' => [
          {
            'traveler' => 'CHILD',
            'travelerName' => 'Child Traveler',
            'travelLocation' => 'HOSPITAL',
            'travelLocationOther' => 'Child Clinic',
            'travelMilesTraveled' => '45',
            'travelDate' => '2024-03-03',
            'travelReimbursementAmount' => '12345.6'
          }
        ],
        'reportingPeriod' => { 'from' => '2024-01-01', 'to' => '2024-12-31' },
        'firstTimeReporting' => false
      }
    end

    let(:form_data) { base_form_data.deep_dup }

    it 'returns the IBM data dictionary mapping' do
      payload = instance.send(:build_ibm_payload, form_data)

      expect(payload).to include(
        'CLAIMANT_FIRST_NAME' => 'Jane',
        'CLAIMANT_LAST_NAME' => 'Public',
        'CLAIMANT_MIDDLE_INITIAL' => 'Q',
        'CLAIMANT_NAME' => 'Jane Q Public',
        'CLAIMANT_ADDRESS_FULL_BLOCK' => '100 Main St Apt 2 City VA 22206 USA',
        'CL_EMAIL' => 'claimant@example.com',
        'CL_PHONE_NUMBER' => '5551234567',
        'CL_INT_PHONE_NUMBER' => '',
        'DATE_SIGNED' => '04/01/2024',
        'FORM_TYPE' => MedicalExpenseReports::FORM_TYPE_LABEL,
        'MED_EXPENSES_FROM_1' => '01/01/2024',
        'MED_EXPENSES_TO_1' => '12/31/2024',
        'USE_VA_RCVD_DATE' => 0,
        'VA_FILE_NUMBER' => '987654321',
        'VETERAN_FIRST_NAME' => 'John',
        'VETERAN_LAST_NAME' => 'Public',
        'VETERAN_MIDDLE_INITIAL' => 'Q',
        'VETERAN_NAME' => 'John Q Public',
        'VETERAN_SSN' => '123456789',
        'CLAIMANT_SIGNATURE' => 'Jane Public',
        'IN_HM_VTRN_PAID_1' => 1,
        'IN_HM_CHLD_PAID_2' => 1,
        'IN_HM_CHLD_OTHR_NAME_2' => 'Child Care',
        'IN_HM_PROVIDER_NAME_2' => 'Child Provider',
        'IN_HM_DATE_START_2' => '02/01/2023',
        'IN_HM_AMT_PAID_2' => '1,200.50',
        'IN_HM_HRLY_RATE_2' => '30',
        'IN_HM_NBR_HRS_2' => '20',
        'MED_EXP_PAID_SPSE_1' => 1,
        'CB_PAYMENT_MONTHLY1' => 1,
        'MED_EXP_DATE_PAID_1' => '02/02/2024',
        'MED_EXP_AMT_PAID_1' => '123,456.78',
        'MED_EXP_PRVDR_NAME_1' => 'Medical Lab',
        'MED_EXPENSE_1' => 'Labs',
        'CHLD_RQD_TRVL_1' => 1,
        'MDCL_FCLTY_NAME_1' => 'Child Clinic',
        'TTL_MLS_TRVLD_1' => '45',
        'DATE_TRVLD_1' => '03/03/2024',
        'OTHER_SRC_RMBRSD_1' => '12,345.60',
        'TRVL_CHLD_OTHR_NAME_1' => 'Child Traveler'
      )
    end

    context 'without claimantAddress data' do
      let(:form_data) do
        base_form_data.deep_dup.tap { |form| form.delete('claimantAddress') }
      end

      it 'falls back to the veteran address' do
        payload = instance.send(:build_ibm_payload, form_data)

        expect(payload['CLAIMANT_ADDRESS_FULL_BLOCK']).to eq('1 Main Street A1 City VA 22206 USA')
      end
    end
  end

  describe '#to_stamped_pdf' do
    let(:claim) { create(:medical_expense_reports_claim) }
    let(:raw_path) { 'tmp/raw.pdf' }
    let(:stamped_path) { 'tmp/stamped.pdf' }

    it 'suppresses the built-in footers, stamps the watermark, and removes the intermediate PDF' do
      expect(claim).to receive(:to_pdf)
        .with('file-name', { extras_redesign: true, omit_esign_stamp: true, omit_footer: true })
        .and_return(raw_path)
      expect(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_submission_footer)
        .with(raw_path, claim.created_at, 3).and_return(stamped_path)
      allow(Common::FileHelpers).to receive(:delete_file_if_exists)

      expect(claim.to_stamped_pdf('file-name', loa: 3)).to eq(stamped_path)
      expect(Common::FileHelpers).to have_received(:delete_file_if_exists).with(raw_path)
    end

    it 'keeps the unstamped file when stamping fails open and returns the original path' do
      allow(claim).to receive(:to_pdf).and_return(raw_path)
      allow(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_submission_footer).and_return(raw_path)
      allow(Common::FileHelpers).to receive(:delete_file_if_exists)

      expect(claim.to_stamped_pdf(loa: 3)).to eq(raw_path)
      expect(Common::FileHelpers).not_to have_received(:delete_file_if_exists)
    end

    it 'renders the watermark exactly once on every page of the generated PDF' do
      path = claim.to_stamped_pdf(claim.guid, loa: 3)

      begin
        reader = PDF::Reader.new(path)
        reader.pages.each_with_index do |page, index|
          expect(page.text.scan('Signed electronically and submitted via VA.gov at').count)
            .to eq(1), "expected exactly one watermark timestamp line on page #{index + 1}"
          expect(page.text.scan('Signee signed with an identity-verified account.').count)
            .to eq(1), "expected exactly one watermark authentication line on page #{index + 1}"
        end
      ensure
        Common::FileHelpers.delete_file_if_exists(path)
      end
    end
  end
end
