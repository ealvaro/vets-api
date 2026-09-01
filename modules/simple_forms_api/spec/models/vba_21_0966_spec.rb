# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/shared_examples_for_base_form'

RSpec.describe SimpleFormsApi::VBA210966 do
  it_behaves_like 'zip_code_is_us_based', %w[veteran_mailing_address surviving_dependent_mailing_address]

  describe 'populate_veteran_data' do
    context 'data does not already have what it needs' do
      let(:expected_first_name) { 'Rory' }
      let(:expected_last_name) { 'Stewart' }
      let(:expected_address) do
        {
          'postal_code' => '12345'
        }
      end
      let(:expected_ssn) { 'fake-ssn' }
      let(:user) { create(:user, first_name: expected_first_name, last_name: expected_last_name, ssn: expected_ssn) }
      let(:data) { {} }

      it 'pulls the data from the user' do
        allow(user).to receive(:address).and_return(expected_address)

        form = SimpleFormsApi::VBA210966.new(data).populate_veteran_data(user)

        expect(form.data['veteran_full_name']).to eq({ 'first' => expected_first_name, 'last' => expected_last_name })
        expect(form.data['veteran_mailing_address']).to eq expected_address
        expect(form.data['veteran_id']).to eq({ 'ssn' => expected_ssn })
      end
    end

    context 'data already has what it needs' do
      let(:expected_address) do
        {
          'postal_code' => '12345'
        }
      end
      let(:expected_full_name) { { 'first' => 'John', 'last' => 'Darwin' } }
      let(:expected_ssn) { 'fake-ssn' }
      let(:user) { create(:user) }
      let(:data) do
        { 'veteran_full_name' => expected_full_name, 'veteran_mailing_address' => expected_address,
          'veteran_id' => { 'ssn' => expected_ssn } }
      end

      it 'pulls the data from the form' do
        form = SimpleFormsApi::VBA210966.new(data).populate_veteran_data(user)

        expect(form.data['veteran_full_name']).to eq(expected_full_name)
        expect(form.data['veteran_mailing_address']).to eq expected_address
        expect(form.data['veteran_id']).to eq({ 'ssn' => expected_ssn })
      end
    end
  end

  describe '#notification_first_name' do
    context 'preparer is surviving dependent' do
      let(:data) do
        {
          'preparer_identification' => 'SURVIVING_DEPENDENT',
          'surviving_dependent_full_name' => {
            'first' => 'Surviving',
            'last' => 'Dependent'
          }
        }
      end

      it 'returns the surviving dependent first name' do
        expect(described_class.new(data).notification_first_name).to eq 'Surviving'
      end
    end

    context 'preparer is not the surviving dependent' do
      let(:data) do
        {
          'preparer_identification' => 'VETERAN',
          'veteran_full_name' => {
            'first' => 'Veteran',
            'last' => 'Eteranvay'
          }
        }
      end

      it 'returns the veteran first name' do
        expect(described_class.new(data).notification_first_name).to eq 'Veteran'
      end
    end
  end

  describe '#notification_email_address' do
    context 'preparer is surviving dependent' do
      let(:data) do
        {
          'preparer_identification' => 'SURVIVING_DEPENDENT',
          'surviving_dependent_email' => 'a@b.com'
        }
      end

      it 'returns the surviving dependent email address' do
        expect(described_class.new(data).notification_email_address).to eq 'a@b.com'
      end
    end

    context 'preparer is anyone else' do
      let(:data) do
        {
          'preparer_identification' => 'space-alien',
          'veteran_email' => 'a@b.com'
        }
      end

      it 'returns the veteran email address' do
        expect(described_class.new(data).notification_email_address).to eq 'a@b.com'
      end
    end
  end

  describe '#full_address' do
    it 'joins the address parts into a single line' do
      data = { 'veteran_mailing_address' => { 'street' => '1 Main St', 'street2' => 'Apt 2', 'street3' => 'Unit B',
                                              'city' => 'Austin', 'state' => 'TX', 'postal_code' => '78701',
                                              'country' => 'USA' } }

      expect(described_class.new(data).full_address('veteran_mailing_address'))
        .to eq '1 Main St Apt 2 Unit B, Austin, TX, 78701, USA'
    end

    it 'skips blank parts' do
      data = { 'surviving_dependent_mailing_address' => { 'street' => '1 Main St', 'street2' => '', 'city' => 'Austin',
                                                          'postal_code' => '78701' } }

      expect(described_class.new(data).full_address('surviving_dependent_mailing_address'))
        .to eq '1 Main St, Austin, 78701'
    end

    it 'returns an empty string when the address is missing' do
      expect(described_class.new({}).full_address('veteran_mailing_address')).to eq ''
    end
  end

  describe 'PDF field mapping' do
    let(:fixture) do
      JSON.parse(Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json',
                                 'vba_21_0966.json').read)
    end
    let(:template_path) { Rails.root.join('modules', 'simple_forms_api', 'templates', 'vba_21_0966.pdf').to_s }

    def mapped_data(data)
      form = described_class.new(data)
      SimpleFormsApi::PdfFiller.new(form_number: 'vba_21_0966', form:).send(:mapped_data)
    end

    it 'only maps field names that exist in the template' do
      template_fields = PdfForms.new(Settings.binaries.pdftk).get_field_names(template_path)
      mapped_fields = mapped_data(fixture).keys - ['F[0]']

      expect(mapped_fields - template_fields).to be_empty
    end

    it 'fills the single-line mailing address boxes' do
      data = fixture.merge('veteran_mailing_address' => { 'street' => '1 Main St', 'city' => 'Austin', 'state' => 'TX',
                                                          'postal_code' => '78701', 'country' => 'USA' })
      mapped = mapped_data(data)

      expect(mapped['F[0].Page_1[0].Address_Of_Parent_1[0]']).to eq '1 Main St, Austin, TX, 78701, USA'
      expect(mapped['F[0].Page_1[0].Address_Of_Parent_1[1]']).to eq '123 Fake St. Apt. 2, Fakesville, GA, 12345, USA'
    end

    context 'benefit selection checkboxes' do
      let(:compensation) { 'F[0].#subform[1].Compensation[0]' }
      let(:pension) { 'F[0].#subform[1].RadioButtonList[0]' }
      let(:survivors) { 'F[0].#subform[1].RadioButtonList[1]' }

      it 'checks only survivors when survivor is selected' do
        mapped = mapped_data(fixture.merge('benefit_selection' => { 'survivor' => true }))

        expect(mapped.values_at(compensation, pension, survivors)).to eq %w[0 Off 1]
      end

      it 'checks compensation and pension when both are selected' do
        mapped = mapped_data(fixture.merge('benefit_selection' => { 'compensation' => true, 'pension' => true }))

        expect(mapped.values_at(compensation, pension, survivors)).to eq %w[1 2 Off]
      end

      it 'leaves everything unchecked when nothing is selected' do
        mapped = mapped_data(fixture.merge('benefit_selection' => {}))

        expect(mapped.values_at(compensation, pension, survivors)).to eq %w[0 Off Off]
      end
    end
  end
end
