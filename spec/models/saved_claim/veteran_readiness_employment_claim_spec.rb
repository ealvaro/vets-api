# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../modules/claims_api/spec/support/fake_vbms'
require 'claims_api/vbms_uploader'
require Rails.root.join('modules', 'claims_evidence_api', 'lib', 'claims_evidence_api', 'service', 'search').to_s
require Rails.root.join('modules', 'claims_evidence_api', 'lib', 'claims_evidence_api', 'uploader').to_s

RSpec.describe SavedClaim::VeteranReadinessEmploymentClaim do
  let(:user_object) { create(:evss_user, :loa3) }
  let(:user_struct) do
    OpenStruct.new(
      edipi: user_object.edipi,
      participant_id: user_object.participant_id,
      pid: user_object.participant_id,
      birth_date: user_object.birth_date,
      ssn: user_object.ssn,
      vet360_id: user_object.vet360_id,
      loa3?: true,
      icn: user_object.icn,
      uuid: user_object.uuid,
      first_name: user_object.first_name,
      va_profile_email: user_object.va_profile_email
    )
  end
  let(:encrypted_user) { KmsEncrypted::Box.new.encrypt(user_struct.to_h.to_json) }
  let(:user) { OpenStruct.new(JSON.parse(KmsEncrypted::Box.new.decrypt(encrypted_user))) }
  let(:claim) { create(:veteran_readiness_employment_claim) }

  before do
    allow_any_instance_of(RES::Ch31Form).to receive(:submit).and_return(true)
  end

  describe '#form_id' do
    it 'returns the correct form ID' do
      expect(claim.form_id).to eq('28-1900')
    end
  end

  describe '#after_create_metrics' do
    it 'increments StatsD saved_claim.create' do
      allow(StatsD).to receive(:increment)
      claim.save!

      tags = ['form_id:28-1900', 'doctype:10']
      expect(StatsD).to have_received(:increment).with('saved_claim.create', { tags: })
    end
  end

  describe '#add_claimant_info' do
    it 'adds veteran information' do
      claim.add_claimant_info(user_object)
      claimant_keys = %w[fullName dob pid edipi vet360ID regionalOffice regionalOfficeName stationId VAFileNumber
                         ssn]
      form_data = {
        'fullName' => {
          'first' => 'First',
          'middle' => 'Middle',
          'last' => 'Last',
          'suffix' => 'III'
        },
        'dob' => '1986-05-06'
      }
      expect(claim.parsed_form['veteranInformation']).to include(form_data)
      expect(claim.parsed_form['veteranInformation']).to include(*claimant_keys)
    end

    it 'does not obtain va_file_number' do
      people_service_object = double('people_service')
      allow(people_service_object).to receive(:find_person_by_participant_id)
      allow(BGS::People::Request).to receive(:new) { people_service_object }

      claim.add_claimant_info(user_object)
      expect(claim.parsed_form['veteranInformation']).to include('VAFileNumber' => nil)
    end
  end

  describe '#send_email' do
    let(:notification_email) { double('notification_email') }

    before do
      allow(VRE::NotificationEmail).to receive(:new).with(claim.id).and_return(notification_email)
    end

    context 'when email_type is a confirmation type' do
      it 'sends VBMS confirmation email' do
        expect(notification_email).to receive(:deliver).with(:confirmation_vbms)
        claim.send_email(:confirmation_vbms)
      end

      it 'sends Lighthouse confirmation email' do
        expect(notification_email).to receive(:deliver).with(:confirmation_lighthouse)
        claim.send_email(:confirmation_lighthouse)
      end
    end

    context 'when email_type is not a confirmation type' do
      it 'sends error email' do
        expect(notification_email).to receive(:deliver).with(:error)
        claim.send_email(:error)
      end
    end
  end

  describe '#send_to_vre' do
    it 'propagates errors from send_to_lighthouse!' do
      allow(claim).to receive(:process_attachments!).and_raise(StandardError, 'Attachment error')

      expect do
        claim.send_to_lighthouse!(user_object)
      end.to raise_error(StandardError, 'Attachment error')
    end

    context 'when VBMS response is VBMSDownForMaintenance' do
      before do
        allow(OpenSSL::PKCS12).to receive(:new).and_return(double.as_null_object)
        @vbms_client = FakeVBMS.new
        allow(VBMS::Client).to receive(:from_env_vars).and_return(@vbms_client)
      end

      it 'calls #send_to_lighthouse!' do
        expect(claim).to receive(:send_to_lighthouse!)
        claim.send_to_vre(user_object)
      end

      it 'does not raise an error' do
        allow(claim).to receive(:send_to_lighthouse!)
        expect { claim.send_to_vre(user_object) }.not_to raise_error
      end
    end

    context 'when VBMS upload is successful' do
      before do
        allow(Flipper).to receive(:enabled?).with(:vre_use_claims_evidence_api).and_return(false)
        expect(ClaimsApi::VBMSUploader).to receive(:new) { OpenStruct.new(upload!: {}) }
      end

      context 'submission to VRE' do
        before do
          # As the PERMITTED_OFFICE_LOCATIONS constant at
          # the top of: app/models/saved_claim/veteran_readiness_employment_claim.rb gets changed, you
          # may need to change this mock below and maybe even move it into different 'it'
          # blocks if you need to test different routing offices
          expect_any_instance_of(BGS::RORoutingService).to receive(:get_regional_office_by_zip_code).and_return(
            { regional_office: { number: '325' } }
          )
        end

        it 'sends confirmation email' do
          expect(claim).to receive(:send_email)
            .with(:confirmation_vbms)

          claim.send_to_vre(user_object)
        end
      end

      # We want all submission to go through with RES
      context 'non-submission to VRE' do
        context 'flipper enabled' do
          it 'stops submission if location is not in list' do
            expect_any_instance_of(RES::Ch31Form).to receive(:submit)
            claim.add_claimant_info(user_object)

            claim.send_to_vre(user_object)
          end
        end
      end
    end

    context 'when user has no PID' do
      let(:user_object) { create(:unauthorized_evss_user) }

      it 'PDF is sent to Central Mail and not VBMS' do
        expect(claim).to receive(:process_attachments!)
        expect(claim).to receive(:send_to_lighthouse!).with(user_object).once.and_call_original
        expect(claim).to receive(:send_email).with(:confirmation_lighthouse)
        expect(claim).not_to receive(:upload_to_vbms)
        expect(VeteranReadinessEmploymentMailer).to receive(:build).with(
          user_object.participant_id, 'VRE.VBAPIT@va.gov', true
        ).and_call_original
        claim.send_to_vre(user_object)
      end
    end
  end

  describe '#regional_office' do
    it 'returns an empty array' do
      expect(claim.regional_office).to be_empty
    end
  end

  describe '#check_form_v2_validations' do
    ['', [], nil, {}].each do |address|
      context "with empty #{address} input" do
        describe 'address validation' do
          it 'accepts empty address format as not required' do
            claim_data = JSON.parse(claim.form)
            claim_data['veteranAddress'] = address
            claim_data['newAddress'] = address
            claim.form = claim_data.to_json
            expect(claim).to be_valid
          end
        end
      end
    end

    context 'when address is not empty' do
      let(:claim) { build(:veteran_readiness_employment_claim) }

      it 'passes validation with only street and city' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'street' => '123 Main St',
          'city' => 'Anytown'
        }
        claim_data['newAddress'] = {
          'street' => '456 Elm St',
          'city' => 'Othertown'
        }
        claim.form = claim_data.to_json
        expect(claim).to be_valid
      end

      it 'passes validation when only one address object is present' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'street' => '123 Main St',
          'city' => 'Anytown'
        }
        claim.form = claim_data.to_json
        expect(claim).to be_valid
      end

      it 'fails validation when one address object is missing street' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'country' => 'USA',
          'city' => 'Anytown',
          'state' => 'NY',
          'postalCode' => '12345'
        }
        claim.form = claim_data.to_json
        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/veteranAddress/street')
      end

      it 'fails validation when street is missing' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'country' => 'USA',
          'city' => 'Anytown',
          'state' => 'NY',
          'postalCode' => '12345'
        }
        claim_data['newAddress'] = {
          'country' => 'USA',
          'city' => 'Othertown',
          'state' => 'CA',
          'postalCode' => '67890'
        }
        claim.form = claim_data.to_json
        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/veteranAddress/street')
        expect(claim.errors.attribute_names).to include(:'/newAddress/street')
      end

      it 'fails validation when city is missing' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'country' => 'USA',
          'street' => '123 Main St',
          'state' => 'NY',
          'postalCode' => '12345'
        }
        claim_data['newAddress'] = {
          'country' => 'USA',
          'street' => '456 Elm St',
          'state' => 'CA',
          'postalCode' => '67890'
        }
        claim.form = claim_data.to_json
        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/veteranAddress/city')
        expect(claim.errors.attribute_names).to include(:'/newAddress/city')
      end

      it 'fails validation when fileds are longer than allowed' do
        claim_data = JSON.parse(claim.form)
        claim_data['veteranAddress'] = {
          'country' => 'USA',
          'city' => 'A' * 101,
          'street' => '123 Main St',
          'state' => 'N' * 101,
          'postalCode' => '12345'
        }
        claim_data['newAddress'] = {
          'country' => 'USA',
          'city' => 'O' * 101,
          'street' => '456 Elm St',
          'state' => 'C' * 101,
          'postalCode' => '67890'
        }
        claim.form = claim_data.to_json
        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/veteranAddress/city')
        expect(claim.errors.attribute_names).to include(:'/veteranAddress/state')
        expect(claim.errors.attribute_names).to include(:'/newAddress/city')
        expect(claim.errors.attribute_names).to include(:'/newAddress/state')
      end

      # ['1', '123456', '123456789', 'a' * 5].each do |postal_code|
      #   context 'postal code is not XXXXX or XXXXX-XXXX format' do
      #     it 'fails validation' do
      #       claim = build(:new_veteran_readiness_employment_claim, postal_code:)

      #       expect(claim).not_to be_valid
      #       expect(claim.errors.attribute_names).to include(:'/veteranAddress/postalCode')
      #       expect(claim.errors.attribute_names).to include(:'/veteranAddress/postalCode')
      #     end
      #   end
      # end
    end

    ['USA', 'United States'].each do |country|
      context "with #{country} format" do
        let(:claim) { build(:veteran_readiness_employment_claim, country:) }

        describe 'country validation' do
          it 'accepts valid country format' do
            expect(claim).to be_valid
          end

          it 'validates other fields independently of country format' do
            claim_data = JSON.parse(claim.form)
            claim_data['veteranInformation']['fullName'] = {} # Invalid name
            claim.form = claim_data.to_json

            expect(claim).not_to be_valid
            expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/first')
            expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/last')
          end
        end
      end
    end

    ['', ' ', nil].each do |invalid_input|
      context 'when required field is empty' do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, email: invalid_input, is_moving: invalid_input,
                                                             years_of_ed: invalid_input, first: invalid_input,
                                                             last: invalid_input, dob: invalid_input,
                                                             privacyAgreementAccepted: invalid_input)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/email')
          expect(claim.errors.attribute_names).to include(:'/isMoving')
          expect(claim.errors.attribute_names).to include(:'/yearsOfEducation')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/first')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/last')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/dob')
        end
      end
    end

    [0, true, ['data']].each do |invalid_type|
      context "when string field receives #{invalid_type} data type" do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, main_phone: invalid_type, cell_phone: invalid_type,
                                                             international_number: invalid_type,
                                                             email: invalid_type, years_of_ed: invalid_type,
                                                             first: invalid_type, middle: invalid_type,
                                                             last: invalid_type, dob: invalid_type)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/mainPhone')
          expect(claim.errors.attribute_names).to include(:'/cellPhone')
          expect(claim.errors.attribute_names).to include(:'/internationalNumber')
          expect(claim.errors.attribute_names).to include(:'/email')
          expect(claim.errors.attribute_names).to include(:'/yearsOfEducation')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/first')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/middle')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/last')
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/dob')
        end
      end
    end

    ['true', 1, 0, [], nil].each do |invalid_type|
      context "when isMoving receives #{invalid_type} data type" do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, is_moving: invalid_type)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/isMoving')
        end
      end
    end

    context 'when name field is allowed length' do
      it 'passes validation' do
        name = 'a' * 30
        claim = build(:veteran_readiness_employment_claim, first: name, middle: name, last: name)
        expect(claim).to be_valid
      end
    end

    context 'when name field is too long' do
      it 'fails validation' do
        long_name = 'a' * 31
        claim = build(:veteran_readiness_employment_claim, first: long_name, middle: long_name, last: long_name)

        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/first')
        expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/middle')
        expect(claim.errors.attribute_names).to include(:'/veteranInformation/fullName/last')
      end
    end

    context 'when email field is allowed length' do
      it 'passes validation' do
        email = "#{'a' * 244}@example.com"
        claim = build(:veteran_readiness_employment_claim, email:)
        expect(claim).to be_valid
      end
    end

    context 'when email field is too long' do
      it 'fails validation' do
        email = "#{'a' * 245}@example.com"
        claim = build(:veteran_readiness_employment_claim, email:)

        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/email')
      end
    end

    ['email.com', '@email.com', 'email', '@.com'].each do |email|
      context 'when email field is not properly formatted' do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, email:)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/email')
        end
      end
    end

    ['1', '123456789', '12345678901', 'a' * 10].each do |invalid_phone|
      context 'when phone field is not 10 digits' do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, main_phone: invalid_phone,
                                                             cell_phone: invalid_phone)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/mainPhone')
          expect(claim.errors.attribute_names).to include(:'/cellPhone')
        end
      end
    end

    %w[10-30-1990 30-10-1990 90-10-30 1990-10-1 1990-9-9].each do |invalid_dob|
      context 'when dob field does not match YYYY-MM-DD format' do
        it 'fails validation' do
          claim = build(:veteran_readiness_employment_claim, dob: invalid_dob)

          expect(claim).not_to be_valid
          expect(claim.errors.attribute_names).to include(:'/veteranInformation/dob')
        end
      end
    end
  end

  ['true', 1, 0, [], nil].each do |invalid_type|
    context "when privacyAgreementAccepted receives #{invalid_type} data type" do
      it 'fails validation' do
        claim = build(:veteran_readiness_employment_claim, privacyAgreementAccepted: invalid_type)

        expect(claim).not_to be_valid
        expect(claim.errors.attribute_names).to include(:'/privacyAgreementAccepted')
      end
    end
  end

  describe '#upload_to_vbms' do
    let(:upload_user) { build(:user) }
    let(:form_path) { 'tmp/test_vre_form.pdf' }

    let(:veteran_information) { { 'VAFileNumber' => '123456789', 'ssn' => '987654321' } }
    let(:base_parsed_form) do
      claim.parsed_form.merge(
        'veteranInformation' => claim.parsed_form.fetch('veteranInformation', {}).merge(veteran_information)
      )
    end

    before do
      allow(PdfFill::Filler).to receive(:fill_form).and_return(form_path)
      allow(claim).to receive(:parsed_form).and_return(base_parsed_form)
    end

    context 'when vre_use_claims_evidence_api flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_return(false)
      end

      context 'when veteran identifier is missing' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => nil, 'ssn' => nil)
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs a validation error with the missing identifier message' do
          allow(Rails.logger).to receive(:error)

          claim.upload_to_vbms(user: upload_user)

          expect(Rails.logger).to have_received(:error).with(
            'Error uploading VRE claim to VBMS.',
            {
              user_uuid: upload_user.uuid,
              message: 'SSN or VA File Number required'
            }
          )
        end
      end

      context 'when veteran identifier formats are invalid' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => 'BAD-ID', 'ssn' => '1234')
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs a validation error describing invalid formats' do
          allow(Rails.logger).to receive(:error)
          expected_message = 'Invalid veteran identifiers: SSN must be 9 digits; ' \
                             'VA File Number must be 7-9 digits with optional leading C'

          claim.upload_to_vbms(user: upload_user)

          expect(Rails.logger).to have_received(:error).with(
            'Error uploading VRE claim to VBMS.',
            {
              user_uuid: upload_user.uuid,
              message: expected_message
            }
          )
        end
      end

      it 'uses ClaimsApi::VBMSUploader and stores the document series ref id as documentId' do
        allow_any_instance_of(ClaimsApi::VBMSUploader).to receive(:upload!)
          .and_return({ vbms_document_series_ref_id: 'DOC-SERIES-001' })

        claim.upload_to_vbms(user: upload_user)

        expect(claim.parsed_form['documentId']).to eq('DOC-SERIES-001')
      end

      it 'uses VAFileNumber as file_number when present' do
        vbms_uploader = instance_double(ClaimsApi::VBMSUploader)
        allow(vbms_uploader).to receive(:upload!).and_return({ vbms_document_series_ref_id: 'X' })
        expect(ClaimsApi::VBMSUploader).to receive(:new).with(
          filepath: Rails.root.join(form_path),
          file_number: '123456789',
          doc_type: '1167'
        ).and_return(vbms_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'falls back to SSN as file_number when VAFileNumber is blank' do
        allow(claim).to receive(:parsed_form)
          .and_return(
            base_parsed_form.merge(
              'veteranInformation' => base_parsed_form.fetch('veteranInformation', {}).merge('VAFileNumber' => '')
            )
          )

        vbms_uploader = instance_double(ClaimsApi::VBMSUploader)
        allow(vbms_uploader).to receive(:upload!).and_return({ vbms_document_series_ref_id: 'X' })
        expect(ClaimsApi::VBMSUploader).to receive(:new).with(
          filepath: Rails.root.join(form_path),
          file_number: '987654321',
          doc_type: '1167'
        ).and_return(vbms_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'normalizes SSN by stripping non-digits before VBMS upload' do
        allow(claim).to receive(:parsed_form)
          .and_return(
            base_parsed_form.merge(
              'veteranInformation' => base_parsed_form.fetch('veteranInformation', {}).merge(
                'VAFileNumber' => '',
                'ssn' => '987-65-4321'
              )
            )
          )

        vbms_uploader = instance_double(ClaimsApi::VBMSUploader)
        allow(vbms_uploader).to receive(:upload!).and_return({ vbms_document_series_ref_id: 'X' })
        expect(ClaimsApi::VBMSUploader).to receive(:new).with(
          filepath: Rails.root.join(form_path),
          file_number: '987654321',
          doc_type: '1167'
        ).and_return(vbms_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'falls back to send_to_lighthouse! on upload error' do
        allow_any_instance_of(ClaimsApi::VBMSUploader).to receive(:upload!)
          .and_raise(StandardError, 'VBMS unavailable')
        expect(claim).to receive(:send_to_lighthouse!).with(upload_user)

        claim.upload_to_vbms(user: upload_user)
      end
    end

    context 'when vre_use_claims_evidence_api flipper is enabled' do
      let(:ce_uploader) { instance_double(ClaimsEvidenceApi::Uploader) }
      let(:search_service) { instance_double(ClaimsEvidenceApi::Service::Search) }

      before do
        allow(Flipper).to receive(:enabled?).and_return(true)
        allow(ClaimsEvidenceApi::Service::Search).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:folder_identifier=)
        allow(search_service).to receive(:find).and_return(double(body: { 'files' => [] }))
        allow(ClaimsEvidenceApi::Uploader).to receive(:new).and_return(ce_uploader)
        allow(ce_uploader).to receive(:upload_evidence).and_return('uuid-001')
      end

      it 'uses ClaimsEvidenceApi::Uploader and stores the file uuid as documentId' do
        claim.upload_to_vbms(user: upload_user)

        expect(claim.parsed_form['documentId']).to eq('uuid-001')
      end

      it 'builds a FILENUMBER folder identifier when VAFileNumber is present' do
        expect(ClaimsEvidenceApi::Uploader).to receive(:new)
          .with('VETERAN:FILENUMBER:123456789').and_return(ce_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'builds an SSN folder identifier when VAFileNumber is blank' do
        allow(claim).to receive(:parsed_form)
          .and_return(
            base_parsed_form.merge(
              'veteranInformation' => base_parsed_form.fetch('veteranInformation', {}).merge('VAFileNumber' => '')
            )
          )

        expect(ClaimsEvidenceApi::Uploader).to receive(:new)
          .with('VETERAN:SSN:987654321').and_return(ce_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'calls upload_evidence with the correct parameters' do
        expect(ce_uploader).to receive(:upload_evidence).with(
          claim.id,
          file_path: Rails.root.join(form_path).to_s,
          form_id: '28-1900',
          doctype: 1167
        ).and_return('uuid-001')

        claim.upload_to_vbms(user: upload_user)
      end

      it 'checks that the Claims Evidence folder exists before uploading' do
        expect(search_service).to receive(:folder_identifier=).with('VETERAN:FILENUMBER:123456789')
        expect(search_service).to receive(:find).with(filters: {})

        claim.upload_to_vbms(user: upload_user)
      end

      it 'falls back to legacy VBMS when Claims Evidence folder is missing' do
        allow(search_service).to receive(:find).and_raise(
          Common::Client::Errors::ClientError.new(
            'Unable to retrieve folder of Type: VETERAN using Identifier: SSN.',
            403,
            { 'code' => 'VEFSERR40302' }
          )
        )
        vbms_uploader = instance_double(ClaimsApi::VBMSUploader)
        allow(vbms_uploader).to receive(:upload!).and_return({ vbms_document_series_ref_id: 'DOC-SERIES-001' })

        expect(ClaimsEvidenceApi::Uploader).not_to receive(:new)
        expect(ClaimsApi::VBMSUploader).to receive(:new).and_return(vbms_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'tries SSN folder identifier when FILENUMBER folder lookup fails' do
        missing_folder_error = Common::Client::Errors::ClientError.new(
          'Unable to retrieve folder of Type: VETERAN using Identifier: FILENUMBER.',
          403,
          { 'code' => 'VEFSERR40302' }
        )

        expect(search_service).to receive(:folder_identifier=)
          .with('VETERAN:FILENUMBER:123456789').ordered
        expect(search_service).to receive(:find)
          .with(filters: {}).ordered.and_raise(missing_folder_error)
        expect(search_service).to receive(:folder_identifier=).with('VETERAN:SSN:987654321').ordered
        expect(search_service).to receive(:find)
          .with(filters: {}).ordered.and_return(double(body: { 'files' => [] }))

        expect(ClaimsEvidenceApi::Uploader).to receive(:new)
          .with('VETERAN:SSN:987654321').and_return(ce_uploader)

        claim.upload_to_vbms(user: upload_user)
      end

      it 'falls back to default Claims Evidence doctype when given invalid doctype' do
        expect(ce_uploader).to receive(:upload_evidence).with(
          claim.id,
          file_path: Rails.root.join(form_path).to_s,
          form_id: '28-1900',
          doctype: 1167
        ).and_return('uuid-001')

        claim.upload_to_vbms(user: upload_user, doc_type: 'invalid-doctype')
      end

      it 'falls back to send_to_lighthouse! on upload error' do
        allow(ce_uploader).to receive(:upload_evidence)
          .and_raise(StandardError, 'Claims Evidence API unavailable')
        expect(claim).to receive(:send_to_lighthouse!).with(upload_user)

        claim.upload_to_vbms(user: upload_user)
      end
    end
  end
end
