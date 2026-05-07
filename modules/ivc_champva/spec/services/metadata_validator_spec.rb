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

    describe 'supporting_docs validation' do
      it 'raises when supporting_docs is missing' do
        data = existing_payload.except('supporting_docs')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'supporting_docs is missing')
      end

      it 'raises when supporting_docs is empty' do
        data = existing_payload.merge('supporting_docs' => [])
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'supporting_docs is missing')
      end

      it 'raises when a doc is missing confirmation_code' do
        data = existing_payload.merge('supporting_docs' => [{ 'name' => 'doc.pdf' }])
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'supporting_docs[0] confirmation_code is missing')
      end
    end

    describe 'primary_contact_info validation' do
      it 'raises when primary_contact_info is missing' do
        data = existing_payload.except('primary_contact_info')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'primary_contact_info is missing')
      end

      it 'raises when email is missing' do
        data = existing_payload.merge('primary_contact_info' => { 'name' => { 'first' => 'Joe' } })
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'primary_contact_info email is missing')
      end
    end

    describe 'applicants validation' do
      it 'raises when applicants is missing' do
        data = existing_payload.except('applicants')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants is missing')
      end

      it 'raises when applicants is empty' do
        data = existing_payload.merge('applicants' => [])
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants is missing')
      end

      it 'raises when applicant first name is nil' do
        data = existing_payload.merge(
          'applicants' => [{ 'applicant_name' => { 'last' => 'Alvin' } }]
        )
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants[0] first name is missing')
      end

      it 'raises when applicant last name is nil' do
        data = existing_payload.merge(
          'applicants' => [{ 'applicant_name' => { 'first' => 'Johnny' } }]
        )
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants[0] last name is missing')
      end

      it 'raises when applicant_dob is nil' do
        data = existing_payload.deep_merge(
          'applicants' => [existing_payload['applicants'][0].except('applicant_dob')]
        )
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants[0] applicant_dob is missing')
      end

      it 'raises when applicant_member_number is nil for enrollment submissions' do
        data = enrollment_payload.deep_merge(
          'applicants' => [enrollment_payload['applicants'][0].except('applicant_member_number')]
        )
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'applicants[0] applicant_member_number is missing')
      end

      it 'does NOT require applicant_member_number for existing submissions' do
        data = existing_payload.deep_merge(
          'applicants' => [existing_payload['applicants'][0].except('applicant_member_number')]
        )
        expect { described_class.validate_docs_only_resubmission(data) }.not_to raise_error
      end
    end

    describe 'veteran validation' do
      it 'raises when veteran is missing' do
        data = existing_payload.except('veteran')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'veteran is missing')
      end

      it 'raises when veteran first name is nil for existing submissions' do
        data = existing_payload.merge('veteran' => { 'full_name' => { 'last' => 'Johnson' } })
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'veteran first name is missing')
      end

      it 'raises when veteran last name is nil for existing submissions' do
        data = existing_payload.merge('veteran' => { 'full_name' => { 'first' => 'Joe' } })
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'veteran last name is missing')
      end

      it 'raises when veteran ssn_or_tin is nil for existing submissions' do
        data = existing_payload.deep_merge('veteran' => { 'ssn_or_tin' => nil })
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'veteran ssn_or_tin is missing')
      end

      it 'raises when veteran date_of_birth is nil for existing submissions' do
        data = existing_payload.deep_merge('veteran' => { 'date_of_birth' => nil })
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'veteran date_of_birth is missing')
      end

      it 'does NOT raise for empty veteran data on enrollment submissions' do
        expect { described_class.validate_docs_only_resubmission(enrollment_payload) }.not_to raise_error
      end
    end

    describe 'certifier_role validation' do
      it 'raises when certifier_role is missing' do
        data = existing_payload.except('certifier_role')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'certifier_role is missing')
      end
    end

    describe 'statement_of_truth_signature validation' do
      it 'raises when statement_of_truth_signature is missing' do
        data = existing_payload.except('statement_of_truth_signature')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'statement_of_truth_signature is missing')
      end
    end

    describe 'certification validation' do
      it 'raises when certification date is missing' do
        data = existing_payload.merge('certification' => {})
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'certification date is missing')
      end

      it 'raises when certification is missing entirely' do
        data = existing_payload.except('certification')
        expect { described_class.validate_docs_only_resubmission(data) }
          .to raise_error(ArgumentError, 'certification date is missing')
      end
    end
  end
end
