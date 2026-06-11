# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/claim_behavior'
require 'dependents_benefits/monitor'

RSpec.describe DependentsBenefits::ClaimBehavior do
  let(:claim) { build(:dependents_claim).tap { |record| record.save!(validate: false) } }
  let(:child_claim) { build(:add_remove_dependents_claim).tap { |record| record.save!(validate: false) } }
  let(:student_claim) { build(:student_claim).tap { |record| record.save!(validate: false) } }

  let(:claim_group) { create(:parent_claim_group, parent_claim: claim) }

  let(:monitor_double) { instance_double(DependentsBenefits::Monitor) }

  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow(DependentsBenefits::Monitor).to receive(:new).and_return(monitor_double)
    allow(monitor_double).to receive(:track_error_event)
  end

  describe '#submissions_succeeded?' do
    it 'returns true when both BGS and Claims Evidence submissions succeeded' do
      allow(claim).to receive_messages(submitted_to_bgs?: true, submitted_to_claims_evidence_api?: true)

      expect(claim.submissions_succeeded?).to be true
    end

    it 'returns false when BGS submission failed or incomplete' do
      allow(claim).to receive_messages(submitted_to_bgs?: false, submitted_to_claims_evidence_api?: true)

      expect(claim.submissions_succeeded?).to be false
    end

    it 'returns false when Claims Evidence submission failed or incomplete' do
      allow(claim).to receive_messages(submitted_to_bgs?: true, submitted_to_claims_evidence_api?: false)

      expect(claim.submissions_succeeded?).to be false
    end
  end

  describe 'adding signatureDate' do
    it 'adds signature date appropriately' do
      # Force created_at to a known date before adding the signature date.
      claim.update(created_at: Time.new(2026, 3, 1).utc)
      claim.add_signature_date
      expect(claim.parsed_form).to include('signatureDate')
      expect(claim.parsed_form['signatureDate']).to eq('2026-03-01')
    end
  end

  describe '#submitted_to_bgs?' do
    context 'when there is no BGS submission' do
      it 'returns false' do
        expect(claim.submitted_to_bgs?).to be false
      end
    end

    context 'when is a BGS submission' do
      let!(:submission) { create(:bgs_submission, saved_claim: claim) }

      it 'returns false if there are no attempts' do
        expect(claim.submitted_to_bgs?).to be false
      end

      context 'when there are attempts' do
        let!(:attempt1) { create(:bgs_submission_attempt, submission:, status: 'submitted') }
        let!(:attempt2) { create(:bgs_submission_attempt, submission:, status: 'submitted') }

        it 'returns true if the latest is submitted' do
          expect(claim.submitted_to_bgs?).to be true
        end

        it 'returns false if any latest attempt is not submitted' do
          attempt2.update(status: 'failure')
          expect(claim.submitted_to_bgs?).to be false
        end
      end
    end
  end

  describe '#submitted_to_claims_evidence_api?' do
    context 'when there is no Claims Evidence submission' do
      it 'returns false' do
        expect(claim.submitted_to_claims_evidence_api?).to be false
      end
    end

    context 'when is a Claims Evidence submission' do
      let!(:submission) { create(:claims_evidence_submission, saved_claim: claim) }

      it 'returns false if there are no attempts' do
        expect(claim.submitted_to_claims_evidence_api?).to be false
      end

      context 'when there are attempts' do
        let!(:attempt1) { create(:claims_evidence_submission_attempt, submission:, status: 'accepted') }
        let!(:attempt2) { create(:claims_evidence_submission_attempt, submission:, status: 'accepted') }

        it 'returns true if the latest is submitted' do
          expect(claim.submitted_to_claims_evidence_api?).to be true
        end

        it 'returns false if any latest attempt is not submitted' do
          attempt2.update(status: 'failed')
          expect(claim.submitted_to_claims_evidence_api?).to be false
        end
      end
    end
  end

  describe '#to_pdf' do
    it 'works with legacy string filename argument' do
      expect(DependentsBenefits::PdfFill::Filler).to receive(:fill_form)
        .with(child_claim, 'custom_filename', {})
      child_claim.to_pdf('custom_filename')
    end

    it 'works with keyword arguments and uses claim ID as filename' do
      student_data = { name: 'Test Student' }

      expect(DependentsBenefits::PdfFill::Filler).to receive(:fill_form)
        .with(child_claim, child_claim.id.to_s, hash_including(form_id: '21-674', student: student_data))

      child_claim.to_pdf(form_id: '21-674', student: student_data)
    end

    context 'when veteran_information is missing' do
      before do
        allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_call_original

        child_claim.parsed_form.delete('veteran_information')
        child_claim.parsed_form['dependents_application'].delete('veteran_information')
      end

      it 'raises an error in the PDF filler' do
        expect { child_claim.to_pdf }.to raise_error(DependentsBenefits::MissingVeteranInfoError)
      end
    end

    context 'with a student claim' do
      before do
        allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_call_original
      end

      it 'builds the pdf correctly' do
        expect(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).with(student_claim, nil,
                                                                                {}).and_call_original
        expect { student_claim.to_pdf }.not_to raise_error
      end

      context 'when veteran_information is missing' do
        before do
          allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_call_original

          student_claim.parsed_form.delete('veteran_information')
        end

        it 'raises an error in the PDF filler' do
          expect { student_claim.to_pdf }.to raise_error(DependentsBenefits::MissingVeteranInfoError)
        end
      end
    end
  end

  describe '#fdf_submission_payload' do
    it 'returns expected format for FDF' do
      claim.update(created_at: Time.new(2026, 3, 1).utc)

      full_name = { 'first' => 'Roy', 'middle' => 'G', 'last' => 'Biv' }
      veteran_information = { 'veteran_information' => {
        'full_name' => full_name,
        'common_name' => 'Roy',
        'va_profile_email' => 'va@gov',
        'email' => 'foo@bar.com',
        'participant_id' => 'TEST',
        'ssn' => '123456789',
        'va_file_number' => 'FOOBAR',
        'birth_date' => '1776-07-04',
        'uuid' => SecureRandom.uuid,
        'icn' => 'SOMETHING'
      } }.to_json
      claim.add_veteran_info(JSON.parse(veteran_information))

      payload = claim.fdf_submission_payload

      expect(payload).not_to include('dependents_application')
      expect(payload).not_to include('dependentsApplication')
      expect(payload).to include('signatureDate')
      expect(payload.dig('veteranInformation', 'vaFileNumber')).to eq('FOOBAR')
      expect(payload.dig('veteranInformation', 'fullName', 'last')).to eq('Webb') # retain what was submitted
    end
  end

  describe 'validation behavior' do
    context 'when the form matches the schema' do
      let(:valid_combined_form) { build(:dependents_claim_combined_form) }

      before do
        allow(claim).to receive_messages(validate_schema: [], validate_form: [])
      end

      it 'returns true' do
        claim.form = valid_combined_form.to_json
        expect(claim.form_matches_schema).to be true
      end
    end

    context 'when the form does not match the schema' do
      before do
        allow_any_instance_of(DependentsBenefits::PrimaryDependencyClaim)
          .to receive(:validate_schema)
          .and_return([
                        { fragment: '#/veteran_information', message: 'is missing' }
                      ])
        allow_any_instance_of(DependentsBenefits::PrimaryDependencyClaim)
          .to receive(:validate_form)
          .and_return([])
        allow(monitor_double).to receive(:track_error_event)
      end

      it 'returns false and adds errors' do
        expect(claim.form_matches_schema).to be false
        expect(monitor_double).to have_received(:track_error_event).with(
          'Dependents Benefits schema failed validation.',
          action: 'schema_error',
          component: 'DependentsBenefits::PrimaryDependencyClaim',
          form_id: claim.form_id,
          errors: [{ fragment: '#/veteran_information', message: 'is missing' }]
        ).at_least(:once)
      end
    end
  end

  describe '#validate_form' do
    let(:schema) { { 'type' => 'object' } }
    let(:schemer) { instance_double(JSONSchemer::Schema) }
    let(:test_claim) { build(:dependents_claim) }

    before do
      allow(JSONSchemer).to receive(:schema).and_call_original
      allow(JSONSchemer).to receive(:schema).with(schema).and_return(schemer)
      allow(test_claim).to receive(:reformatted_schemer_errors).and_return([])
      allow(schemer).to receive(:validate).and_return([])
    end

    it 'flattens dependents_application to root before camelizing keys' do
      test_claim.form = {
        'some_root_key' => 'root value',
        'dependents_application' => {
          'some_nested_key' => 'nested value',
          'deep_nested_key' => {
            'inner_key' => 'inner value'
          }
        }
      }.to_json

      test_claim.send(:validate_form, schema)

      expect(schemer).to have_received(:validate).with(
        hash_including(
          'someRootKey' => 'root value',
          'someNestedKey' => 'nested value',
          'deepNestedKey' => { 'innerKey' => 'inner value' }
        )
      )
    end

    it 'uses dependents_application values when keys overlap with root' do
      test_claim.form = {
        'veteran_information' => { 'source' => 'root' },
        'dependents_application' => {
          'veteran_information' => { 'source' => 'dependents_application' }
        }
      }.to_json

      test_claim.send(:validate_form, schema)

      expect(schemer).to have_received(:validate).with(
        hash_including('veteranInformation' => { 'source' => 'dependents_application' })
      )
    end

    it 'handles missing dependents_application by validating camelized root data' do
      test_claim.form = {
        'root_only_key' => 'value'
      }.to_json

      test_claim.send(:validate_form, schema)

      expect(schemer).to have_received(:validate).with(
        hash_including('rootOnlyKey' => 'value')
      )
    end

    it 'handles nil dependents_application by validating camelized root data' do
      test_claim.form = {
        'root_only_key' => 'value',
        'dependents_application' => nil
      }.to_json

      test_claim.send(:validate_form, schema)

      expect(schemer).to have_received(:validate).with(
        hash_including('rootOnlyKey' => 'value')
      )
    end

    it 'does not mutate parsed_form during flattening/camelization' do
      original_form = {
        'some_root_key' => 'root value',
        'dependents_application' => {
          'some_nested_key' => 'nested value'
        }
      }
      test_claim.form = original_form.deep_dup.to_json

      test_claim.send(:validate_form, schema)

      expect(test_claim.parsed_form).to eq(original_form)
    end
  end

  describe '#form_schema' do
    context 'when the schema file cannot be loaded' do
      let(:form_id) { 'DOES_NOT_EXIST' }

      before do
        allow(claim).to receive(:monitor).and_return(monitor_double)
        allow(monitor_double).to receive(:track_error_event)
      end

      it 'returns nil and tracks the error' do
        expect(claim.form_schema(form_id)).to be_nil
        expect(monitor_double).to have_received(:track_error_event).with(
          'Dependents Benefits form schema could not be loaded.',
          action: 'schema_load_error',
          component: 'DependentsBenefits::PrimaryDependencyClaim',
          form_id:,
          error: /No such file or directory/
        )
      end
    end
  end

  describe '#pension_related_submission?' do
    context 'when feature flag is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:va_dependents_net_worth_and_pension).and_return(false) }

      it 'returns false' do
        expect(child_claim.pension_related_submission?).to be false
      end
    end

    context 'when feature flag is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:va_dependents_net_worth_and_pension).and_return(true) }

      context 'when the claim is pension related' do
        let(:claim) { create(:dependents_claim, :pension_related) }

        it 'returns true' do
          expect(claim.pension_related_submission?).to be true
        end
      end

      context 'when the claim is not pension related' do
        it 'returns false' do
          expect(claim.pension_related_submission?).to be false
        end
      end
    end
  end

  describe '#no_ssn_claim?' do
    context 'when feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_dependents_no_ssn).and_return(false)
      end

      it 'returns false' do
        expect(child_claim.no_ssn_claim?).to be false
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_dependents_no_ssn).and_return(true)
      end

      it 'returns false if no relevant sections are present' do
        child_claim.parsed_form['dependents_application']['spouse_information']['no_ssn'] = false
        child_claim.parsed_form['dependents_application']['children_to_add']&.each { |child| child['no_ssn'] = false }
        child_claim.parsed_form['dependents_application']['student_information']&.each do |student|
          student['no_ssn'] = false
        end

        expect(child_claim.no_ssn_claim?).to be false
      end

      it 'handles missing sections gracefully' do
        child_claim.parsed_form['dependents_application'].delete('spouse_information')
        child_claim.parsed_form['dependents_application'].delete('children_to_add')
        child_claim.parsed_form['dependents_application'].delete('student_information')

        expect { child_claim.no_ssn_claim? }.not_to raise_error
        expect(child_claim.no_ssn_claim?).to be false
      end

      it 'returns true if spouse is marked as having no SSN' do
        child_claim.parsed_form['dependents_application']['spouse_information']['no_ssn'] = true
        expect(child_claim.no_ssn_claim?).to be true
      end

      it 'returns true if any child/student is marked as having no SSN' do
        child_claim.parsed_form['dependents_application']['children_to_add'] = [{ 'no_ssn' => true }]
        expect(child_claim.no_ssn_claim?).to be true
      end

      it 'returns true if any student is marked as having no SSN' do
        child_claim.parsed_form['dependents_application']['student_information'] = [{ 'no_ssn' => true }]
        expect(child_claim.no_ssn_claim?).to be true
      end

      it 'returns true if a combination of dependents is marked as having no SSN' do
        child_claim.parsed_form['dependents_application']['spouse_information']['no_ssn'] = true
        child_claim.parsed_form['dependents_application']['children_to_add'] = [
          { 'no_ssn' => true },
          { 'no_ssn' => false }
        ]
        child_claim.parsed_form['dependents_application']['student_information'] = [
          { 'no_ssn' => false },
          { 'no_ssn' => true }
        ]
        expect(child_claim.no_ssn_claim?).to be true
      end
    end
  end

  describe '#folder_identifier' do
    context 'when ssn is present' do
      before do
        claim.parsed_form['veteran_information']['ssn'] = '123-45-6789'
        claim.parsed_form['veteran_information']['participant_id'] = nil
        claim.parsed_form['veteran_information']['icn'] = nil
      end

      it 'includes ssn in the folder identifier' do
        expect(claim.folder_identifier).to eq('VETERAN:SSN:123-45-6789')
      end
    end

    context 'when participant_id is present' do
      before do
        claim.parsed_form['veteran_information']['ssn'] = nil
        claim.parsed_form['veteran_information']['participant_id'] = 'P123456789'
        claim.parsed_form['veteran_information']['icn'] = nil
      end

      it 'includes participant_id in the folder identifier' do
        expect(claim.folder_identifier).to eq('VETERAN:PARTICIPANT_ID:P123456789')
      end
    end

    context 'when icn is present' do
      before do
        claim.parsed_form['veteran_information']['ssn'] = nil
        claim.parsed_form['veteran_information']['participant_id'] = nil
        claim.parsed_form['veteran_information']['icn'] = 'ICN123456789'
      end

      it 'includes icn in the folder identifier' do
        expect(claim.folder_identifier).to eq('VETERAN:ICN:ICN123456789')
      end
    end
  end

  describe '#claim_form_type' do
    context 'when both 686 and 674 forms are submittable' do
      it 'returns 686c-674' do
        expect(claim.claim_form_type).to eq('686c-674')
      end
    end

    context 'when only 686 form is submittable' do
      it 'returns 21-686c' do
        expect(child_claim.claim_form_type).to eq('21-686c')
      end
    end

    context 'when only 674 form is submittable' do
      it 'returns 21-674' do
        expect(student_claim.claim_form_type).to eq('21-674')
      end
    end

    context 'when form type is unknown' do
      before do
        allow(claim).to receive(:submittable_686?).and_raise(StandardError.new('Unknown form type'))
        allow(monitor_double).to receive(:track_warning_event)
      end

      it 'returns nil and tracks the unknown claim type' do
        expect(claim.claim_form_type).to be_nil
        expect(monitor_double).to have_received(:track_warning_event)
      end
    end
  end

  describe '#add_veteran_info' do
    it 'merges veteran information into the parsed form' do
      veteran_info = {
        'veteran_information' => {
          'ssn' => '987-65-4321',
          'participant_id' => 'P987654321',
          'icn' => 'ICN987654321'
        }
      }

      claim.add_veteran_info(veteran_info)

      expect(claim.parsed_form['veteran_information']['ssn']).to eq('987-65-4321')
      expect(claim.parsed_form['veteran_information']['participant_id']).to eq('P987654321')
      expect(claim.parsed_form['veteran_information']['icn']).to eq('ICN987654321')
    end
  end

  describe '#user_data' do
    it 'merges veteran information into the parsed form' do
      veteran_info = {
        'veteran_information' => {
          'ssn' => '987-65-4321',
          'participant_id' => 'P987654321',
          'icn' => 'ICN987654321'
        }
      }
      expect(claim_group).to receive(:user_data).and_return veteran_info.to_json
      expect(claim_group).to receive(:parent_claim_group_for_child).and_return claim_group
      expect(claim).to receive(:child_of_groups).and_return([claim_group])
      expect(claim).to receive(:add_veteran_info).and_call_original

      claim.user_data

      expect(claim.parsed_form['veteran_information']['ssn']).to eq('987-65-4321')
      expect(claim.parsed_form['veteran_information']['participant_id']).to eq('P987654321')
      expect(claim.parsed_form['veteran_information']['icn']).to eq('ICN987654321')
    end

    it 'logs an error and returns nil if unable to parse' do
      expect(claim).to receive(:child_of_groups).and_return([])
      expect(claim_group).not_to receive(:user_data)
      expect(monitor_double).to receive(:track_error_event)

      expect(claim.user_data).to be_nil
    end
  end

  describe '#parent_claim_id' do
    it 'returns the parent claim id' do
      expect(claim).to receive(:child_of_groups).and_return([claim_group])
      pid = claim.parent_claim_id

      expect(pid).to eq(claim.id)
    end
  end
end
