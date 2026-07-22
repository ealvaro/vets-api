# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

# Controller-orchestration coverage for UploadsController data preparation that
# spans more than a single form model: OHI additional_file_metadata mapping,
# Duty to Assist (DTA) stamped-page naming, and DTA document merging.
# The pure per-form data-transformation logic is covered by the model and mixin
# unit specs (see spec/models/ivc_champva/* and spec/services/data_transformations_spec.rb).
RSpec.describe 'IvcChampva::V1::UploadsController data preparation', type: :request do
  let(:ves_client) { double('IvcChampva::VesApi::Client') }
  let(:aws_client) { instance_double(Aws::S3::Client) }
  let(:uuid) { SecureRandom.uuid }

  before do
    @original_aws_config = Aws.config.dup
    Aws.config.update(stub_responses: true)
    allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
    allow(ves_client).to receive(:submit_1010d).with(anything, anything)
    allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_update_datadog_tracking, anything).and_return(false)
  end

  after do
    Aws.config = @original_aws_config
  end

  describe '10-7959A DTA resubmission (has_claim_docs: false)' do
    fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959a.json')
    data = JSON.parse(fixture_path.read).merge(
      'claim_status' => 'resubmission',
      'has_claim_docs' => false
    )

    let(:pdf_path) { Rails.root.join('tmp', "#{uuid}_vha_10_7959a.pdf").to_s }
    let(:blank_page_path) { Rails.root.join('tmp', "#{SecureRandom.hex(8)}_blank.pdf").to_s }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_send_to_ves, @current_user).and_return(false)
      allow(Flipper).to receive(:enabled?).with('champva_claims_insurance_dates', anything).and_return(false)

      allow(SecureRandom).to receive(:uuid).and_return(uuid)
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record1', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))

      [IvcChampva::VHA1010d2027, IvcChampva::VHA1010d, IvcChampva::VHA107959a, IvcChampva::VHA107959a2027,
       IvcChampva::VHA107959cRev2025, IvcChampva::VHA107959c, IvcChampva::VHA107959f1, IvcChampva::VHA107959f2,
       IvcChampva::VHA107959f22025].each do |form|
        allow_any_instance_of(form).to receive(:handle_attachments).and_return([pdf_path])
      end
      allow_any_instance_of(IvcChampva::PdfFiller).to receive(:generate).and_return(pdf_path)

      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:create_custom_attachment).and_return({})
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:add_supporting_doc)
      allow(IvcChampva::PdfStamper).to receive(:stamp_metadata_items)

      allow(aws_client).to receive(:put_object).and_return(
        double('response', context: double('context', http_response: double('http_response', status_code: 200)))
      )
      allow_any_instance_of(IvcChampva::S3).to receive(:client).and_return(aws_client)

      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist, anything).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_document_merging, anything).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)

      FileUtils.touch(blank_page_path)
      allow(IvcChampva::Attachments).to receive(:get_blank_page).and_return(blank_page_path)
    end

    after do
      Rails.root.glob("tmp/#{uuid}_*_form_page.pdf").each { |f| FileUtils.rm_f(f) }
    end

    it 'names the DTA stamped page as form_page instead of supporting_doc' do
      stamped_page_key = "#{uuid}_vha_10_7959a_form_page.pdf"

      allow_any_instance_of(IvcChampva::S3).to receive(:read_file) do |_instance, path|
        path.to_s.include?('_metadata.json') ? '{}' : '%PDF-1.4 test stub'
      end

      post '/ivc_champva/v1/forms', params: data.to_json,
                                    headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:ok)

      put_object_calls = []
      expect(aws_client).to have_received(:put_object).at_least(:once) do |params|
        put_object_calls << params
      end

      uploaded_keys = put_object_calls.map { |p| p[:key] }

      expect(uploaded_keys).to include(stamped_page_key)
      expect(uploaded_keys.select { |k| k.include?('supporting_doc') }).to be_empty

      stamped_upload = put_object_calls.find { |p| p[:key] == stamped_page_key }
      expect(stamped_upload[:metadata]['attachment_id']).to eq('Duty to Assist')
    end

    it 'labels all attachment_ids as Duty to Assist' do
      allow_any_instance_of(IvcChampva::S3).to receive(:read_file) do |_instance, path|
        path.to_s.include?('_metadata.json') ? '{}' : '%PDF-1.4 test stub'
      end

      post '/ivc_champva/v1/forms', params: data.to_json,
                                    headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:ok)

      expect(aws_client).to have_received(:put_object).once.with(
        hash_including(
          key: "#{uuid}_vha_10_7959a.pdf",
          metadata: a_hash_including('attachment_id' => 'Duty to Assist')
        )
      )
    end

    context 'with document merging enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_document_merging, anything).and_return(true)
        allow(Flipper).to receive(:enabled?).with('champva_docmerge_10_7959a_duty_to_assist', anything)
                                            .and_return(true)

        FileUtils.touch(pdf_path)
        allow(IvcChampva::PdfCombiner).to receive(:combine) do |output_path, _input_paths|
          FileUtils.touch(output_path)
        end
      end

      after do
        Rails.root.glob("tmp/#{uuid}_*_combined.pdf").each { |f| FileUtils.rm_f(f) }
      end

      it 'merges the stamped page into the combined DTA PDF' do
        allow_any_instance_of(IvcChampva::S3).to receive(:read_file) do |_instance, path|
          path.to_s.include?('_metadata.json') ? '{}' : '%PDF-1.4 test stub'
        end

        post '/ivc_champva/v1/forms', params: data.to_json,
                                      headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)

        put_object_calls = []
        expect(aws_client).to have_received(:put_object).at_least(:once) do |params|
          put_object_calls << params
        end

        uploaded_keys = put_object_calls.map { |p| p[:key] }

        combined_key = uploaded_keys.find { |k| k.include?('_combined.pdf') }
        expect(combined_key).to be_present
        expect(combined_key).to include('duty_to_assist')

        expect(uploaded_keys.select { |k| k.include?('form_page') }).to be_empty
        expect(uploaded_keys.select { |k| k.include?('supporting_doc') }).to be_empty
      end
    end
  end

  describe 'additional_file_metadata with champva_send_ohi_ves_to_pega' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:mock_form) { double('Form', form_id: 'vha_10_10d', uuid:, data: {}, metadata: {}) }
    let(:mock_ves_request) { double('VesRequest', to_json: '{"test":"data"}') }
    let(:pdf_path) { "#{uuid}_vha_10_10d-tmp.pdf" }

    before do
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
      allow(controller).to receive(:get_form_id).and_return('vha_10_10d')
      allow(controller).to receive(:track_form_submission_metrics)
      allow(IvcChampva::FormVersionManager).to receive_messages(create_form_instance: mock_form,
                                                                get_legacy_form_id: 'vha_10_10d')
      allow_any_instance_of(IvcChampva::PdfFiller).to receive(:generate).and_return(pdf_path)
      allow(mock_form).to receive_messages(prepare_submission_data: [['vha_10_10d'], nil], validated_metadata: {},
                                           handle_attachments: [pdf_path])
      allow(IvcChampva::VesDataFormatter).to receive(:format_for_request).and_return(mock_ves_request)
      allow(File).to receive(:write)
    end

    context 'when flag is enabled' do
      let(:parsed_form_data) do
        JSON.parse(
          Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read
        )
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(true)
      end

      it 'includes additional_file_metadata mapping PDF to VES JSON' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(metadata).to have_key('additional_file_metadata')
        pdf_meta = metadata['additional_file_metadata']["#{uuid}_vha_10_10d.pdf"]
        expect(pdf_meta).to be_present
        expect(pdf_meta['meta-jsonfile']).to include('_ves.json')
      end
    end

    context 'when flag is enabled with two OHI PDFs (EXTENDED)' do
      let(:ohi_pdf_one) { "#{uuid}_vha_10_10d_supporting_doc-1.pdf" }
      let(:ohi_pdf_two) { "#{uuid}_vha_10_10d_supporting_doc-2.pdf" }
      let(:mock_ohi_request_a) { double('VesOhiRequestA', to_json: '{"ohi":"a"}') }
      let(:mock_ohi_request_b) { double('VesOhiRequestB', to_json: '{"ohi":"b"}') }
      let(:parsed_form_data) do
        data = JSON.parse(
          Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read
        )
        data['form_number'] = '10-10D-EXTENDED'
        data
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(true)
        allow(mock_form).to receive_messages(
          prepare_submission_data: [['vha_10_10d', 'VA form 10-7959c', 'VA form 10-7959c'],
                                    nil], handle_attachments: [pdf_path, ohi_pdf_one, ohi_pdf_two]
        )
        allow(IvcChampva::VesDataFormatter).to receive(:format_for_ohi_request)
          .and_return([mock_ohi_request_a, mock_ohi_request_b])
      end

      it 'maps 10-10D PDF to 10-10D VES JSON' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)
        tenten_meta = metadata.dig('additional_file_metadata', "#{uuid}_vha_10_10d.pdf")

        expect(tenten_meta['meta-jsonfile']).to include('_ves.json')
        expect(tenten_meta['meta-jsonfile']).not_to include('_ohi_')
      end

      it 'maps each OHI PDF to its own VES OHI JSON by position' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)
        afm = metadata['additional_file_metadata']

        expect(afm.dig(ohi_pdf_one, 'meta-jsonfile')).to include('_ohi_ves_0')
        expect(afm.dig(ohi_pdf_two, 'meta-jsonfile')).to include('_ohi_ves_1')
      end
    end

    context 'when flag is enabled with standalone 10-7959C' do
      let(:mock_form) { double('Form', form_id: 'vha_10_7959c', uuid:, data: {}, metadata: {}) }
      let(:ohi_pdf) { "#{uuid}_vha_10_7959c-tmp.pdf" }
      let(:mock_ohi_request) { double('VesOhiRequest', to_json: '{"ohi":"standalone"}') }
      let(:parsed_form_data) do
        data = JSON.parse(
          Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959c.json').read
        )
        data['form_number'] = '10-7959C'
        data
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(true)
        allow(controller).to receive(:get_form_id).and_return('vha_10_7959c')
        allow(controller).to receive(:track_form_submission_metrics)
        allow(IvcChampva::FormVersionManager).to receive_messages(create_form_instance: mock_form,
                                                                  get_legacy_form_id: 'vha_10_7959c')
        allow(mock_form).to receive_messages(prepare_submission_data: [['vha_10_7959c'], nil], validated_metadata: {},
                                             handle_attachments: [ohi_pdf])
        allow(IvcChampva::VesDataFormatter).to receive(:format_for_ohi_request)
          .and_return([mock_ohi_request])
      end

      it 'maps the standalone 10-7959C PDF to its OHI VES JSON' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)
        afm = metadata['additional_file_metadata']

        expect(afm).to be_present
        pdf_meta = afm["#{uuid}_vha_10_7959c.pdf"]
        expect(pdf_meta).to be_present
        expect(pdf_meta['meta-jsonfile']).to include('_ohi_ves_0.json')
      end

      it 'does not create a VES JSON entry (only OHI VES JSON)' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(metadata['attachment_ids']).to include('VES OHI JSON')
        expect(metadata['attachment_ids']).not_to include('VES JSON')
      end
    end

    context 'when flag is disabled' do
      let(:parsed_form_data) do
        JSON.parse(
          Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read
        )
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(false)
      end

      it 'does not include additional_file_metadata' do
        _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(metadata).not_to have_key('additional_file_metadata')
      end
    end
  end
end
