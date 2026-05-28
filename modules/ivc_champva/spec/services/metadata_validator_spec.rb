# frozen_string_literal: true

require 'rails_helper'

describe IvcChampva::MetadataValidator do
  def first_name
    return 'sponsorFirstName' if Flipper.enabled?(:champva_update_metadata_keys)

    'veteranFirstName'
  end

  def last_name
    return 'sponsorLastName' if Flipper.enabled?(:champva_update_metadata_keys)

    'veteranLastName'
  end

  def first_name_error_label
    return 'sponsor first name' if Flipper.enabled?(:champva_update_metadata_keys)

    'veteran first name'
  end

  def set_flipper(enabled)
    allow(Flipper).to(
      receive(:enabled?).with(:champva_update_metadata_keys).and_return(enabled)
    )
  end

  [true, false].each do |champva_update_metadata_keys_enabled|
    # before do
    #   allow(Flipper).to(
    #     receive(:enabled?).with(:champva_update_metadata_keys).and_return(champva_update_metadata_keys_enabled)
    #   )
    # end

    describe 'metadata is valid' do
      it 'returns unmodified metadata' do
        set_flipper(champva_update_metadata_keys_enabled)

        metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '12345',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }

        validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

        expect(validated_metadata).to eq(metadata)
      end
    end

    describe 'metadata key has a missing value' do
      it 'raises a missing exception' do
        set_flipper(champva_update_metadata_keys_enabled)

        expect do
          IvcChampva::MetadataValidator.validate_presence_and_stringiness(nil, first_name_error_label)
        end.to raise_error(ArgumentError, "#{first_name_error_label} is missing")
      end
    end

    describe 'metadata key has a non-string value' do
      it 'raises a non-string exception' do
        set_flipper(champva_update_metadata_keys_enabled)

        expect do
          IvcChampva::MetadataValidator.validate_presence_and_stringiness(12, first_name_error_label)
        end.to raise_error(ArgumentError, "#{first_name_error_label} is not a string")
      end
    end

    describe 'first name is malformed' do
      describe 'too long' do
        it 'returns metadata with first 50 characters of the first name' do
          set_flipper(champva_update_metadata_keys_enabled)

          # rubocop:disable Layout/LineLength
          metadata = {
            first_name => 'Wolfeschlegelsteinhausenbergerdorffwelchevoralternwarengewissenhaftschaferswessenschafe
              warenwohlgepflegeundsorgfaltigkeitbeschutzenvonangreifendurchihrraubgierigfeindewelchevoralternzwolftausend
              jahresvorandieerscheinenvanderersteerdemenschderraumschiffgebrauchlichtalsseinursprungvonkraftgestartsein
              langefahrthinzwischensternartigraumaufdersuchenachdiesternwelchegehabtbewohnbarplanetenkreisedrehensichund
              wohinderneurassevonverstandigmenschlichkeitkonntefortpflanzenundsicherfreuenanlebenslanglichfreudeundruhemit
              nichteinfurchtvorangreifenvonandererintelligentgeschopfsvonhinzwischensternartigraum',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }
          # rubocop:enable Layout/LineLength
          expected_metadata = {
            first_name => 'Wolfeschlegelsteinhausenbergerdorffwelchevoraltern',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq expected_metadata
        end
      end

      describe 'contains disallowed characters' do
        it 'returns metadata with disallowed characters of first name stripped or corrected' do
          set_flipper(champva_update_metadata_keys_enabled)

          metadata = {
            first_name => '2Jöhn~! - Jo/hn?\\',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }
          expected_metadata = {
            first_name => 'John - Jo/hn',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq expected_metadata
        end
      end
    end

    describe 'last name is malformed' do
      describe 'too long' do
        it 'returns metadata with first 50 characters of last name' do
          set_flipper(champva_update_metadata_keys_enabled)

          # rubocop:disable Layout/LineLength
          metadata = {
            first_name => 'John',
            last_name => 'Wolfeschlegelsteinhausenbergerdorffwelchevoralternwarengewissenhaftschaferswessenschafe
              warenwohlgepflegeundsorgfaltigkeitbeschutzenvonangreifendurchihrraubgierigfeindewelchevoralternzwolftausend
              jahresvorandieerscheinenvanderersteerdemenschderraumschiffgebrauchlichtalsseinursprungvonkraftgestartsein
              langefahrthinzwischensternartigraumaufdersuchenachdiesternwelchegehabtbewohnbarplanetenkreisedrehensichund
              wohinderneurassevonverstandigmenschlichkeitkonntefortpflanzenundsicherfreuenanlebenslanglichfreudeundruhemit
              nichteinfurchtvorangreifenvonandererintelligentgeschopfsvonhinzwischensternartigraum',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }
          # rubocop:enable Layout/LineLength
          expected_metadata = {
            first_name => 'John',
            last_name => 'Wolfeschlegelsteinhausenbergerdorffwelchevoraltern',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq expected_metadata
        end
      end

      describe 'contains disallowed characters' do
        it 'returns metadata with disallowed characters of last name stripped or corrected' do
          set_flipper(champva_update_metadata_keys_enabled)

          metadata = {
            first_name => 'John',
            last_name => '2Jöh’n~! - J\'o/hn?\\',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }
          expected_metadata = {
            first_name => 'John',
            last_name => 'John - Jo/hn',
            'fileNumber' => '444444444',
            'zipCode' => '12345',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq expected_metadata
        end
      end
    end

    describe 'file number is malformed' do
      describe 'too long' do
        it 'raises an exception' do
          set_flipper(champva_update_metadata_keys_enabled)

          metadata = {
            first_name => 'John',
            last_name => 'Doe',
            'fileNumber' => '4444444442789',
            'zipCode' => '12345',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          expect do
            IvcChampva::MetadataValidator.validate(metadata)
          end.to raise_error(ArgumentError, 'file number is invalid. It must be 8 or 9 digits')
        end
      end

      describe 'missing' do
        it 'succeeds' do
          set_flipper(champva_update_metadata_keys_enabled)

          metadata = {
            first_name => 'John',
            last_name => 'Doe',
            'fileNumber' => '',
            'zipCode' => '12345',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq(metadata)
        end
      end
    end

    describe 'zip code is malformed' do
      it 'defaults to 00000' do
        set_flipper(champva_update_metadata_keys_enabled)

        metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '1234567890',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }
        expected_metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '00000',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }

        validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

        expect(validated_metadata).to eq expected_metadata
      end
    end

    describe 'zip code is 9 digits long' do
      it 'is transformed to a 5+4 format US zip code' do
        set_flipper(champva_update_metadata_keys_enabled)

        metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '123456789',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }
        expected_metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '12345-6789',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }

        validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

        expect(validated_metadata).to eq expected_metadata
      end
    end

    describe 'zip code is not US based' do
      it 'is set to 00000' do
        set_flipper(champva_update_metadata_keys_enabled)

        metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '12345',
          'country' => 'CA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }
        expected_metadata = {
          first_name => 'John',
          last_name => 'Doe',
          'fileNumber' => '444444444',
          'zipCode' => '00000',
          'country' => 'CA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '21-0845',
          'businessLine' => 'CMP'
        }

        validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

        expect(validated_metadata).to eq expected_metadata
      end

      describe 'zip code is nil' do
        it 'is set to 00000' do
          set_flipper(champva_update_metadata_keys_enabled)

          metadata = {
            first_name => 'John',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }
          expected_metadata = {
            first_name => 'John',
            last_name => 'Doe',
            'fileNumber' => '444444444',
            'zipCode' => '00000',
            'country' => 'USA',
            'source' => 'VA Platform Digital Forms',
            'docType' => '21-0845',
            'businessLine' => 'CMP'
          }

          validated_metadata = IvcChampva::MetadataValidator.validate(metadata)

          expect(validated_metadata).to eq expected_metadata
        end
      end
    end
  end

  describe '.validate_docs_only_resubmission' do
    let(:existing_payload) do
      {
        'form_number' => '10-10D-EXTENDED',
        'submission_type' => 'existing',
        'certifier_role' => 'sponsor',
        'veteran' => {
          'full_name' => { 'first' => 'Joe', 'middle' => 'T', 'last' => 'Johnson', 'suffix' => '' },
          'ssn_or_tin' => '411111111',
          'date_of_birth' => '01-01-1958'
        },
        'applicants' => [
          {
            'applicant_name' => { 'first' => 'Johnny', 'middle' => 'T', 'last' => 'Alvin', 'suffix' => 'Jr.' },
            'applicant_dob' => '01-04-2003',
            'applicant_member_number' => '345345345'
          }
        ],
        'primary_contact_info' => {
          'name' => { 'first' => 'Joe', 'last' => 'Johnson' },
          'email' => 'contact@email.gov'
        },
        'supporting_docs' => [
          {
            'name' => 'sample.png',
            'confirmation_code' => '0d21739a-632a-4773-90f6-480b2f2473ce',
            'attachment_id' => 'Birth certificate',
            'is_encrypted' => false
          }
        ],
        'certification' => { 'date' => '04-01-2026' },
        'statement_of_truth_signature' => 'Certifier Jones'
      }
    end

    let(:enrollment_payload) do
      existing_payload.merge(
        'submission_type' => 'enrollment',
        'certifier_role' => 'applicant',
        'veteran' => { 'full_name' => {}, 'ssn_or_tin' => '', 'date_of_birth' => '' },
        'primary_contact_info' => {
          'name' => { 'first' => 'Johnny', 'last' => 'Alvin' },
          'email' => 'johnny@email.gov'
        }
      )
    end

    it 'passes for a valid existing payload' do
      expect { described_class.validate_docs_only_resubmission(existing_payload) }.not_to raise_error
    end

    it 'passes for a valid enrollment payload with empty veteran data' do
      expect { described_class.validate_docs_only_resubmission(enrollment_payload) }.not_to raise_error
    end

    it 'passes for a valid existing payload with multiple supporting docs' do
      data = existing_payload.deep_merge(
        'supporting_docs' => [
          {
            'name' => 'birth-certificate.png',
            'confirmation_code' => '0d21739a-632a-4773-90f6-480b2f2473ce',
            'attachment_id' => 'Birth certificate'
          },
          {
            'name' => 'marriage-certificate.pdf',
            'confirmation_code' => 'f09a8f72-66d3-4db0-8a3b-4c6eb63a8d4d',
            'attachment_id' => 'Marriage certificate'
          }
        ]
      )

      expect { described_class.validate_docs_only_resubmission(data) }.not_to raise_error
    end

    it 'raises when certifier_role is missing' do
      data = existing_payload.except('certifier_role')
      expect { described_class.validate_docs_only_resubmission(data) }
        .to raise_error(ArgumentError, 'certifier_role is missing')
    end

    it 'does NOT raise when applicant_dob is missing for existing submissions' do
      data = existing_payload.deep_merge(
        'applicants' => [existing_payload['applicants'][0].except('applicant_dob')]
      )
      expect { described_class.validate_docs_only_resubmission(data) }.not_to raise_error
    end

    it 'raises when certification date is missing' do
      data = existing_payload.merge('certification' => {})
      expect { described_class.validate_docs_only_resubmission(data) }
        .to raise_error(ArgumentError, 'certification date is missing')
    end
  end

  describe '.validate_docs_only_resubmission_cst' do
    let(:docs_only_payload) do
      {
        'supporting_docs' => [
          {
            'name' => 'sample.png',
            'confirmation_code' => '0d21739a-632a-4773-90f6-480b2f2473ce',
            'attachment_id' => 'Birth certificate',
            'is_encrypted' => false
          }
        ]
      }
    end

    it 'passes for a valid docs-only payload' do
      expect { described_class.validate_docs_only_resubmission_cst(docs_only_payload) }.not_to raise_error
    end

    it 'does not require full-form fields for CST docs-only validation' do
      data = docs_only_payload.merge(
        'submission_type' => 'existing',
        'certifier_role' => nil,
        'statement_of_truth_signature' => nil,
        'certification' => {},
        'primary_contact_info' => {},
        'veteran' => {},
        'applicants' => []
      )

      expect { described_class.validate_docs_only_resubmission_cst(data) }.not_to raise_error
    end
  end
end
