# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SurvivorsBenefits::SavedClaim do
  subject { described_class.new }

  let(:instance) { build(:survivors_benefits_claim) }

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
      expect(subject.business_line).to eq('NCA')
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
    expect(subject.form_id).to eq(SurvivorsBenefits::FORM_ID)
    expect(subject.guid).not_to be_nil
    expect(subject.type).to eq(SurvivorsBenefits::SavedClaim.to_s)
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

    context 'when a custodian is filing for a child under 18' do
      let(:claim) { create(:survivors_benefits_claim, :with_custodian) }
      let(:base_pdf_path) { 'tmp/pdfs/base.pdf' }
      let(:statement_pdf_path) { 'tmp/pdfs/statement.pdf' }
      let(:combined_path) { "tmp/pdfs/#{SurvivorsBenefits::FORM_ID}_#{claim.guid}_combined.pdf" }

      before do
        allow(PdfFill::Filler).to receive_messages(fill_form: base_pdf_path,
                                                   fill_ancillary_form: statement_pdf_path,
                                                   merge_pdfs: nil)
        allow(SurvivorsBenefits::PdfFill::Va21p534ez).to receive(:stamp_signature).and_return(combined_path)
      end

      it 'attaches a 21-4138 addendum even without a CaveSubmission' do
        expect(PdfFill::Filler).to receive(:merge_pdfs).with(base_pdf_path, statement_pdf_path, combined_path)

        expect(claim.to_pdf).to eq(combined_path)
      end

      it 'writes the custodian details into the 21-4138 remarks' do
        expect(PdfFill::Filler).to receive(:fill_ancillary_form) do |form_data, claim_id, form_id, options|
          expect(claim_id).to eq(claim.id)
          expect(form_id).to eq('21-4138')
          expect(options).to eq({ extras_redesign: true })
          expect(form_data[:remarks]).to eq(
            <<~REMARKS.chomp
              ALTERNATE SIGNER (CUSTODIAN) INFORMATION
              Custodian name: Jane Q Custodian
              Relationship to child: Mother
              Custodian address: 123 Main St Apt 4B, Springfield IL 62704, USA
              Custodian email: jane.custodian@example.com
            REMARKS
          )
          statement_pdf_path
        end

        claim.to_pdf
      end

      it 'puts the custodian block ahead of the CAVE change log when both apply' do
        CaveSubmission.create!(saved_claim: claim, cave_response: { 'VETERAN_NAME' => 'JOHN E DOE' }.to_json)

        expect(PdfFill::Filler).to receive(:fill_ancillary_form) do |form_data, *|
          expect(form_data[:remarks]).to start_with("ALTERNATE SIGNER (CUSTODIAN) INFORMATION\n")
          expect(form_data[:remarks]).to include("\n\nSYSTEM GENERATED TO DOCUMENT USER CHANGES\n")
          expect(form_data[:remarks]).to include('Veteran name: OCR Extracted Value: JOHN E DOE;')
          statement_pdf_path
        end

        claim.to_pdf
      end
    end

    context 'when no custodian is filing and there is no CaveSubmission' do
      let(:claim) { create(:survivors_benefits_claim) }

      before do
        allow(PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/base.pdf')
        allow(SurvivorsBenefits::PdfFill::Va21p534ez).to receive(:stamp_signature).and_return('tmp/pdfs/base.pdf')
      end

      it 'does not attach a 21-4138 addendum' do
        expect(PdfFill::Filler).not_to receive(:fill_ancillary_form)
        expect(PdfFill::Filler).not_to receive(:merge_pdfs)

        expect(claim.to_pdf).to eq('tmp/pdfs/base.pdf')
      end
    end
  end

  describe '#send_email' do
    it 'calls SurvivorsBenefits::NotificationEmail with the claim id and delivers the email' do
      claim = build(:survivors_benefits_claim)
      email_type = :error
      notification_double = instance_double(SurvivorsBenefits::NotificationEmail)

      expect(SurvivorsBenefits::NotificationEmail).to receive(:new).with(claim.id).and_return(notification_double)
      expect(notification_double).to receive(:deliver).with(email_type)

      claim.send_email(email_type)
    end
  end

  describe '#to_ibm' do
    context 'when the 2025 flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      it 'uses V2022::StructuredDataService' do
        expect(SurvivorsBenefits::StructuredData::V2022::StructuredDataService)
          .to receive(:new).with(instance.parsed_form).and_call_original
        instance.to_ibm
      end
    end

    context 'when the 2025 flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_form_2025_version_enabled).and_return(true)
      end

      it 'uses V2025::StructuredDataService' do
        expect(SurvivorsBenefits::StructuredData::V2025::StructuredDataService)
          .to receive(:new).with(instance.parsed_form).and_call_original
        instance.to_ibm
      end
    end

    context 'when building structured data raises an error' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      it 'logs an error and returns nil' do
        allow(SurvivorsBenefits::StructuredData::V2022::StructuredDataService)
          .to receive(:new).and_raise(StandardError.new('Structured data error'))
        expect(Rails.logger).to receive(:error)
          .with('Error building structured data for IBM submission: Structured data error')

        expect(instance.to_ibm).to be_nil
      end
    end
  end
end
