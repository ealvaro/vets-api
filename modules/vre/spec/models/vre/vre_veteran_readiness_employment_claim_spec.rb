# frozen_string_literal: true

require 'rails_helper'
require './modules/claims_api/spec/support/fake_vbms'
require './modules/claims_evidence_api/lib/claims_evidence_api/uploader'

RSpec.describe VRE::VREVeteranReadinessEmploymentClaim do
  let(:claim) { create(:vre_veteran_readiness_employment_claim) }
  let(:user_object) { create(:evss_user, :loa3) }
  let(:new_address_hash) do
    {
      newAddress: {
        isForeign: false,
        isMilitary: nil,
        countryName: 'USA',
        addressLine1: '1019 Robin Cir',
        addressLine2: nil,
        addressLine3: nil,
        city: 'Arroyo Grande',
        province: 'CA',
        internationalPostalCode: '93420'
      }
    }
  end
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

  before do
    allow_any_instance_of(VRE::Ch31Form).to receive(:submit).and_return(true)
  end

  it 'includes VREClaimsEvidenceUpload' do
    expect(described_class.ancestors).to include(VREClaimsEvidenceUpload)
  end

  describe '#add_claimant_info' do
    it 'adds veteran information' do
      claim.add_claimant_info(user_object)
      claimant_keys = %w[fullName dob pid edipi vet360ID regionalOffice regionalOfficeName stationId VAFileNumber ssn]
      expect(claim.parsed_form['veteranInformation']).to include(
        {
          'fullName' => {
            'first' => 'Homer',
            'middle' => 'John',
            'last' => 'Simpson'
          },
          'dob' => '1986-05-06'
        }
      )

      expect(claim.parsed_form['veteranInformation']).to include(*claimant_keys)
    end

    it 'does not obtain va_file_number' do
      claim.add_claimant_info(user_object)
      expect(claim.parsed_form['veteranInformation']).to include('VAFileNumber' => nil)
    end

    it 'handles blank form' do
      claim.form = nil
      expect(Rails.logger).to receive(:info)
        .with('VRE claim form is blank, skipping adding veteran info', { user_uuid: user.uuid })
      expect(claim.add_claimant_info(user)).to be_nil
    end
  end

  describe '#send_to_vre' do
    subject { claim.send_to_vre(user_object) }

    before do
      # TODO(02/2026): Remove stub when VRE::NotificationEmail uses VRE::VREVeteranReadinessEmploymentClaim
      # See: https://va.ghe.com/software/va-iir/issues/2011
      allow_any_instance_of(VRE::NotificationEmail).to receive(:claim_class)
        .and_return(VRE::VREVeteranReadinessEmploymentClaim)
    end

    it 'propagates errors from send_to_lighthouse!' do
      allow(claim).to receive(:process_attachments!).and_raise(StandardError, 'Attachment error')

      expect do
        claim.send_to_lighthouse!(user_object)
      end.to raise_error(StandardError, 'Attachment error')
    end

    context 'when VBMS response is VBMSDownForMaintenance' do
      before do
        allow(OpenSSL::PKCS12).to receive(:new).and_return(double.as_null_object)
        vbms_client = FakeVBMS.new
        allow(VBMS::Client).to receive(:from_env_vars).and_return(vbms_client)
      end

      it 'calls #send_to_lighthouse!' do
        expect(claim).to receive(:send_to_lighthouse!)
        subject
      end

      it 'does not raise an error' do
        allow(claim).to receive(:send_to_lighthouse!)
        expect { subject }.not_to raise_error
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
          # modules/vre/app/models/vre/constants.rb gets changed, you
          # may need to change this mock below and maybe even move it into different 'it'
          # blocks if you need to test different routing offices
          expect_any_instance_of(BGS::RORoutingService).to receive(:get_regional_office_by_zip_code).and_return(
            { regional_office: { number: '325' } }
          )
        end

        it 'sends confirmation email' do
          expect(claim).to receive(:send_email).with(:confirmation_vbms)

          claim.send_to_vre(user_object)
        end
      end

      # We want all submission to go through with RES
      context 'non-submission to VRE' do
        it 'stops submission if location is not in list' do
          expect_any_instance_of(VRE::Ch31Form).to receive(:submit)
          claim.add_claimant_info(user_object)

          claim.send_to_vre(user_object)
        end
      end
    end

    context 'when user has no participant ID' do
      let(:user_object) { create(:unauthorized_evss_user) }

      it 'PDF is sent to Central Mail and not VBMS' do
        expect(claim).to receive(:process_attachments!)
        expect(claim).to receive(:send_to_lighthouse!).with(user_object).once.and_call_original
        expect(claim).to receive(:send_email).with(:confirmation_lighthouse)
        expect(claim).not_to receive(:upload_to_vbms)
        expect(VRE::VeteranReadinessEmploymentMailer).to receive(:build).with(
          user_object.participant_id, 'VRE.VBAPIT@va.gov', true
        ).and_call_original
        subject
      end
    end
  end

  describe '#regional_office' do
    it 'returns an empty array' do
      expect(claim.regional_office).to eq []
    end
  end

  describe '#process_attachments!' do
    it 'processes attachments successfully' do
      allow(claim).to receive_messages(
        attachment_keys: ['some_key'],
        open_struct_form: OpenStruct.new(some_key: [OpenStruct.new(confirmationCode: '123')])
      )
      allow(PersistentAttachment).to receive(:where).and_return(double(find_each: true))
      allow_any_instance_of(Lighthouse::SubmitBenefitsIntakeClaim).to receive(:perform).and_return(true)
      expect(claim.process_attachments!).to be_truthy
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
      before { allow(Flipper).to receive(:enabled?).with(:vre_use_claims_evidence_api).and_return(false) }

      context 'when veteran identitifer missing' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => nil, 'ssn' => nil)
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs error with correct service name and error class' do
          allow(Rails.logger).to receive(:error)
          claim.upload_to_vbms(user: upload_user)
          expect(Rails.logger).to have_received(:error).with(
            'VRE modular claim: error uploading to VBMS, falling back to Lighthouse/CMP',
            {
              user_uuid: upload_user.uuid,
              error_class: 'RuntimeError',
              message: 'SSN or VA File Number required'
            }
          )
        end
      end

      context 'when veteran identifier format is invalid' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => 'BAD-ID', 'ssn' => '1234')
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs invalid identifier details with error class' do
          allow(Rails.logger).to receive(:error)
          expected_message = 'Invalid veteran identifiers: SSN must be 9 digits; ' \
                             'VA File Number must be 7-9 digits with optional leading C'
          claim.upload_to_vbms(user: upload_user)
          expect(Rails.logger).to have_received(:error).with(
            'VRE modular claim: error uploading to VBMS, falling back to Lighthouse/CMP',
            {
              user_uuid: upload_user.uuid,
              error_class: 'RuntimeError',
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

      it 'falls back to send_to_lighthouse! on upload error' do
        allow_any_instance_of(ClaimsApi::VBMSUploader).to receive(:upload!)
          .and_raise(StandardError, 'VBMS unavailable')
        expect(claim).to receive(:send_to_lighthouse!).with(upload_user)

        claim.upload_to_vbms(user: upload_user)
      end
    end

    context 'when vre_use_claims_evidence_api flipper is enabled' do
      let(:ce_uploader) { instance_double(ClaimsEvidenceApi::Uploader) }

      before do
        allow(Flipper).to receive(:enabled?).with(:vre_use_claims_evidence_api).and_return(true)
        allow(ClaimsEvidenceApi::Uploader).to receive(:new).and_return(ce_uploader)
        allow(ce_uploader).to receive(:upload_evidence).and_return('uuid-001')
        # Stub folder lookup to succeed by default (simulates folder exists in Claims Evidence)
        allow_any_instance_of(ClaimsEvidenceApi::Service::Search).to receive(:find).and_return({})
      end

      context 'when Claims Evidence folder is not found' do
        before do
          allow(claim).to receive(:claims_evidence_folder_exists?).and_return(false)
        end

        it 'falls back to legacy VBMS instead of routing to Lighthouse/CMP' do
          vbms_uploader = instance_double(ClaimsApi::VBMSUploader)
          allow(vbms_uploader).to receive(:upload!).and_return({ vbms_document_series_ref_id: 'DOC-001' })
          allow(ClaimsApi::VBMSUploader).to receive(:new).and_return(vbms_uploader)

          expect(claim).not_to receive(:send_to_lighthouse!)
          claim.upload_to_vbms(user: upload_user)
        end

        it 'logs the fallback to legacy VBMS' do
          allow(ClaimsApi::VBMSUploader).to receive(:new)
            .and_return(instance_double(ClaimsApi::VBMSUploader, upload!: { vbms_document_series_ref_id: 'X' }))
          expect(Rails.logger).to receive(:warn)
            .with('Claims Evidence API folder not found for VRE claim, falling back to legacy VBMS', anything)
          claim.upload_to_vbms(user: upload_user)
        end
      end

      context 'when veteran identitifer missing' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => nil, 'ssn' => nil)
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs error with correct service name and error class' do
          allow(Rails.logger).to receive(:error)
          claim.upload_to_vbms(user: upload_user)
          expect(Rails.logger).to have_received(:error).with(
            'VRE modular claim: error uploading to Claims Evidence API, falling back to Lighthouse/CMP',
            {
              user_uuid: upload_user.uuid,
              error_class: 'RuntimeError',
              message: 'SSN or VA File Number required'
            }
          )
        end
      end

      context 'when veteran identifier format is invalid' do
        before do
          base_parsed_form['veteranInformation'].merge!('VAFileNumber' => 'BAD-ID', 'ssn' => '1234')
          allow(claim).to receive(:send_to_lighthouse!).and_return(nil)
        end

        it 'logs invalid identifier details with error class' do
          allow(Rails.logger).to receive(:error)
          expected_message = 'Invalid veteran identifiers: SSN must be 9 digits; ' \
                             'VA File Number must be 7-9 digits with optional leading C'
          claim.upload_to_vbms(user: upload_user)
          expect(Rails.logger).to have_received(:error).with(
            'VRE modular claim: error uploading to Claims Evidence API, falling back to Lighthouse/CMP',
            {
              user_uuid: upload_user.uuid,
              error_class: 'RuntimeError',
              message: expected_message
            }
          )
        end
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

      it 'calls upload_evidence with integer doctype' do
        expect(ce_uploader).to receive(:upload_evidence).with(
          claim.id,
          file_path: Rails.root.join(form_path).to_s,
          form_id: '28-1900',
          doctype: 1167
        ).and_return('uuid-001')

        claim.upload_to_vbms(user: upload_user)
      end

      it 'falls back to send_to_lighthouse! on upload error' do
        allow(ce_uploader).to receive(:upload_evidence)
          .and_raise(StandardError, 'Claims Evidence API unavailable')
        expect(claim).to receive(:send_to_lighthouse!).with(upload_user)

        claim.upload_to_vbms(user: upload_user)
      end
    end
  end

  describe '#log_to_statsd' do
    it 'measures response time on success' do
      expect(StatsD).to receive(:measure).with('api.1900.vbms.response_time', anything, tags: {})
      claim.send(:log_to_statsd, 'vbms') { :ok }
    end

    it 'increments error metric and re-raises on failure' do
      allow(StatsD).to receive(:increment)
      expect do
        claim.send(:log_to_statsd, 'vbms') { raise StandardError, 'upload failed' }
      end.to raise_error(StandardError, 'upload failed')
      expect(StatsD).to have_received(:increment).with('api.1900.vbms.error')
    end
  end
end
