# frozen_string_literal: true

require 'rails_helper'

require 'evss/disability_compensation_auth_headers' # required to build a Form526Submission
require 'evss/disability_compensation_form/form4142_processor'
require 'sidekiq/form526_backup_submission_process/submit'

RSpec.describe Sidekiq::Form526BackupSubmissionProcess::Processor do
  subject { described_class }

  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end

  before do
    allow_any_instance_of(BenefitsIntakeService::Utilities::ConvertToPdf)
      .to receive(:converted_filename)
      .and_return('tmp/converted_file.pdf')
  end

  context 'veteran with a foreign address' do
    describe 'submission and document metadata' do
      before do
        allow(Settings.form526_backup).to receive(:enabled).and_return(true)
      end

      let!(:submission) { create(:form526_submission, :with_non_us_address) }

      it 'sets the submission metadata zip code to a default value' do
        instance = subject.new(submission.id, get_upload_location_on_instantiation: false)
        expect(instance.zip).to eq('00000')
      end
    end
  end

  describe '#choose_provider' do
    let(:user) { create(:user, :loa3, :with_terms_of_use_agreement) }
    let(:user_account) { user.user_account }
    let(:icn) { user_account.icn }
    let(:submission) { create(:form526_submission, user_account:, submit_endpoint: 'claims_api') }

    it 'delegates to the ApiProviderFactory with the correct data' do
      auth_headers = {}
      expect(ApiProviderFactory).to receive(:call).with(
        {
          type: ApiProviderFactory::FACTORIES[:generate_pdf],
          provider: ApiProviderFactory::API_PROVIDER[:lighthouse],
          options: { auth_headers: },
          current_user: OpenStruct.new({ flipper_id: submission.user_uuid, icn: }),
          feature_toggle: nil
        }
      )

      subject
        .new(submission.id, get_upload_location_on_instantiation: false)
        .choose_provider(auth_headers, ApiProviderFactory::API_PROVIDER[:lighthouse])
    end

    describe '#get_uploads' do
      let!(:submission) { create(:form526_submission, :with_everything, user_account:) }
      let!(:upload_data) { submission.form[Form526Submission::FORM_526_UPLOADS] }
      let(:mock_random_file_path) { 'tmp/mock_random_file_path' }
      let(:mock_timestamp) { 1_234_567_890 }

      before do
        allow(Common::FileHelpers).to receive(:random_file_path).and_return(mock_random_file_path)
        upload_data.each do |ud|
          filename = ud['name']
          file_path = Rails.root.join('spec', 'fixtures', 'files', filename)
          file = Rack::Test::UploadedFile.new(file_path, 'application/pdf')
          sea = SupportingEvidenceAttachment.find_or_create_by(guid: ud['confirmationCode'])
          sea.set_file_data!(file)
          sea.save!
        end
      end

      it 'calls process with correct filename path' do
        VCR.use_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload_location') do
          VCR.use_cassette('lighthouse/benefits_claims/submit526/200_response_generate_pdf') do
            VCR.use_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload') do
              processor = described_class.new(submission.id)
              processed_files = processor.get_uploads
              processed_files.each do |processed_file|
                # Filenames are shortened at upload time by SupportingEvidenceAttachmentUploader,
                # and the resulting filename (path component) should be reasonably short (<= 255 characters).
                expect(processed_file[:file]).to match(%r{^tmp/.+\.pdf$})
                expect(File.basename(processed_file[:file]).length).to be <= 255
              end
            end
          end
        end
      end

      context 'when uploads have long original filenames that were shortened' do
        let(:long_filename) { "#{'a' * 200}.pdf" }

        before do
          # Override the first upload with a long filename
          first_upload = upload_data.first
          fixture_file_path = Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf')
          file = Rack::Test::UploadedFile.new(fixture_file_path, 'application/pdf')
          allow(file).to receive(:original_filename).and_return(long_filename)

          sea = SupportingEvidenceAttachment.find_by(guid: first_upload['confirmationCode'])
          sea.set_file_data!(file)
          sea.save!
        end

        it 'retrieves files without ENAMETOOLONG error' do
          VCR.use_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload_location') do
            VCR.use_cassette('lighthouse/benefits_claims/submit526/200_response_generate_pdf') do
              VCR.use_cassette('lighthouse/benefits_intake/200_lighthouse_intake_upload') do
                processor = described_class.new(submission.id)
                expect { processor.get_uploads }.not_to raise_error
              end
            end
          end
        end
      end
    end

    it 'pulls the 526 PDF from the Lighthouse generate_pdf provider' do
      allow_any_instance_of(LighthouseGeneratePdfProvider).to receive(:generate_526_pdf)
        .and_return(Faraday::Response.new(
                      status: 200, body: '526pdf'
                    ))

      expect(ApiProviderFactory).to receive(:call).with(
        {
          type: ApiProviderFactory::FACTORIES[:generate_pdf],
          provider: ApiProviderFactory::API_PROVIDER[:lighthouse],
          options: { auth_headers: submission.auth_headers },
          current_user: OpenStruct.new({ flipper_id: submission.user_uuid, icn: }),
          feature_toggle: nil
        }
      ).and_call_original

      subject
        .new(submission.id, get_upload_location_on_instantiation: false)
        .get_form526_pdf
    end

    describe '#get_form526_pdf claimDate handling' do
      let(:created_at_time) { Time.zone.local(2023, 7, 15, 14, 30, 0) }
      let(:submission_with_claim_date) { create(:form526_submission, :with_everything, user_account:) }
      let(:submission_without_claim_date) { create(:form526_submission, user_account:) }
      let!(:captured_form_json) { {} }

      before do
        # Mock the response so we don't make actual API calls
        klass = LighthouseGeneratePdfProvider
        allow_any_instance_of(klass).to receive(:generate_526_pdf) do |_instance, form_json, _transaction_id|
          # Capture the form_json that's being sent (mutate the existing hash rather than reassigning)
          captured_form_json.replace(JSON.parse(form_json))
          Faraday::Response.new(status: 200, body: '526pdf')
        end
      end

      context 'when submission has no claimDate in the form' do
        it 'sets claimDate to the formatted submission created_at date' do
          # Set the created_at time for the submission
          submission_without_claim_date.update!(created_at: created_at_time)

          processor = subject.new(submission_without_claim_date.id, get_upload_location_on_instantiation: false)
          processor.get_form526_pdf

          # Verify claimDate was set to the formatted created_at date
          expect(captured_form_json['form526']['claimDate']).to eq('2023-07-15')
        end
      end

      context 'when submission has nil claimDate in the form' do
        it 'sets claimDate to the formatted submission created_at date' do
          # Modify the form to have nil claimDate
          form_data = JSON.parse(submission_with_claim_date.form_json)
          form_data['form526']['claimDate'] = nil
          submission_with_claim_date.update!(
            form_json: form_data.to_json,
            created_at: created_at_time
          )

          processor = subject.new(submission_with_claim_date.id, get_upload_location_on_instantiation: false)
          processor.get_form526_pdf

          # Verify claimDate was set to the formatted created_at date
          expect(captured_form_json['form526']['claimDate']).to eq('2023-07-15')
        end
      end

      context 'when submission has empty string claimDate in the form' do
        it 'sets claimDate to the formatted submission created_at date' do
          # Modify the form to have empty claimDate
          form_data = JSON.parse(submission_with_claim_date.form_json)
          form_data['form526']['claimDate'] = ''
          submission_with_claim_date.update!(
            form_json: form_data.to_json,
            created_at: created_at_time
          )

          processor = subject.new(submission_with_claim_date.id, get_upload_location_on_instantiation: false)
          processor.get_form526_pdf

          # Verify claimDate was set to the formatted created_at date
          expect(captured_form_json['form526']['claimDate']).to eq('2023-07-15')
        end
      end

      it 'formats the submission created_at date as YYYY-MM-DD' do
        # Test different created_at dates to ensure proper formatting
        test_dates = [
          Time.zone.local(2023, 1, 1),    # New Year's Day
          Time.zone.local(2023, 12, 31),  # New Year's Eve
          Time.zone.local(2023, 2, 28),   # End of February (non-leap year)
          Time.zone.local(2024, 2, 29)    # Leap year February 29th
        ]

        expected_formats = %w[2023-01-01 2023-12-31 2023-02-28 2024-02-29]

        test_dates.each_with_index do |test_date, index|
          submission_without_claim_date.update!(created_at: test_date)

          processor = subject.new(submission_without_claim_date.id, get_upload_location_on_instantiation: false)
          processor.get_form526_pdf

          expect(captured_form_json['form526']['claimDate']).to eq(expected_formats[index])
        end
      end
    end
  end

  describe '#get_form0781_pdf' do
    context 'generates a 0781 version 1 pdf' do
      let(:submission) { create(:form526_submission, :with_0781, submit_endpoint: 'benefits_intake_api') } # rubocop:disable Naming/VariableNumber

      it 'generates a 0781 v1 pdf and a 0781a pdf' do
        form0781_pdfs = subject
                        .new(submission.id, get_upload_location_on_instantiation: false)
                        .get_form0781_pdf
        expect(form0781_pdfs.count).to eq(2)
        expect(form0781_pdfs.first[:type]).to eq('21-0781')
        expect(form0781_pdfs.last[:type]).to eq('21-0781a')
      end
    end

    context 'generates a 0781 version 2 pdf' do
      let(:submission) { create(:form526_submission, :with_0781v2, submit_endpoint: 'benefits_intake_api') }

      it 'generates a 0781 v2 pdf' do
        form0781_pdfs = subject
                        .new(submission.id, get_upload_location_on_instantiation: false)
                        .get_form0781_pdf
        expect(form0781_pdfs.count).to eq(1)
        expect(form0781_pdfs.first[:type]).to eq('21-0781V2')
      end
    end
  end

  describe '#determine_zip' do
    let(:submission_base) { create(:form526_submission) }

    context 'with a US address with both zip5 and zip4' do
      let(:submission) { create(:form526_submission, :with_everything) }

      it 'returns zip5-zip4 formatted string' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        expect(processor.zip).to eq('12345-6789')
      end
    end

    context 'with a US address with zip5 only' do
      let(:submission) do
        form = JSON.parse(
          Rails.root.join('spec', 'support', 'disability_compensation_form', 'submissions', 'only_526.json').read
        )
        form['form526']['form526']['veteran']['currentMailingAddress'] = {
          'country' => 'USA',
          'addressLine1' => '123 Main St',
          'city' => 'Springfield',
          'state' => 'IL',
          'zipFirstFive' => '62701'
        }
        create(:form526_submission, form_json: form.to_json)
      end

      it 'returns only the zip5' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        expect(processor.zip).to eq('62701')
      end
    end

    context 'with no mailing address' do
      it 'returns the default zip code' do
        processor = subject.new(submission_base.id, get_upload_location_on_instantiation: false)
        expect(processor.zip).to eq('00000')
      end
    end
  end

  describe '#bdd?' do
    context 'when the submission is BDD qualified' do
      let(:submission) { create(:form526_submission, :without_diagnostic_code) }

      it 'returns true' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        expect(processor.bdd?).to be true
      end
    end

    context 'when the submission is not BDD qualified' do
      let(:submission) { create(:form526_submission) }

      it 'returns false' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        expect(processor.bdd?).to be false
      end
    end
  end

  describe '#write_to_tmp_file' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'writes binary content to a tmp file with a .pdf extension by default' do
      path = processor.write_to_tmp_file('binary content')
      expect(path).to match(/\.pdf$/)
      expect(File.read(path)).to eq('binary content')
    ensure
      FileUtils.rm_f(path)
    end

    it 'respects a custom file extension' do
      path = processor.write_to_tmp_file('data', 'txt')
      expect(path).to match(/\.txt$/)
    ensure
      FileUtils.rm_f(path)
    end
  end

  describe '#upload_location_to_location_and_uuid' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'extracts uuid and location from a lighthouse upload response' do
      response = { 'data' => { 'id' => 'abc-123', 'attributes' => { 'location' => 'https://example.com/upload' } } }
      result = processor.upload_location_to_location_and_uuid(response)
      expect(result).to eq({ uuid: 'abc-123', location: 'https://example.com/upload' })
    end
  end

  describe '#received_date' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'returns the saved claim created_at formatted in Central Time' do
      fixed_time = Time.zone.parse('2024-06-15 18:00:00 UTC')
      submission.saved_claim.update!(created_at: fixed_time)
      # 18:00 UTC = 13:00 CDT (UTC-5)
      expect(processor.received_date).to match(/\A2024-06-15 \d{2}:\d{2}:\d{2}\z/)
    end
  end

  describe '#evidence_526_split' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'separates 526 and evidence docs from other docs' do
      processor.docs = [
        { type: '21-526EZ', file: 'a.pdf' },
        { type: 'evidence', file: 'b.pdf' },
        { type: '21-4142', file: 'c.pdf' }
      ]
      initial, other = processor.evidence_526_split
      expect(initial.map { |d| d[:type] }).to contain_exactly('21-526EZ', 'evidence')
      expect(other.map { |d| d[:type] }).to contain_exactly('21-4142')
    end
  end

  describe '#generate_attachments' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'returns evidence files unchanged when other_payloads is nil' do
      evidence = [{ file: 'a.pdf', file_name: 'evidence_1.pdf' }]
      expect(processor.generate_attachments(evidence, nil)).to eq(evidence)
    end

    it 'appends other_payload pdfs to evidence files' do
      evidence = [{ file: 'a.pdf', file_name: 'evidence_1.pdf' }]
      other = [{ file: 'b.pdf', metadata: { docType: '21-4142' } }]
      result = processor.generate_attachments(evidence, other)
      expect(result.length).to eq(2)
      expect(result.last[:file_name]).to eq('21-4142.pdf')
    end
  end

  describe '#get_meta_data' do
    let(:submission) { create(:form526_submission, :with_everything) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    before do
      allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate) { |m| m }
    end

    it 'returns a metadata hash with expected keys and values' do
      metadata = processor.get_meta_data('21-526EZ')
      expect(metadata['source']).to eq('va.gov backup submission')
      expect(metadata['docType']).to eq('21-526EZ')
      expect(metadata['businessLine']).to eq('CMP')
      expect(metadata['forceOfframp']).to eq('true')
      expect(metadata['zipCode']).to eq(processor.zip)
    end

    it 'delegates to MetadataValidator' do
      expect(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate)
      processor.get_meta_data('21-526EZ')
    end
  end

  describe '#get_form4142_pdf' do
    let(:submission) { create(:form526_submission, :with_everything) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }
    let(:mock_processor) { double('Form4142Processor', pdf_path: 'tmp/4142.pdf') }

    it 'adds a form4142 doc to docs' do
      allow(EVSS::DisabilityCompensationForm::Form4142Processor).to receive(:new).and_return(mock_processor)
      processor.get_form4142_pdf
      expect(processor.docs).to include(a_hash_including(type: '21-4142', file: 'tmp/4142.pdf'))
    end
  end

  describe '#get_form8940_pdf' do
    let(:submission) { create(:form526_submission, :with_everything) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }
    let(:mock_doc) { { type: '21-8940', file: 'tmp/8940.pdf' } }

    it 'adds a form8940 doc to docs' do
      allow_any_instance_of(EVSS::DisabilityCompensationForm::SubmitForm8940).to receive(:get_docs).and_return(mock_doc)
      processor.get_form8940_pdf
      expect(processor.docs).to include(a_hash_including(type: '21-8940'))
    end
  end

  describe '#get_bdd_pdf' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }

    it 'adds the BDD instructions PDF to docs' do
      processor.get_bdd_pdf
      expect(processor.docs).to include(a_hash_including(type: 'bdd'))
      expect(processor.docs.last[:file]).to include('bdd_instructions.pdf')
    end
  end

  describe '#convert_doc_to_pdf' do
    let(:submission) { create(:form526_submission) }
    let(:processor) { subject.new(submission.id, get_upload_location_on_instantiation: false) }
    let(:klass) { BenefitsIntakeService::Utilities::ConvertToPdf }

    before do
      allow(processor.lighthouse_service).to receive(:get_file_path_from_objs) { |f| f }
    end

    context 'when the file type is convertible' do
      it 'replaces doc[:file] with the converted filename' do
        # .jpg IS in CAN_CONVERT so the conversion branch executes naturally.
        # Stub klass.new to avoid MiniMagick actually running (no test file on disk).
        doc = { file: 'tmp/test.jpg', type: '21-526EZ' }
        converter = double('ConvertToPdf', converted_filename: 'tmp/converted_file.pdf')
        allow(klass).to receive(:new).with('tmp/test.jpg').and_return(converter)
        processor.convert_doc_to_pdf(doc, klass)
        expect(doc[:file]).to eq('tmp/converted_file.pdf')
      end
    end

    context 'when the file type is not convertible' do
      it 'leaves doc[:file] unchanged' do
        # .pdf is NOT in CAN_CONVERT, so no conversion happens naturally
        doc = { file: 'tmp/test.pdf', type: '21-526EZ' }
        processor.convert_doc_to_pdf(doc, klass)
        expect(doc[:file]).to eq('tmp/test.pdf')
      end
    end
  end

  describe '#gather_docs!' do
    let(:mock_lh_service) { instance_double(Form526BackupSubmission::Service) }
    let(:fake_pdf_resp) { double('Faraday::Response', env: double('Faraday::Env', response_body: '%PDF')) }

    before do
      allow(Form526BackupSubmission::Service).to receive(:new).and_return(mock_lh_service)
      allow(mock_lh_service).to receive(:get_file_path_from_objs) { |f| f }
    end

    context 'with only a 526 form' do
      let(:submission) { create(:form526_submission) }
      let(:mock_pdf_provider) { instance_double(LighthouseGeneratePdfProvider) }

      before do
        allow(ApiProviderFactory).to receive(:call).and_return(mock_pdf_provider)
        allow(mock_pdf_provider).to receive(:generate_526_pdf).and_return(fake_pdf_resp)
        allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate) { |m| m }
      end

      it 'only adds the 526 doc and sets docs_gathered' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        processor.gather_docs!
        expect(processor.docs.map { |d| d[:type] }).to contain_exactly('21-526EZ')
        expect(processor.docs_gathered).to be true
      end
    end

    context 'with BDD-qualified submission' do
      let(:submission) { create(:form526_submission, :without_diagnostic_code) }
      let(:mock_pdf_provider) { instance_double(LighthouseGeneratePdfProvider) }

      before do
        allow(ApiProviderFactory).to receive(:call).and_return(mock_pdf_provider)
        allow(mock_pdf_provider).to receive(:generate_526_pdf).and_return(fake_pdf_resp)
        # 526_bdd.json includes uploads/0781/8940/4142 — stub them all out since we're only testing BDD doc addition
        allow_any_instance_of(described_class).to receive(:get_uploads)
        allow_any_instance_of(EVSS::DisabilityCompensationForm::SubmitForm0781).to receive(:get_docs).and_return([])
        allow_any_instance_of(EVSS::DisabilityCompensationForm::SubmitForm8940).to receive(:get_docs).and_return(
          { type: '21-8940', file: 'tmp/8940.pdf' }
        )
        allow_any_instance_of(EVSS::DisabilityCompensationForm::Form4142Processor)
          .to receive(:pdf_path).and_return('tmp/4142.pdf')
        allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate) { |m| m }
      end

      it 'includes the BDD instructions doc' do
        processor = subject.new(submission.id, get_upload_location_on_instantiation: false)
        processor.gather_docs!
        expect(processor.docs.map { |d| d[:type] }).to include('bdd')
      end
    end
  end

  describe '#submit_as_one' do
    let(:submission) { create(:form526_submission) }
    let(:mock_lh_service) { instance_double(Form526BackupSubmission::Service) }
    let(:processor) do
      allow(Form526BackupSubmission::Service).to receive(:new).and_return(mock_lh_service)
      allow(mock_lh_service).to receive(:get_location_and_uuid).and_return({ uuid: 'test-uuid',
                                                                             location: 'https://example.com' })
      subject.new(submission.id)
    end
    let(:form526_doc) { { type: '21-526EZ', file: 'tmp/526.pdf', metadata: { 'docType' => '21-526EZ' } } }
    let(:evidence_doc) { { type: 'evidence', file: 'tmp/evidence.pdf', metadata: { 'docType' => 'evidence' } } }
    let(:ancillary_doc) { { type: '21-4142', file: 'tmp/4142.pdf', metadata: { docType: '21-4142' } } }

    context 'when return_docs_instead_of_sending is false' do
      it 'uploads to lighthouse and updates submission' do
        allow(mock_lh_service).to receive(:upload_doc)
        processor.docs = [form526_doc]
        processor.submit_as_one([form526_doc])
        expect(mock_lh_service).to have_received(:upload_doc)
        expect(submission.reload.backup_submitted_claim_id).to eq('test-uuid')
      end
    end

    context 'when return_docs_instead_of_sending is true' do
      it 'returns upload params instead of submitting' do
        expected_params = { main_document: 'params', attachments: [] }
        allow(mock_lh_service).to receive(:get_upload_docs).and_return(expected_params)
        expect(mock_lh_service).not_to receive(:upload_doc)
        result = processor.submit_as_one([form526_doc], nil, return_docs_instead_of_sending: true)
        expect(result).to eq(expected_params)
      end
    end
  end

  describe '#send_to_central_mail_through_lighthouse_claims_intake_api!' do
    let(:submission) { create(:form526_submission) }
    let(:mock_lh_service) { instance_double(Form526BackupSubmission::Service) }
    let(:processor) do
      allow(Form526BackupSubmission::Service).to receive(:new).and_return(mock_lh_service)
      allow(mock_lh_service).to receive(:get_location_and_uuid).and_return({ uuid: 'test-uuid',
                                                                             location: 'https://example.com' })
      p = subject.new(submission.id)
      p.docs = [{ type: '21-526EZ', file: 'tmp/526.pdf', metadata: { 'docType' => '21-526EZ' } }]
      p
    end

    context 'in :single submission mode' do
      it 'calls submit_as_one' do
        allow(mock_lh_service).to receive(:upload_doc)
        expect(processor).to receive(:submit_as_one).and_call_original
        processor.send_to_central_mail_through_lighthouse_claims_intake_api!
      end
    end
  end

  describe '#process!' do
    let(:submission) { create(:form526_submission) }
    let(:mock_lh_service) { instance_double(Form526BackupSubmission::Service) }
    let(:processor) do
      allow(Form526BackupSubmission::Service).to receive(:new).and_return(mock_lh_service)
      allow(mock_lh_service).to receive(:get_location_and_uuid).and_return({ uuid: 'test-uuid',
                                                                             location: 'https://example.com' })
      subject.new(submission.id)
    end

    it 'calls gather_docs! then sends to lighthouse' do
      fake_pdf_resp = double('Faraday::Response', env: double('Faraday::Env', response_body: '%PDF'))
      expect(processor).to receive(:gather_docs!).and_call_original
      expect(processor).to receive(:send_to_central_mail_through_lighthouse_claims_intake_api!).and_call_original
      allow(mock_lh_service).to receive(:upload_doc)
      allow_any_instance_of(LighthouseGeneratePdfProvider).to receive(:generate_526_pdf).and_return(fake_pdf_resp)
      allow(mock_lh_service).to receive(:get_file_path_from_objs) { |f| f }
      allow(SimpleFormsApiSubmission::MetadataValidator).to receive(:validate) { |m| m }
      processor.process!
    end

    it 'does not call gather_docs! if docs were already gathered' do
      allow(processor).to receive(:send_to_central_mail_through_lighthouse_claims_intake_api!)
      processor.instance_variable_set(:@docs_gathered, true)
      expect(processor).not_to receive(:gather_docs!)
      processor.process!
    end
  end
end
