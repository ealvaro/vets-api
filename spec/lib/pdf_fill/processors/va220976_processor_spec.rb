# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/processors/va220976_processor'
require 'pdf_fill/filler'

describe PdfFill::Processors::VA220976Processor do
  let(:form_data) { saved_claim.parsed_form }
  let(:filler) { PdfFill::Filler }
  let(:processor) { described_class.new(form_data, filler, 'abc') }

  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  def get_field_value(fields, name)
    fields.find { |f| f.name == name }&.value
  end

  describe '#process' do
    # happy path - all initials present, no overflow, is financially sound was selected yes on the form
    context 'when the content does not overflow' do
      let(:saved_claim) { create(:va0976) } # uses spec/fixtures/education_benefits_claims/0976/minimal.json

      it 'creates the pdf correctly' do
        processor.process
        expect(File.exist?('tmp/pdfs/22-0976_abc.pdf')).to be(true)
      end

      it 'fills in the form fields' do
        processor.process
        fields = PdfForms.new(Settings.binaries.pdftk).get_fields('tmp/pdfs/22-0976_abc.pdf')

        expect(get_field_value(fields, 'submission_type_initial')).to eq 'Yes'
        expect(get_field_value(fields, 'institution_name')).to eq 'Test University'
        expect(get_field_value(fields, 'institution_facility_code')).to eq '12345678'
        expect(get_field_value(fields, 'degree_program_0_name')).to eq 'Physics'
        expect(get_field_value(fields, 'authorizing_initials_1')).to eq 'JH'
        expect(get_field_value(fields, 'is_financially_sound')).to eq 'YES'
        expect(get_field_value(fields, 'faculty_0_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'sco_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'institution_mailing_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'institution_physical_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'authorizing_official_signature')).to eq 'John Doe'
      end
    end

    # Is financially sound was selected no on the form, initials present
    context 'when the financially_sound is false' do
      let(:saved_claim) { create(:va0976_no) }

      it 'creates the pdf correctly' do
        processor.process
        expect(File.exist?('tmp/pdfs/22-0976_abc.pdf')).to be(true)
      end

      it 'fills in the form fields' do
        processor.process
        fields = PdfForms.new(Settings.binaries.pdftk).get_fields('tmp/pdfs/22-0976_abc.pdf')
        expect(get_field_value(fields, 'submission_type_initial')).to eq 'Yes'
        expect(get_field_value(fields, 'institution_name')).to eq 'Test University'
        expect(get_field_value(fields, 'institution_facility_code')).to eq '12345678'
        expect(get_field_value(fields, 'degree_program_0_name')).to eq 'Physics'
        expect(get_field_value(fields, 'authorizing_initials_1')).to eq 'JH'
        expect(get_field_value(fields, 'is_financially_sound')).to eq 'NO'
        expect(get_field_value(fields, 'financially_sound_description')).to eq 'Fraud investigation pending'
        expect(get_field_value(fields, 'faculty_0_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'sco_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'institution_mailing_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'institution_physical_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'authorizing_official_signature')).to eq 'John Doe'
      end
    end

    context 'when the content has no acknowledgement details (intitials and others)' do
      let(:saved_claim) { create(:va0976_no_acknowledgement) }

      # We need this test because the pdf generation was blowing up until code was fixed
      it 'creates the pdf correctly' do
        processor.process
        expect(File.exist?('tmp/pdfs/22-0976_abc.pdf')).to be(true)
      end

      it 'fills in the form fields' do
        processor.process
        fields = PdfForms.new(Settings.binaries.pdftk).get_fields('tmp/pdfs/22-0976_abc.pdf')
        expect(get_field_value(fields, 'submission_type_initial')).to eq 'Yes'
        expect(get_field_value(fields, 'institution_name')).to eq 'Test University'
        expect(get_field_value(fields, 'institution_facility_code')).to eq '12345678'
        expect(get_field_value(fields, 'degree_program_0_name')).to eq 'Physics'
        expect(get_field_value(fields, 'authorizing_initials_1')).to be_nil
        expect(get_field_value(fields, 'authorizing_initials_2')).to be_nil
        expect(get_field_value(fields, 'authorizing_initials_3')).to be_nil
        expect(get_field_value(fields, 'authorizing_initials_4')).to be_nil
        expect(get_field_value(fields, 'is_financially_sound')).to eq ''
        expect(get_field_value(fields, 'financially_sound_description')).to be_nil
        expect(get_field_value(fields, 'faculty_0_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'sco_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'institution_mailing_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'institution_physical_address')).to eq '123 Main St, Anytown, CA, 12345, USA'
        expect(get_field_value(fields, 'authorizing_official_signature')).to eq 'John Doe'
      end
    end

    context 'when the content does overflow' do
      let(:saved_claim) { create(:va0976_overflow) }

      it 'creates the pdf correctly' do
        processor.process
        expect(File.exist?('tmp/pdfs/22-0976_abc_final.pdf')).to be(true)
      end

      it 'fills in the form fields' do
        processor.process
        fields = PdfForms.new(Settings.binaries.pdftk).get_fields('tmp/pdfs/22-0976_abc_final.pdf')
        expect(get_field_value(fields, 'submission_type_initial')).to eq 'Yes'
        expect(get_field_value(fields, 'institution_name')).to eq 'Test University'
        expect(get_field_value(fields, 'institution_facility_code')).to eq '12345678'
        expect(get_field_value(fields, 'degree_program_0_name')).to eq 'Physics'
        expect(get_field_value(fields, 'authorizing_initials_1')).to eq 'JH'
        expect(get_field_value(fields, 'faculty_0_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'sco_name')).to eq 'John A Doe'
        expect(get_field_value(fields, 'authorizing_official_signature')).to eq 'John Doe'

        # 'Business Administration' (program index 3) has entryRequirements text longer than
        # ENTRY_REQUIREMENTS_CHAR_LIMIT, so it's extracted in full to the overflow page
        expect(get_field_value(fields, 'degree_program_3_name')).to eq 'See Additional Page'
        expect(get_field_value(fields, 'degree_program_3_entry_requirements')).to be_nil
        expect(get_field_value(fields, 'branch_3_name')).to eq 'Branch 4'
        expect(get_field_value(fields, 'faculty_6_name')).to eq 'John A Doe6'
      end
    end

    context 'when a program has entry requirements text that overflows the pdf field' do
      let(:saved_claim) { create(:va0976) }
      let(:long_entry_requirements) { 'A' * (described_class::ENTRY_REQUIREMENTS_CHAR_LIMIT + 1) }

      before do
        form_data['programs'][0]['entryRequirements'] = long_entry_requirements
      end

      it 'creates a combined pdf with an overflow page' do
        processor.process
        expect(File.exist?('tmp/pdfs/22-0976_abc_final.pdf')).to be(true)
      end

      it 'replaces the program name with See Additional Page and moves the full program to the overflow page' do
        processor.process
        fields = PdfForms.new(Settings.binaries.pdftk).get_fields('tmp/pdfs/22-0976_abc_final.pdf')

        expect(get_field_value(fields, 'degree_program_0_name')).to eq 'See Additional Page'
        expect(get_field_value(fields, 'degree_program_0_entry_requirements')).to be_nil
        expect(get_field_value(fields, 'degree_program_0_length')).to be_nil
        expect(get_field_value(fields, 'degree_program_0_weeks_per_term')).to be_nil
        expect(get_field_value(fields, 'degree_program_0_credit_hours')).to be_nil
      end
    end
  end
end
