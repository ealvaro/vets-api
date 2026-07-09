# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

RSpec.describe 'IvcChampva::V1::Uploads — 10-10D supplemental docs-only resubmission',
               type: :request do
  let(:confirmation_code) { 'a1111111-b222-c333-d444-e55555555555' }

  let(:base_payload) do
    {
      'form_number' => '10-10D-SUPPLEMENTAL',
      'submission_type' => 'existing',
      'certifier_role' => 'sponsor',
      'veteran' => {
        'full_name' => { 'first' => 'Pat', 'middle' => 'T', 'last' => 'Veteran', 'suffix' => '' },
        'ssn_or_tin' => '411111111',
        'date_of_birth' => '01-01-1958'
      },
      'applicants' => [
        {
          'applicant_name' => { 'first' => 'Sam', 'middle' => 'T', 'last' => 'Beneficiary', 'suffix' => 'Jr.' },
          'applicant_dob' => '01-04-2003',
          'applicant_member_number' => '345345345'
        }
      ],
      'primary_contact_info' => {
        'email' => 'pat@example.com',
        'name' => { 'first' => 'Pat', 'last' => 'Contact' }
      },
      'supporting_docs' => [
        {
          'confirmation_code' => confirmation_code,
          'attachment_id' => 'Birth certificate',
          'name' => 'doc.pdf',
          'is_encrypted' => false
        }
      ],
      'certification' => { 'date' => '04-01-2026' },
      'statement_of_truth_signature' => 'Certifier Jones'
    }
  end

  let(:enrollment_payload) do
    base_payload.merge(
      'submission_type' => 'enrollment',
      'certifier_role' => 'applicant',
      'veteran' => {
        'full_name' => {},
        'ssn_or_tin' => '',
        'date_of_birth' => ''
      },
      'primary_contact_info' => {
        'email' => 'sam@example.com',
        'name' => { 'first' => 'Sam', 'last' => 'Beneficiary' }
      }
    )
  end

  let(:merged_route) { '/ivc_champva/v1/forms/10-10d-ext' }

  before do
    @original_aws_config = Aws.config.dup
    Aws.config.update(stub_responses: true)

    tempfile = Tempfile.new(['ivc_enhanced_spec_supporting', '.pdf'])
    FileUtils.cp(
      Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'pdfs', 'pdf_with_optional_content.pdf'),
      tempfile.path
    )
    tempfile.close
    @supporting_pdf_for_mv = tempfile.path

    created = Time.zone.parse('2024-06-01 12:00:00')
    attachment_record = instance_double(
      PersistentAttachment,
      created_at: created,
      to_pdf: @supporting_pdf_for_mv
    )
    allow(attachment_record).to receive(:[]).with(:created_at).and_return(created)

    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(
      :champva_cst_file_uploader_docs_only_resubmission, any_args
    ).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:form1010d_enhanced_flow_enabled, any_args).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:champva_send_to_ves, any_args).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_send_ves_to_pega, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_mpi_validation, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_store_request_json, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_update_datadog_tracking, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys, any_args).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_form_versioning, any_args).and_return(false)

    allow(PersistentAttachments::MilitaryRecords).to receive(:find_by).with(guid: confirmation_code).and_return(
      double('Record', created_at: attachment_record.created_at, id: 1, file: double(id: 'file0'))
    )
    allow(PersistentAttachments::MilitaryRecords).to receive(:exists?).with(guid: confirmation_code).and_return(true)
    allow(PersistentAttachment).to receive(:where).with(guid: [confirmation_code]).and_return([attachment_record])

    allow_any_instance_of(IvcChampva::S3).to receive(:put_object).and_return({ success: true })

    allow(IvcChampva::VesApi::Client).to receive(:new).and_raise(
      StandardError, 'VES must not be invoked for docs-only resubmission'
    )
  end

  after do
    Aws.config = @original_aws_config
    FileUtils.rm_f(@supporting_pdf_for_mv) if @supporting_pdf_for_mv
  end

  it 'accepts docs-only resubmission, skips VES, and uploads supporting docs + metadata' do
    post merged_route, params: base_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }

    form_record = IvcChampvaForm.find_by(form_number: '10-10D-SUPPLEMENTAL-EXISTING')
    expect(form_record).to be_present
    expect(form_record.file_name).not_to include('vha_10_10d-tmp.pdf')
  end

  it 'composes docType from form_number + submission_type and preserves submissionType casing' do
    controller = IvcChampva::V1::UploadsController.new
    form_uuid = SecureRandom.uuid
    claim_uuid = SecureRandom.uuid
    form_instance = double('FormInstance', metadata: { 'uuid' => form_uuid })

    allow(controller).to receive(:form_id_for_form_number).with('10-10D-SUPPLEMENTAL').and_return('vha_10_10d')
    allow(IvcChampva::FormVersionManager).to receive(:create_form_instance).and_return(form_instance)
    allow(controller).to receive(:track_form_submission_metrics)
    allow(form_instance).to receive(:supporting_document_ids).and_return(['Birth certificate'])
    allow(controller).to receive(:docs_only_resubmission_supporting_paths_from_form).and_return(['/tmp/supporting.pdf'])
    allow(IvcChampva::MetadataValidator).to receive(:validate) { |m| m }

    # Without claim_id, form's own uuid is preserved
    _file_paths, metadata = controller.send(
      :get_docs_only_resubmission_file_paths_and_metadata, base_payload
    )
    expect(metadata['docType']).to eq('10-10D-SUPPLEMENTAL-EXISTING')
    expect(metadata['submissionType']).to eq('existing')
    expect(metadata['standalone-flag']).to eq('true')
    expect(metadata['uuid']).to eq(form_uuid)

    # With claim_id, uuid comes from claim_id
    payload_with_claim = base_payload.merge('claim_id' => claim_uuid)
    _file_paths, metadata = controller.send(
      :get_docs_only_resubmission_file_paths_and_metadata, payload_with_claim
    )
    expect(metadata['uuid']).to eq(claim_uuid)
  end

  it 'does not use docs-only persistence when both docs-only flow flags are off' do
    allow(Flipper).to receive(:enabled?)
      .with(:champva_cst_file_uploader_docs_only_resubmission, any_args)
      .and_return(false)
    allow(Flipper).to receive(:enabled?).with(:form1010d_enhanced_flow_enabled, any_args).and_return(false)

    post merged_route, params: base_payload, as: :json

    expect(IvcChampvaForm.where('form_number LIKE ?', '10-10D-SUPPLEMENTAL%').count).to eq(0)
  end

  it 'accepts enrollment docs-only resubmission with empty veteran data' do
    allow(IvcChampvaForm).to receive(:create!).and_call_original

    post merged_route, params: enrollment_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    expect(IvcChampvaForm).to have_received(:create!).with(
      hash_including(form_number: '10-10D-SUPPLEMENTAL-ENROLLMENT')
    )
  end

  it 'returns 422 when a supporting doc is missing its confirmation_code' do
    # no confirmation code, expect a 422
    bad = base_payload.merge('supporting_docs' => [
                               { 'attachment_id' => 'Birth certificate', 'name' => 'doc.pdf', 'is_encrypted' => false }
                             ])
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error_message']).to include('confirmation_code')
  end

  it 'returns 422 when supporting_docs is empty' do
    bad = base_payload.merge('supporting_docs' => [])
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error_message']).to include('supporting_docs is missing')
  end

  it 'does not require certifier_role for docs-only resubmission' do
    bad = base_payload.except('certifier_role')
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'does not require statement_of_truth_signature for docs-only resubmission' do
    bad = base_payload.except('statement_of_truth_signature')
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'does not require certification date for docs-only resubmission' do
    bad = base_payload.merge('certification' => {})
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'does not require applicant details for docs-only resubmission' do
    bad = base_payload.merge('applicants' => [{ 'applicant_name' => { 'last' => 'Alvin' } }])
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'does not require veteran identifiers for docs-only resubmission' do
    bad = base_payload.merge('veteran' => { 'full_name' => { 'first' => 'Pat', 'last' => 'Vet' } })
    post merged_route, params: bad, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'does NOT require veteran name for enrollment submissions' do
    post merged_route, params: enrollment_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
  end

  it 'sends sponsor/veteran metadata from veteran data for existing submissions' do
    captured_puts = []
    allow_any_instance_of(IvcChampva::S3).to receive(:put_object) do |_instance, key, _file, metadata|
      captured_puts << { key:, metadata: }
      { success: true }
    end

    post merged_route, params: base_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    doc_upload = captured_puts.find { |p| p[:metadata].is_a?(Hash) && p[:metadata]['docType'].present? }
    expect(doc_upload).to be_present, "Expected an upload with docType metadata, got: #{captured_puts.inspect}"
    metadata = doc_upload[:metadata]
    expect(metadata['veteranFirstName']).to eq('Pat')
    expect(metadata['veteranLastName']).to eq('Veteran')
    expect(metadata['sponsorFirstName']).to eq('Pat')
    expect(metadata['sponsorLastName']).to eq('Veteran')
  end

  it 'does not populate veteran/sponsor metadata with bene info for enrollment' do
    captured_puts = []
    allow_any_instance_of(IvcChampva::S3).to receive(:put_object) do |_instance, key, _file, metadata|
      captured_puts << { key:, metadata: }
      { success: true }
    end

    post merged_route, params: enrollment_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    doc_upload = captured_puts.find { |p| p[:metadata].is_a?(Hash) && p[:metadata]['docType'].present? }
    expect(doc_upload).to be_present, "Expected an upload with docType metadata, got: #{captured_puts.inspect}"
    metadata = doc_upload[:metadata]
    expect(metadata['veteranFirstName']).to be_nil
    expect(metadata['sponsorFirstName']).to be_nil
  end

  it 'maps applicant_member_number to beneficiary_ssn for enrollment' do
    allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys, any_args).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(true)

    captured_puts = []
    allow_any_instance_of(IvcChampva::S3).to receive(:put_object) do |_instance, key, _file, metadata|
      captured_puts << { key:, metadata: }
      { success: true }
    end

    post merged_route, params: enrollment_payload, as: :json

    expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    doc_upload = captured_puts.find { |p| p[:metadata].is_a?(Hash) && p[:metadata]['docType'].present? }
    expect(doc_upload).to be_present, "Expected an upload with docType metadata, got: #{captured_puts.inspect}"
    bene = JSON.parse(doc_upload[:metadata]['beneficiary_0'])
    expect(bene['beneficiary_ssn']).to eq('345345345')
  end
end
