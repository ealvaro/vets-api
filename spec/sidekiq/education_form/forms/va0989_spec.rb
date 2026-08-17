# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EducationForm::Forms::VA0989 do
  subject { described_class.new(application) }

  let(:application) { create(:va0989).education_benefits_claim }

  it 'exposes the header form type' do
    expect(subject.header_form_type).to eq('V0989')
  end

  it 'hardcodes the benefit type for the spool header' do
    expect(subject.benefit_type).to eq('CH33')
  end

  it 'uses applicant name and identifier for the spool header' do
    expect(subject.applicant_name.first).to eq('John')
    expect(subject.applicant_ssn).to eq('123456789')
  end

  it 'formats closed school information' do
    expected = <<~SCHOOL.strip
      Test U
      111 2ND ST S
      UNIT B
      SECTION ALPHA
      SEATTLE, WA, 98101
      USA
    SCHOOL

    expect(subject.closed_school_name_and_address).to eq(expected)
  end

  it 'formats new school and program information' do
    expect(subject.new_school_and_program_name).to eq("New School\nPhysics 2.0")
  end

  describe 'conditional field formatting' do
    let(:application) { create(:va0989_not_closed).education_benefits_claim }

    it 'marks school-closure follow-up fields as not applicable' do
      expect(subject.closed_school_name_and_address).to eq('N/A')
      expect(subject.conditional_yesno(nil, visible: subject.school_closed_questions_visible?)).to eq('N/A')
      expect(subject.attestation_signature).to eq('N/A')
    end
  end

  describe 'optional field formatting' do
    let(:application) { create(:va0989_optional_blanks).education_benefits_claim }

    it 'marks optional blank fields as unanswered' do
      expect(subject.home_phone).to eq('U/A')
      expect(subject.mobile_phone).to eq('U/A')
      expect(subject.remarks).to eq('U/A')
    end
  end

  %w[minimal not_closed partial_branches optional_blanks].each do |form|
    test_spool_file('0989', form)
  end
end
