# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormMappers::VHA107959f22025 do
  let(:fixture_data) do
    JSON.parse(File.read('modules/ivc_champva/spec/fixtures/form_json/vha_10_7959f_2.json'))
  end
  let(:form) { IvcChampva::VHA107959f22025.new(fixture_data) }
  let(:mapper) { described_class.new(form.data) }
  let(:fields) { mapper.mapped_fields }

  describe '#mapped_fields' do
    it 'returns a Hash' do
      expect(fields).to be_a(Hash)
    end

    context 'send payment radio' do
      it 'returns 0 when payment is to Veteran' do
        expect(fields['send_payment_radio']).to eq(0)
      end

      context 'when payment is to Provider' do
        let(:provider_data) do
          fixture_data.deep_dup.tap { |d| d['veteran']['send_payment'] = 'Provider' }
        end
        let(:form) { IvcChampva::VHA107959f22025.new(provider_data) }

        it 'returns 1' do
          expect(fields['send_payment_radio']).to eq(1)
        end
      end
    end

    context 'veteran name fields' do
      it 'maps last name without suffix' do
        expect(fields['veteran_last_name']).to eq('Surname')
      end

      it 'maps first name' do
        expect(fields['veteran_first_name']).to eq('Veteran')
      end

      it 'maps middle initial' do
        expect(fields['veteran_middle_initial']).to eq('B')
      end
    end

    context 'veteran identifiers' do
      it 'maps SSN' do
        expect(fields['veteran_ssn']).to eq('222554444')
      end

      it 'maps VA claim number' do
        expect(fields['veteran_va_claim_number']).to eq('123456789')
      end

      it 'maps date of birth' do
        expect(fields['veteran_dob']).to eq('02/02/1987')
      end
    end

    context 'address fields' do
      it 'formats physical address string' do
        expect(fields['veteran_physical_address']).to eq('1 Physical Ln\nPlace, AL\n12345')
      end

      it 'maps physical address country' do
        expect(fields['veteran_physical_country']).to eq('USA')
      end

      it 'formats mailing address string' do
        expect(fields['veteran_mailing_address']).to eq('1 Mail Ln\nPlace, PA\n12345')
      end

      it 'maps mailing address country' do
        expect(fields['veteran_mailing_country']).to eq('USA')
      end
    end

    context 'contact and signature fields' do
      it 'maps phone number' do
        expect(fields['veteran_phone']).to eq('9876543213')
      end

      it 'maps email address' do
        expect(fields['veteran_email']).to eq('veteran@mail.com')
      end

      it 'maps statement of truth signature' do
        expect(fields['statement_of_truth_signature']).to eq('Veteran B Surname')
      end

      it 'maps current date' do
        expect(fields['current_date']).to eq('01/01/2024')
      end
    end
  end
end
