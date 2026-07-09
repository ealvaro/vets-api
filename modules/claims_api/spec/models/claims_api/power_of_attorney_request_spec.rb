# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::PowerOfAttorneyRequest do
  describe 'validations' do
    def build_validated_request(attributes)
      request = described_class.new(**attributes)
      request.valid?
      request
    end

    let(:valid_attributes) do
      {
        proc_id: '123456',
        veteran_icn: '1012667169V030190',
        poa_code: '074'
      }
    end

    describe '#validate_meta_schema' do
      context 'with valid metadata' do
        it 'passes validation when metadata is nil' do
          attributes = valid_attributes.merge(metadata: nil)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with empty metadata hash' do
          attributes = valid_attributes.merge(metadata: {})

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with only veteran branch' do
          metadata = {
            'veteran' => {
              'vnp_mail_id' => '12345',
              'vnp_email_id' => '67890',
              'vnp_phone_id' => '11111'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with only claimant branch' do
          metadata = {
            'claimant' => {
              'vnp_mail_id' => '22222',
              'vnp_email_id' => '33333',
              'vnp_phone_id' => '44444'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with both veteran and claimant branches' do
          metadata = {
            'veteran' => {
              'vnp_mail_id' => '12345',
              'vnp_email_id' => '67890',
              'vnp_phone_id' => '11111'
            },
            'claimant' => {
              'vnp_mail_id' => '22222',
              'vnp_email_id' => '33333',
              'vnp_phone_id' => '44444'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with phone_data nested in veteran' do
          metadata = {
            'veteran' => {
              'vnp_mail_id' => '12345',
              'phone_data' => {
                'countryCode' => '1',
                'areaCode' => '555',
                'phoneNumber' => '1234567'
              }
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with phone_data nested in claimant' do
          metadata = {
            'claimant' => {
              'vnp_phone_id' => '99999',
              'phone_data' => {
                'countryCode' => '44',
                'areaCode' => '20',
                'phoneNumber' => '7946543210'
              }
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end

        it 'passes validation with optional phone_data fields omitted' do
          metadata = {
            'veteran' => {
              'vnp_mail_id' => '12345',
              'phone_data' => {
                'phoneNumber' => '1234567'
              }
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end
      end

      context 'with invalid metadata - unknown keys' do
        it 'fails validation with typo in veteran key' do
          metadata = {
            'veteran' => {
              'vnp_mail_id' => '12345',
              'vnp_mail_id_typo' => '67890'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata].first).to eq(
            'invalid at /veteran/vnp_mail_id_typo: The property ' \
            '/veteran/vnp_mail_id_typo is not defined on the schema. ' \
            'Additional properties are not allowed'
          )
        end

        it 'fails validation with typo in claimant key' do
          metadata = {
            'claimant' => {
              'vnp_email_id' => '33333',
              'vnp_email_typo' => '44444'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata].first).to eq(
            'invalid at /claimant/vnp_email_typo: The property /claimant/vnp_email_typo is ' \
            'not defined on the schema. Additional properties are not allowed'
          )
        end

        it 'fails validation with unknown top-level key' do
          metadata = {
            'unknown_branch' => {
              'vnp_mail_id' => '12345'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata].first).to eq(
            'invalid at /unknown_branch: The property /unknown_branch is not defined on ' \
            'the schema. Additional properties are not allowed'
          )
        end

        it 'fails validation with typo in phone_data key' do
          metadata = {
            'veteran' => {
              'vnp_phone_id' => '11111',
              'phone_data' => {
                'countryCode' => '1',
                'areCode' => '555'
              }
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata].first).to eq(
            'invalid at /veteran/phone_data/areCode: The property /veteran/phone_data/areCode is ' \
            'not defined on the schema. Additional properties are not allowed'
          )
        end

        it 'returns multiple metadata errors when multiple unknown keys are present' do
          metadata = {
            'veteran' => {
              'vnp_mail_id_typo' => '12345'
            },
            'claimant' => {
              'vnp_email_typo' => '44444'
            }
          }
          attributes = valid_attributes.merge(metadata:)
          errors = build_validated_request(attributes).errors[:metadata]

          expect(errors.length).to be >= 2
          expect(errors).to include(
            'invalid at /veteran/vnp_mail_id_typo: The property ' \
            '/veteran/vnp_mail_id_typo is not defined on the schema. ' \
            'Additional properties are not allowed'
          )
          expect(errors).to include(
            'invalid at /claimant/vnp_email_typo: The property ' \
            '/claimant/vnp_email_typo is not defined on the schema. ' \
            'Additional properties are not allowed'
          )
        end
      end

      context 'with invalid metadata - wrong types' do
        it 'fails validation when metadata is a top-level string' do
          attributes = valid_attributes.merge(metadata: 'not a hash')

          expect(build_validated_request(attributes).errors[:metadata].first).to include(
            'invalid at /: The property  did not match the following requirements:'
          )
        end

        it 'fails validation when phone_data is not an object' do
          metadata = {
            'veteran' => {
              'phone_data' => 'not an object'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata].first).to include(
            'invalid at /veteran/phone_data: The property /veteran/phone_data ' \
            'did not match the following requirements:'
          )
        end
      end

      context 'metadata normalization' do
        it 'handles symbol keys by converting to strings before validation' do
          metadata = {
            veteran: {
              vnp_mail_id: '12345'
            }
          }
          attributes = valid_attributes.merge(metadata:)

          expect(build_validated_request(attributes).errors[:metadata]).to be_empty
        end
      end
    end

    describe 'standard validations still work' do
      subject(:request) { described_class.new(**attributes) }

      let(:attributes) { valid_attributes }

      before do
        request.valid?
      end

      context 'when proc_id is missing' do
        let(:attributes) { valid_attributes.except(:proc_id) }

        it 'validates proc_id presence' do
          expect(request.errors[:proc_id].first).to eq("can't be blank")
        end
      end

      context 'when veteran_icn is missing' do
        let(:attributes) { valid_attributes.except(:veteran_icn) }

        it 'validates veteran_icn presence' do
          expect(request.errors[:veteran_icn].first).to eq("can't be blank")
        end
      end

      context 'when poa_code is missing' do
        let(:attributes) { valid_attributes.except(:poa_code) }

        it 'validates poa_code presence' do
          expect(request.errors[:poa_code]).not_to be_empty
        end
      end
    end
  end
end
