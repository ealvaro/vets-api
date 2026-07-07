# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

RSpec.describe ClaimsApi::V1::PoaFormBuilderJob, type: :job, vcr: 'bgs/person_web_service/find_by_ssn' do
  subject { described_class }

  let(:poa_code) { 'ABC' }
  let(:bad_b64_image) { File.read('modules/claims_api/spec/fixtures/signature_b64_prefix_bad.txt') }
  let(:b64_image) { File.read('modules/claims_api/spec/fixtures/signature_b64.txt') }
  let(:rep) do
    create(:representative, representative_id: '1234', poa_codes: [poa_code], first_name: 'Bob',
                            last_name: 'Representative')
  end
  let(:bd_client) { instance_double(ClaimsApi::BD) }

  let(:veteran_form_data) do
    {
      recordConsent: true,
      consentAddressChange: true,
      consentLimits: ['DRUG ABUSE', 'SICKLE CELL'],
      signatures: {
        veteran: b64_image,
        representative: b64_image
      },
      veteran: {
        serviceBranch: 'ARMY',
        address: {
          numberAndStreet: '2719 Hyperion Ave',
          city: 'Los Angeles',
          state: 'CA',
          country: 'US',
          zipFirstFive: '92264'
        },
        phone: {
          areaCode: '555',
          phoneNumber: '5551337'
        }
      },
      serviceOrganization: {
        poaCode: poa_code.to_s,
        organizationName: 'I Help Vets LLC',
        firstName: 'Bob',
        lastName: 'Law',
        address: {
          numberAndStreet: '123 East Main St',
          city: 'My City',
          state: 'ZZ',
          country: 'US',
          zipFirstFive: '12345'
        }
      }
    }
  end

  let(:claimant_form_data) do
    {
      claimant: {
        firstName: 'Lillian',
        middleInitial: 'A',
        lastName: 'Disney',
        dateOfBirth: '1985-07-04',
        email: 'lillian@disney.com',
        relationship: 'Spouse',
        address: {
          numberAndStreet: '2688 S Camino Real',
          city: 'Palm Springs',
          state: 'CA',
          country: 'US',
          zipFirstFive: '92264',
          zipLastFour: '9876'
        },
        phone: {
          areaCode: '555',
          phoneNumber: '5551337'
        }
      }
    }
  end

  let(:base_form_data) { veteran_form_data }
  let(:form_data_overrides) { {} }
  let(:form_data) { base_form_data.deep_merge(form_data_overrides) }

  let(:power_of_attorney) do
    create(:power_of_attorney, :with_full_headers, :pending).tap do |record|
      record.update!(form_data:)
    end
  end

  before do
    Sidekiq::Job.clear_all
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v1_2122a_pdf_form_update).and_return(false)
    allow_any_instance_of(ClaimsApi::V2::BenefitsDocuments::Service)
      .to receive(:get_auth_token).and_return('some-value-here')

    allow_any_instance_of(ClaimsApi::PoaAssignDependentClaimantJob)
      .to receive(:perform)
      .and_return(nil)

    allow_any_instance_of(ClaimsApi::PoaUpdater)
      .to receive(:perform)
      .and_return(nil)
  end

  describe 'with lighthouse_claims_api_2122_pdf_form_update_v1 feature flag disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122_pdf_form_update_v1).and_return(false)
    end

    describe 'generating the filled and signed pdf' do
      context 'when representative is an individual' do
        before do
          create(:veteran_representative, :with_address, representative_id: '12345', poa_codes: [poa_code.to_s])
        end

        it 'generates the pdf to match example' do
          allow(ClaimsApi::BD).to receive(:new).and_return(bd_client)
          allow(bd_client).to receive(:upload_document).and_return(true)
          allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })
          expect(ClaimsApi::V1::PoaPdfConstructor::Individual).to receive(:new).and_call_original
          expect_any_instance_of(ClaimsApi::V1::PoaPdfConstructor::Individual).to receive(:construct).and_call_original

          subject.new.perform(power_of_attorney.id, 'post')
        end
      end

      context 'when representative is part of an organization' do
        before do
          create(:veteran_representative, representative_id: '67890', poa_codes: [poa_code.to_s]).save!
          create(:veteran_organization, poa: 'ABC', name: 'Some org')
        end

        it 'generates the pdf to match example' do
          allow(ClaimsApi::BD).to receive(:new).and_return(bd_client)
          allow(bd_client).to receive(:upload_document).and_return(true)
          allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })
          expect(ClaimsApi::V1::PoaPdfConstructor::Organization).to receive(:new).and_call_original
          expect_any_instance_of(
            ClaimsApi::V1::PoaPdfConstructor::Organization
          ).to receive(:construct).and_call_original

          subject.new.perform(power_of_attorney.id, 'post')
        end
      end

      context 'when signature has prefix' do
        before do
          create(:veteran_representative, representative_id: '67890', poa_codes: ['ABC']).save!
          create(:veteran_organization, poa: 'ABC', name: 'Some org')
          power_of_attorney.update(form_data: power_of_attorney.form_data.deep_merge(
            {
              signatures: {
                veteran: bad_b64_image,
                representative: bad_b64_image
              }
            }
          ))
        end

        it 'sets the status and store the error' do
          expect_any_instance_of(ClaimsApi::V1::PoaPdfConstructor::Organization).to receive(:construct)
            .and_raise(ClaimsApi::StampSignatureError)

          subject.new.perform(power_of_attorney.id, 'post')

          power_of_attorney.reload
          expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
          expect(power_of_attorney.signature_errors).not_to be_empty
        end
      end
    end
  end

  describe 'with lighthouse_claims_api_2122a_pdf_form_update_v1 feature flag enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v1_2122a_pdf_form_update).and_return(true)
    end

    context 'when lighthouse_claims_api_v1_2122a_pdf_form_update is enabled' do
      it 'generates a 3-page PDF using the updated form' do
        allow(ClaimsApi::BD).to receive(:new).and_return(bd_client)
        allow(bd_client).to receive(:upload_document).and_return(true)
        allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })

        pdf_path = nil
        allow_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload) do |_instance, args|
          pdf_path = args[:pdf_path]
        end

        subject.new.perform(power_of_attorney.id, 'post')

        expect(pdf_path).to be_present
        expect(PDF::Reader.new(pdf_path).pages.size).to eq(3)
      end
    end
  end

  describe 'with lighthouse_claims_api_2122_pdf_form_update_v1 feature flag enabled' do
    let(:constructor) { ClaimsApi::V1::PoaPdfConstructor::Organization.new }
    let(:data) do
      power_of_attorney.form_data.deep_merge(
        {
          'veteran' => {
            'firstName' => power_of_attorney.auth_headers['va_eauth_firstName'],
            'lastName' => power_of_attorney.auth_headers['va_eauth_lastName'],
            'ssn' => power_of_attorney.auth_headers['va_eauth_pnid'],
            'birthdate' => power_of_attorney.auth_headers['va_eauth_birthdate']
          }
        }
      )
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_2122_pdf_form_update_v1).and_return(true)
      create(:veteran_representative, representative_id: '67890', poa_codes: [poa_code.to_s]).save!
      create(:veteran_organization, poa: poa_code.to_s, name: 'Some org')
      Timecop.freeze(Time.zone.parse('2026-06-25T08:00:00Z')) # freeze time for date field validations
    end

    after do
      Timecop.return
    end

    it 'uses the Organization constructor' do
      allow(ClaimsApi::BD).to receive(:new).and_return(bd_client)
      allow(bd_client).to receive(:upload_document).and_return(true)
      allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })
      expect(ClaimsApi::V1::PoaPdfConstructor::Organization).to receive(:new).and_call_original
      expect_any_instance_of(ClaimsApi::V1::PoaPdfConstructor::Organization).to receive(:construct).and_call_original

      subject.new.perform(power_of_attorney.id, 'post')
    end

    it 'uses revised page 2 signature coordinates' do
      signatures = constructor.send(:page2_signatures, data['signatures'])

      expect(signatures.map { |s| [s.x, s.y] }).to eq([[35, 328], [35, 281]])
    end

    it 'maps revised page 2 SSN and consent checkbox indexes correctly' do
      base_form = 'form1[0].#subform[1]'
      page2_options = constructor.send(:page2_options, data)

      expect(page2_options[:"#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]"]).to eq('796')
      expect(page2_options[:"#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]"]).to eq('37')
      expect(page2_options[:"#{base_form}.SocialSecurityNumber_LastFourNumbers[1]"]).to eq('8881')
      expect(page2_options[:"#{base_form}.I_Authorize[0]"]).to eq(1)
      expect(page2_options[:"#{base_form}.I_Authorize[1]"]).to eq(1)
      expect(page2_options).not_to have_key(:"#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]")
    end

    it 'uses revised date field names' do
      page1_base_form = 'form1[0].#subform[0]'
      page2_base_form = 'form1[0].#subform[1]'
      page1_options = constructor.send(:page1_options, data)
      page2_options = constructor.send(:page2_options, data)

      expect(page1_options[:"#{page1_base_form}.DateAppt[0]"]).to eq('06/25/2026')
      expect(page2_options[:"#{page2_base_form}.DateSigned[0]"]).to eq('06/25/2026')
      expect(page2_options[:"#{page2_base_form}.DateSigned[1]"]).to eq('06/25/2026')
      expect(page2_options).not_to have_key(:"#{page2_base_form}.Date_Signed[0]")
    end

    it 'uses revised veteran phone field name' do
      base_form = 'form1[0].#subform[0]'
      page1_options = constructor.send(:page1_options, data)

      expect(page1_options[:"#{base_form}.Phone[0]"]).to eq('555 5551337')
      expect(page1_options).not_to have_key(:"#{base_form}.TelephoneNumber_IncludeAreaCode[1]")
    end

    context 'when claimant information is present on form' do
      let(:base_form_data) { veteran_form_data.deep_merge(claimant_form_data) }

      it 'maps claimant date of birth fields on the revised form' do
        base_form = 'form1[0].#subform[0]'
        page1_options = constructor.send(:page1_options, data)

        expect(page1_options[:"#{base_form}.DOBmonth[1]"]).to eq('07')
        expect(page1_options[:"#{base_form}.DOBday[1]"]).to eq('04')
        expect(page1_options[:"#{base_form}.DOByear[1]"]).to eq('1985')
      end

      it 'maps claimant contact and zip last four fields on the revised form' do
        base_form = 'form1[0].#subform[0]'
        page1_options = constructor.send(:page1_options, data)

        expect(page1_options[:"#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]"]).to eq('9876')
        expect(page1_options[:"#{base_form}.Phone[1]"]).to eq('555 5551337')
        expect(page1_options[:"#{base_form}.EmailAddress_Optional[1]"]).to eq('lillian@disney.com')
      end
    end
  end

  describe 'POA update failures' do
    context 'when dependent claimant POA assignment fails' do
      before do
        power_of_attorney.update(
          auth_headers: power_of_attorney.auth_headers.merge(
            'dependent' => { 'claimant_participant_id' => '000000000000' }
          )
        )
      end

      it 'does not generate or upload the PDF' do
        expect_any_instance_of(ClaimsApi::PoaAssignDependentClaimantJob).to receive(:perform)
          .with(power_of_attorney.id).and_raise(Common::Exceptions::ServiceError)

        expect(ClaimsApi::V1::PoaPdfConstructor::Organization).not_to receive(:new)
        expect(ClaimsApi::V1::PoaPdfConstructor::Individual).not_to receive(:new)
        expect(ClaimsApi::PoaDocumentService).not_to receive(:new)

        expect { subject.new.perform(power_of_attorney.id, 'post', '2122') }
          .to raise_error(Common::Exceptions::ServiceError)

        power_of_attorney.reload
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
      end
    end

    context "when a veteran's update with PoaUpdater fails" do
      it 'does not generate or upload the PDF' do
        expect_any_instance_of(ClaimsApi::PoaUpdater).to receive(:perform)
          .with(power_of_attorney.id).and_raise(Common::Exceptions::ServiceError)

        expect(ClaimsApi::V1::PoaPdfConstructor::Organization).not_to receive(:new)
        expect(ClaimsApi::V1::PoaPdfConstructor::Individual).not_to receive(:new)
        expect(ClaimsApi::PoaDocumentService).not_to receive(:new)

        expect { subject.new.perform(power_of_attorney.id, 'post', '2122') }
          .to raise_error(Common::Exceptions::ServiceError)

        power_of_attorney.reload
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
      end
    end

    context 'when the veteran POA updater job fails to update via ManageRepresentativeService' do
      # enable flipper to hit the ManageRepresentativeService path
      before do
        allow(Flipper).to receive(:enabled?).with(:claims_api_use_update_poa_relationship).and_return(true)
      end

      it 'marks the power of attorney as errored and does not generate or upload the PDF' do
        # trigger POA update failure path in PoaUpdater
        allow_any_instance_of(ClaimsApi::ManageRepresentativeService)
          .to receive(:update_poa_relationship).and_return({})
        allow_any_instance_of(ClaimsApi::PoaUpdater).to receive(:find_by_ssn).and_return('123456789')
        allow_any_instance_of(ClaimsApi::PoaUpdater).to receive(:perform)
          .with(power_of_attorney.id).and_call_original

        # expect the PDF generation/upload to not occur
        expect(ClaimsApi::V1::PoaPdfConstructor::Organization).not_to receive(:new)
        expect(ClaimsApi::V1::PoaPdfConstructor::Individual).not_to receive(:new)
        expect(ClaimsApi::PoaDocumentService).not_to receive(:new)

        # expect the job to raise a ServiceError for Sidekiq retry and
        # for the error detail to be set from the PoaUpdater
        error = nil
        expect { subject.new.perform(power_of_attorney.id, 'post', '2122') }
          .to raise_error(Common::Exceptions::ServiceError) { |e| error = e }
        expect(error.errors.first.detail).to include('BGS Error: update_birls_record failed with code')

        # expect the POA to be marked as errored and the process to be failed
        power_of_attorney.reload
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
      end
    end
  end

  context 'when an errored job has exhausted its retries' do
    it 'logs to the ClaimsApi Logger' do
      error_msg = 'An error occurred for the POA Form Builder Job'
      msg = { 'args' => [power_of_attorney.id, 'value here'],
              'class' => subject,
              'error_message' => error_msg }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: power_of_attorney.id,
          message: "Job retries exhausted for #{subject}",
          error: error_msg
        )
      end
    end
  end

  context 'PoaDocumentService' do
    let(:errors) { 'some errors' }
    let(:pdf_path) { 'some/path' }
    let(:doc_type) { 'L075' }

    it 'calls the POA document service API upload' do
      expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload)

      subject.new.perform(power_of_attorney.id, 'post')
    end

    it 'calls the POA updater job upon successful upload' do
      allow(ClaimsApi::BD).to receive(:new).and_return(bd_client)
      allow(bd_client).to receive(:upload_document).and_return(true)
      allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })

      expect_any_instance_of(ClaimsApi::PoaUpdater).to receive(:perform).with(power_of_attorney.id)

      subject.new.perform(power_of_attorney.id, 'post')
    end

    context "when the 'put' action param is included" do
      it 'calls the PoaDocumentService upload_document instead of upload' do
        expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload).with(
          poa: power_of_attorney,
          pdf_path: anything,
          doc_type: 'L075',
          action: 'put'
        )

        subject.new.perform(power_of_attorney.id, 'put')
      end
    end

    context "when the 'post' action param is included" do
      it 'calls the PoaDocumentService upload_document instead of upload' do
        expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload).with(
          poa: power_of_attorney,
          pdf_path: anything,
          doc_type: 'L075',
          action: 'post'
        )

        subject.new.perform(power_of_attorney.id, 'post')
      end
    end

    it 'rescues errors from PoaDocumentService and sets the status to errored' do
      VCR.use_cassette('claims_api/bd/upload_error') do
        subject.new.perform(power_of_attorney.id, 'post')
      rescue
        power_of_attorney.reload
        expect(power_of_attorney.vbms_error_message).to eq(
          'BackendServiceException: {:status=>400, :detail=>nil, :code=>"VA900", :source=>nil}'
        )
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
      end
    end

    context 'when a generic exception occurs during upload' do
      before do
        allow_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload)
          .and_raise(StandardError, 'Upload failed')
      end

      it 'marks the power of attorney as errored and re-raises for retry' do
        expect { subject.new.perform(power_of_attorney.id, 'post') }
          .to raise_error(StandardError)

        power_of_attorney.reload
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
      end
    end

    it 'calls the PoaDocumentService' do
      expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload)

      subject.new.perform(power_of_attorney.id, 'post', '2122')
    end
  end
end
