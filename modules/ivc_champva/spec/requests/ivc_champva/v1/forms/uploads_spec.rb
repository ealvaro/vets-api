# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'
require 'common/convert_to_pdf'

RSpec.describe 'IvcChampva::V1::Forms::Uploads', type: :request do
  # forms_numbers_and_classes is a hash that maps form numbers if they have attachments
  form_numbers_and_classes = {
    '10-10D' => IvcChampva::VHA1010d,
    '10-7959C' => IvcChampva::VHA107959c,
    '10-7959F-2' => IvcChampva::VHA107959f2,
    '10-7959F-1' => IvcChampva::VHA107959f1,
    '10-7959A' => IvcChampva::VHA107959a
  }

  forms = [
    'vha_10_10d.json',
    'vha_10_7959f_1.json',
    'vha_10_7959f_2.json',
    'vha_10_7959c.json',
    'vha_10_7959a.json'
  ]

  let(:ves_request) { double('IvcChampva::VesRequest') }
  let(:ves_client) { double('IvcChampva::VesApi::Client') }

  before do
    @original_aws_config = Aws.config.dup
    Aws.config.update(stub_responses: true)
    allow(IvcChampva::VesDataFormatter).to receive_messages(format_for_request: ves_request,
                                                            format_for_extended_request: ves_request,
                                                            format_for_ohi_request: [])
    allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
    allow(ves_client).to receive(:submit_1010d).with(anything, anything)
    allow(ves_request).to receive_messages(transaction_uuid: '78444a0b-3ac8-454d-a28d-8d63cddd0d3b',
                                           application_uuid: 'test-uuid',
                                           form_type: 'vha_10_10d',
                                           form_1010d?: true,
                                           form_1010dx?: false,
                                           form_7959c?: false,
                                           subforms?: false)
    allow(ves_request).to receive(:transaction_uuid=)
    allow(ves_request).to receive(:to_json).and_return('{}')
    allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:champva_store_request_json, anything).and_return(false)
  end

  after do
    Aws.config = @original_aws_config
  end

  describe '#submit VES flow' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:champva_update_datadog_tracking, @current_user)
        .and_return(false)
    end

    forms.each do |form|
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', form)
      data = JSON.parse(fixture_path.read)

      it 'uploads a PDF file to S3' do
        mock_form = double(first_name: 'Veteran', last_name: 'Surname', form_uuid: 'some_uuid')
        allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
          .and_return(double('Record1', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))
        allow(IvcChampvaForm).to receive(:first).and_return(mock_form)
        allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(
          double('response',
                 context: double('context', http_response: double('http_response', status_code: 200)))
        )

        post '/ivc_champva/v1/forms', params: data

        record = IvcChampvaForm.first

        expect(record.first_name).to eq('Veteran')
        expect(record.last_name).to eq('Surname')
        expect(record.form_uuid).to be_present

        expect(response).to have_http_status(:ok)
      end

      it 'returns a 500 error when supporting documents are submitted, but are missing from the database' do
        allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(true)

        # Actual supporting_docs should exist as records in the DB. This test
        # ensures that if they aren't present we won't have a silent failure
        data_with_docs = data.merge({ supporting_docs: [{ confirmation_code: 'NOT_IN_DATABASE' }] })
        post '/ivc_champva/v1/forms', params: data_with_docs

        expect(response).to have_http_status(:internal_server_error)
      end

      it 'does VES processing only for form 10-10D' do
        controller = IvcChampva::V1::UploadsController.new
        allow(controller).to receive_messages(handle_file_uploads: [[200], nil],
                                              get_file_paths_and_metadata: [['path'], {}],
                                              params: ActionController::Parameters.new(data))
        allow(controller).to receive(:render)

        controller.send(:submit)

        if data['form_number'] == '10-10D'
          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
          # make sure submit_1010d is called with the request object from the formatter
          expect(ves_client).to have_received(:submit_1010d).with(anything, ves_request)
        else
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_request)
          expect(ves_client).not_to have_received(:submit_1010d)
        end
      end

      it 'returns an error and does proceed when format_for_request throws an error' do
        if data['form_number'] == '10-10D'
          allow(IvcChampva::VesDataFormatter).to receive(:format_for_request)
            .and_raise(StandardError.new('oh no'))
          controller = IvcChampva::V1::UploadsController.new
          allow(controller).to receive(:handle_file_uploads)
          allow(controller).to receive_messages(get_file_paths_and_metadata: [['path'], { 'uuid' => 'test-uuid' }],
                                                params: ActionController::Parameters.new(data))
          allow(controller).to receive(:render)

          controller.send(:submit)

          expect(controller).not_to have_received(:handle_file_uploads)
          expect(ves_client).not_to have_received(:submit_1010d)
          expect(controller).to have_received(:render)
            .with({ json: { error_message: 'Error: oh no' }, status: :internal_server_error })
        end
      end

      it 'returns an error and does not proceed when format_for_request returns nil' do
        if data['form_number'] == '10-10D'
          allow(IvcChampva::VesDataFormatter).to receive(:format_for_request).and_return(nil)
          controller = IvcChampva::V1::UploadsController.new
          allow(controller).to receive(:handle_file_uploads)
          allow(controller).to receive_messages(get_file_paths_and_metadata: [['path'], { 'uuid' => 'test-uuid' }],
                                                params: ActionController::Parameters.new(data))
          allow(controller).to receive(:render)

          controller.send(:submit)

          expect(controller).not_to have_received(:handle_file_uploads)
          expect(ves_client).not_to have_received(:submit_1010d)
          expect(controller).to have_received(:render)
            .with({
                    json: { error_message: 'Error: Failed to format data for VES submission' },
                    status: :internal_server_error
                  })
        end
      end

      it 'returns an error and does not proceed when handle_file_uploads fails' do
        if data['form_number'] == '10-10D'
          controller = IvcChampva::V1::UploadsController.new
          allow(controller).to receive_messages(handle_file_uploads: [[400], 'oh no'],
                                                get_file_paths_and_metadata: [['path'], {}],
                                                params: ActionController::Parameters.new(data))
          allow(controller).to receive(:render)

          controller.send(:submit)

          expect(ves_client).not_to have_received(:submit_1010d)
          expect(controller).to have_received(:render)
            .with({ json: { error_message: 'oh no' }, status: 400 })
        end
      end

      it 'returns ok when submitting to VES results in an error' do
        if data['form_number'] == '10-10D'
          # These must be mocked in order for submit to be able to complete successfully: find_by, put_object
          allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
            .and_return(double('Record1', created_at: 1.day.ago,
                                          id: 'some_uuid', file: double(id: 'file0')))
          allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(
            double('response',
                   context: double('context', http_response: double('http_response', status_code: 200)))
          )
          # Mock VES returning an error
          allow(ves_client).to receive(:submit_1010d).and_raise(IvcChampva::VesApi::VesApiError.new('oh no'))

          post '/ivc_champva/v1/forms', params: data

          expect(response).to have_http_status(:ok)
        end
      end

      it 'retries VES submission if it fails' do
        with_settings(Settings, vsp_environment: 'staging') do
          if data['form_number'] == '10-10D'
            allow(ves_request).to receive_messages(transaction_uuid: 'fake-id', 'transaction_uuid=' => nil)

            controller = IvcChampva::V1::UploadsController.new

            allow(ves_client).to receive(:submit_1010d)
              .with(anything, anything)
              .and_raise(IvcChampva::VesApi::VesApiError.new('oh no'))

            allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)

            controller.send(:submit_ves_form, ves_client, ves_request, {})

            expect(ves_client).to have_received(:submit_1010d).twice
          end
        end
      end
    end
  end

  describe '#submit with champva_update_datadog_tracking enabled' do
    let(:form_with_track_submission) { 'vha_10_10d.json' }

    before do
      # Mirror the setup from the passing tests, but enable champva_update_datadog_tracking
      allow(Flipper).to receive(:enabled?)
        .with(:champva_update_datadog_tracking, @current_user)
        .and_return(true)
    end

    it 'calls track_submission on form models that respond to it' do
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json',
                                     form_with_track_submission)
      data = JSON.parse(fixture_path.read)

      mock_form = double(first_name: 'Veteran', last_name: 'Surname', form_uuid: 'some_uuid')
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record1', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))
      allow(IvcChampvaForm).to receive(:first).and_return(mock_form)
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(
        double('response',
               context: double('context', http_response: double('http_response', status_code: 200)))
      )

      # Allow all StatsD calls, but specifically check for the .submission call
      allow(StatsD).to receive(:increment).and_call_original

      post '/ivc_champva/v1/forms', params: data

      expect(response).to have_http_status(:ok)
      # Verify track_submission was called by checking the StatsD increment
      expect(StatsD).to have_received(:increment).with(
        'api.ivc_champva_form.10_10d.submission',
        hash_including(:tags)
      )
    end

    it 'calls track_submission on 7959F-1 form models' do
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959f_1.json')
      data = JSON.parse(fixture_path.read)

      mock_form = double(first_name: 'Veteran', last_name: 'Surname', form_uuid: 'some_uuid')
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record1', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))
      allow(IvcChampvaForm).to receive(:first).and_return(mock_form)
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(
        double('response',
               context: double('context', http_response: double('http_response', status_code: 200)))
      )

      allow(StatsD).to receive(:increment).and_call_original

      post '/ivc_champva/v1/forms', params: data

      expect(response).to have_http_status(:ok)
      expect(StatsD).to have_received(:increment).with(
        'api.ivc_champva_form.10_7959f_1.submission',
        hash_including(:tags)
      )
    end
  end

  describe '#prepare_ves_request routing' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:form_uuid) { '12345678-1234-5678-1234-567812345678' }
    let(:mock_ves_request) { double('IvcChampva::VesRequest') }
    let(:mock_extended_ves_request) { double('IvcChampva::VesRequest with subforms') }
    let(:mock_ohi_requests) { [double('IvcChampva::VesOhiRequest')] }

    before do
      allow(IvcChampva::VesDataFormatter).to receive_messages(
        format_for_request: mock_ves_request,
        format_for_extended_request: mock_extended_ves_request,
        format_for_ohi_request: mock_ohi_requests
      )
    end

    context 'when champva_send_7959c_to_ves is DISABLED (legacy flow)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(false)
      end

      context 'when form_number is 10-10D' do
        let(:parsed_form_data) { { 'form_number' => '10-10D' } }

        it 'calls format_for_request' do
          result = controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)

          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
            .with(parsed_form_data, form_uuid:)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_extended_request)
          expect(result).to eq(mock_ves_request)
        end
      end

      context 'when form_number is 10-10D-EXTENDED' do
        let(:parsed_form_data) { { 'form_number' => '10-10D-EXTENDED' } }

        it 'calls format_for_request (NO subforms in legacy flow)' do
          result = controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)

          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
            .with(parsed_form_data, form_uuid:)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_extended_request)
          expect(result).to eq(mock_ves_request)
        end
      end
    end

    context 'when champva_send_7959c_to_ves is ENABLED' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(true)
      end

      context 'when form_number is 10-10D' do
        let(:parsed_form_data) { { 'form_number' => '10-10D' } }

        it 'calls format_for_request (standalone 10-10D)' do
          result = controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)

          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
            .with(parsed_form_data, form_uuid:)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_extended_request)
          expect(result).to eq(mock_ves_request)
        end
      end

      context 'when form_number is 10-10D-EXTENDED' do
        let(:parsed_form_data) { { 'form_number' => '10-10D-EXTENDED' } }

        it 'calls format_for_extended_request (10-10D with OHI subforms)' do
          result = controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)

          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_extended_request)
            .with(parsed_form_data, form_uuid:)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_request)
          expect(result).to eq(mock_extended_ves_request)
        end

        context 'when OHI formatting fails' do
          before do
            allow(IvcChampva::VesDataFormatter).to receive(:format_for_extended_request)
              .and_raise(ArgumentError, 'OHI validation failed')
          end

          it 'raises the error (strict validation - no fallback)' do
            expect do
              controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)
            end.to raise_error(ArgumentError, 'OHI validation failed')
          end
        end
      end

      context 'when form_number is 10-7959C (standalone OHI)' do
        let(:parsed_form_data) { { 'form_number' => '10-7959C' } }

        it 'calls format_for_ohi_request' do
          result = controller.send(:prepare_ves_request, parsed_form_data, form_uuid:)

          expect(IvcChampva::VesDataFormatter).to have_received(:format_for_ohi_request)
            .with(parsed_form_data, form_uuid:)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_request)
          expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_extended_request)
          expect(result).to eq(mock_ohi_requests)
        end
      end
    end
  end

  describe '#should_process_ves?' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    context 'when form is vha_10_10d' do
      it 'returns true' do
        expect(controller.send(:should_process_ves?, 'vha_10_10d')).to be true
      end
    end

    context 'when form is vha_10_7959c (standalone OHI)' do
      it 'returns true when champva_send_7959c_to_ves is enabled' do
        allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(true)

        expect(controller.send(:should_process_ves?, 'vha_10_7959c')).to be true
      end

      it 'returns false when champva_send_7959c_to_ves is disabled' do
        allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(false)

        expect(controller.send(:should_process_ves?, 'vha_10_7959c')).to be false
      end
    end

    context 'when form is other type' do
      it 'returns false' do
        allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(true)

        expect(controller.send(:should_process_ves?, 'vha_10_7959f_1')).to be false
      end
    end
  end

  describe '#handle_file_uploads_wrapper' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:docs_only_payload) do
      { 'form_number' => '10-10D-EXTENDED', 'submission_type' => 'existing' }
    end

    it 'skips VES when docs-only flow is enabled' do
      allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:form1010d_enhanced_flow_enabled, anything)
        .and_return(true)

      expect(controller).not_to receive(:handle_ves_submission)
      allow(controller).to receive_messages(get_file_paths_and_metadata: [['path'], {}],
                                            build_json: { json: {}, status: 200 })
      allow(controller).to receive(:handle_file_uploads)
        .with('vha_10_10d', anything, anything, docs_only_payload)
        .and_return([[200], nil])

      result = controller.send(:handle_file_uploads_wrapper, 'vha_10_10d', docs_only_payload)
      expect(result[:status]).to eq(200)
    end

    it 'skips VES when CST docs-only flow is enabled' do
      cst_docs_only_payload = docs_only_payload.merge('claim_id' => SecureRandom.uuid)

      allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything)
        .and_return(true)

      expect(controller).not_to receive(:handle_ves_submission)
      allow(controller).to receive_messages(get_file_paths_and_metadata: [['path'], {}],
                                            build_json: { json: {}, status: 200 })
      allow(controller).to receive(:handle_file_uploads)
        .with('vha_10_10d', anything, anything, cst_docs_only_payload)
        .and_return([[200], nil])

      result = controller.send(:handle_file_uploads_wrapper, 'vha_10_10d', cst_docs_only_payload)
      expect(result[:status]).to eq(200)
    end
  end

  describe '#submit_to_ves' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:metadata) { { 'uuid' => 'test-uuid' } }
    let(:mock_ves_client) { double('IvcChampva::VesApi::Client') }
    let(:success_response) { double('Response', status: 200) }

    before do
      allow(IvcChampva::VesApi::Client).to receive(:new).and_return(mock_ves_client)
      allow(controller).to receive(:submit_ves_form).and_return(success_response)
      allow(controller).to receive(:submit_ves_requests)
    end

    context 'when ves_request is nil' do
      it 'does nothing' do
        controller.send(:submit_to_ves, nil, metadata)

        expect(controller).not_to have_received(:submit_ves_form)
        expect(controller).not_to have_received(:submit_ves_requests)
      end
    end

    context 'when ves_request is an array (standalone OHI)' do
      let(:ohi_requests) { [double('VesOhiRequest1'), double('VesOhiRequest2')] }

      it 'calls submit_ves_requests' do
        controller.send(:submit_to_ves, ohi_requests, metadata)

        expect(controller).to have_received(:submit_ves_requests).with(mock_ves_client, ohi_requests, metadata)
      end
    end

    context 'when ves_request is a VesRequest without subforms (10-10D)' do
      let(:mock_request) do
        double('VesRequest', form_type: 'vha_10_10d', form_1010d?: true, form_1010dx?: false, form_7959c?: false,
                             subforms?: false)
      end

      it 'calls submit_ves_form directly' do
        controller.send(:submit_to_ves, mock_request, metadata)

        expect(controller).to have_received(:submit_ves_form).with(mock_ves_client, mock_request, metadata)
        expect(controller).not_to have_received(:submit_ves_requests)
      end
    end

    context 'when ves_request has subforms (10-10D-EXTENDED)' do
      let(:ohi_request) { double('VesOhiRequest', form_1010d?: false, form_1010dx?: false, form_7959c?: true) }
      let(:subforms) { [{ form_type: 'vha_10_7959c', request: ohi_request }] }
      let(:mock_request) do
        double('VesRequest', form_type: 'vha_10_10d', form_1010d?: false, form_1010dx?: true, form_7959c?: false,
                             subforms?: true, subforms:)
      end

      it 'submits parent and then mapped subform requests on success' do
        controller.send(:submit_to_ves, mock_request, metadata)

        expect(controller).to have_received(:submit_ves_form).with(mock_ves_client, mock_request, metadata)
        expect(controller).to have_received(:submit_ves_requests).with(mock_ves_client, [ohi_request], metadata)
      end

      context 'when parent submission fails' do
        let(:failed_response) { double('Response', status: 500) }

        before do
          allow(controller).to receive(:submit_ves_form).and_return(failed_response)
        end

        it 'does not submit subforms' do
          controller.send(:submit_to_ves, mock_request, metadata)

          expect(controller).to have_received(:submit_ves_form)
          expect(controller).not_to have_received(:submit_ves_requests)
        end
      end
    end
  end

  # Copied this test from the #submit endpoint tests above and adjusted to use
  # the new endpoint. We'll need more tests in future, but wanted to have at
  # least one verifying it wasn't throwing rampant errors
  describe '#submit_champva_app_merged' do
    fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json',
                                   'vha_10_10d_extended.json')
    data = JSON.parse(fixture_path.read)

    before do
      # These tests focus on S3/PEGA upload; stub VES so 10-10D-EXTENDED submissions
      # route through VES without hitting the real client.
      allow(Flipper).to receive(:enabled?).with(:champva_send_7959c_to_ves, anything).and_return(false)
      allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
      allow(ves_client).to receive(:submit_1010d).and_return(double('response', status: 200, body: ''))
    end

    it 'uploads a PDF file to S3' do
      mock_form = double(first_name: 'Veteran', last_name: 'Surname', form_uuid: 'some_uuid')
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record1', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))
      allow(IvcChampvaForm).to receive(:first).and_return(mock_form)
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(
        double('response',
               context: double('context', http_response: double('http_response', status_code: 200)))
      )

      post '/ivc_champva/v1/forms/10-10d-ext', params: data

      record = IvcChampvaForm.first

      expect(record.first_name).to eq('Veteran')
      expect(record.last_name).to eq('Surname')
      expect(record.form_uuid).to be_present

      expect(response).to have_http_status(:ok)
    end

    # Also taken from the main #submit endpoint tests as they function the same at this level
    it 'returns a 500 error when supporting documents are submitted, but are missing from the database' do
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object).and_return(true)

      # Actual supporting_docs should exist as records in the DB. This test
      # ensures that if they aren't present we won't have a silent failure
      data_with_docs = data.merge({ supporting_docs: [{ confirmation_code: 'NOT_IN_DATABASE' }] })
      post '/ivc_champva/v1/forms/10-10d-ext', params: data_with_docs

      expect(response).to have_http_status(:internal_server_error)
    end

    it 'tracks the delegate form' do
      # Create a mock form instance that will be returned by generate_ohi_form
      mock_form = instance_double(IvcChampva::VHA107959cRev2025)
      allow(mock_form).to receive(:track_delegate_form)
      allow(mock_form).to receive(:respond_to?).with(:track_delegate_form).and_return(true)

      # Stub the controller methods to bypass the complex PDF generation flow
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:generate_ohi_form)
                                                              .and_return([mock_form])
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:fill_ohi_and_return_path)
                                                              .and_return('/tmp/test.pdf')
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:create_custom_attachment).and_return({})
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:add_supporting_doc)
      allow_any_instance_of(IvcChampva::V1::UploadsController).to receive(:submit).and_return(nil)

      post '/ivc_champva/v1/forms/10-10d-ext', params: data

      # Verify the method was called with the correct parent form ID
      expect(mock_form).to have_received(:track_delegate_form).with('vha_10_10d')
    end
  end

  describe 'stored data encryption' do
    it 'ves_request_data is encrypted' do
      expect(IvcChampvaForm.new).to encrypt_attr(:ves_request_data)
    end

    it 'request_json is encrypted' do
      expect(IvcChampvaForm.new).to encrypt_attr(:request_json)
    end
  end

  describe '#submit_supporting_documents' do
    let(:file) { fixture_file_upload('doctors-note.gif') }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, @current_user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(false)
    end

    context 'successful transaction' do
      it 'renders the attachment as json' do
        clamscan = double(safe?: true)
        allow(Common::VirusScan).to receive(:scan).and_return(clamscan)

        data_sets = [
          { form_id: '10-10D', file: }
        ]

        data_sets.each do |data|
          expect do
            post '/ivc_champva/v1/forms/submit_supporting_documents', params: data
          end.to change(PersistentAttachment, :count).by(1)

          expect(response).to have_http_status(:ok)
          resp = JSON.parse(response.body)
          expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])
          expect(PersistentAttachment.last).to be_a(PersistentAttachments::MilitaryRecords)
        end
      end

      it 'creates an evidence submission when claim_id is provided' do
        clamscan = double(safe?: true)
        allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
        user_account = create(:user_account)

        allow_any_instance_of(IvcChampva::V1::UploadsController)
          .to receive(:current_user_account_for_evidence_submission)
          .and_return(user_account)

        expect do
          post '/ivc_champva/v1/forms/submit_supporting_documents',
               params: { form_id: '10-10D', claim_id: 12_345, file:, attachment_id: 'Birth certificate' }
        end.to change(EvidenceSubmission, :count).by(1)

        submission = EvidenceSubmission.last
        expect(submission.claim_id).to eq(12_345)
        expect(submission.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED])
        expect(submission.user_account_id).to eq(user_account.id)
        expect(JSON.parse(submission.template_metadata)['personalisation']).to include(
          'document_type' => 'Birth certificate',
          'file_name' => 'doctors-note.gif'
        )
      end

      it 'maps UUID claim_id to the underlying CHAMPVA form record id' do
        clamscan = double(safe?: true)
        allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
        user_account = create(:user_account)
        form = create(:ivc_champva_form)

        allow_any_instance_of(IvcChampva::V1::UploadsController)
          .to receive(:current_user_account_for_evidence_submission)
          .and_return(user_account)

        expect do
          post '/ivc_champva/v1/forms/submit_supporting_documents',
               params: { form_id: '10-10D', claim_id: form.form_uuid, file: }
        end.to change(EvidenceSubmission, :count).by(1)

        expect(EvidenceSubmission.last.claim_id).to eq(form.id)
      end

      it 'maps UUID claim_id to a stable CHAMPVA form id when multiple records share the UUID' do
        clamscan = double(safe?: true)
        allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
        user_account = create(:user_account)
        first_form = create(:ivc_champva_form)
        create(:ivc_champva_form, form_uuid: first_form.form_uuid)

        allow_any_instance_of(IvcChampva::V1::UploadsController)
          .to receive(:current_user_account_for_evidence_submission)
          .and_return(user_account)

        expect do
          post '/ivc_champva/v1/forms/submit_supporting_documents',
               params: { form_id: '10-10D', claim_id: first_form.form_uuid, file: }
        end.to change(EvidenceSubmission, :count).by(1)

        expect(EvidenceSubmission.last.claim_id).to eq(first_form.id)
      end
    end

    context 'LLM response integration' do
      let(:clamscan) { double(safe?: true) }

      before do
        allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
      end

      context 'when LLM conditions are met' do
        before do
          # Mock Flipper for both @current_user (which might be set) and nil (which is typical in these tests)
          allow(Flipper).to receive(:enabled?).with(:champva_claims_llm_validation, @current_user).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:champva_claims_llm_validation, nil).and_return(true)
        end

        it 'includes llm_response in the JSON for 10-7959A form' do
          # Set up AWS mocking for individual test runs (prevents real AWS calls)
          original_aws_config = Aws.config.dup
          Aws.config.update(stub_responses: true)

          # Ensure virus scan mock is set up for individual test runs
          clamscan = double(safe?: true)
          allow(Common::VirusScan).to receive(:scan).and_return(clamscan)

          # Mock background job launching to prevent OCR job from hanging on file I/O
          allow_any_instance_of(IvcChampva::V1::UploadsController)
            .to receive(:launch_background_job)

          # Create a mock response that matches the structure returned by MockClient
          # rubocop:disable Layout/LineLength
          mock_response = {
            body: {
              answer: '```json
                      {
                        "doc_type": "EOB",
                        "doc_type_matches": true,
                        "valid": false,
                        "confidence": 0.9,
                        "missing_fields": [
                          "Provider NPI (10-digit)",
                          "Services Paid For (CPT/HCPCS code or description)"
                        ],
                        "present_fields": {
                          "Date of Service": "01/29/13",
                          "Provider Name": "Smith, Robert",
                          "Amount Paid by Insurance": "0.00"
                        },
                        "notes": "The document is classified as an EOB. Missing required fields for Provider NPI and Services Paid For."
                      }
                      ```'
            }.to_json
          }
          # rubocop:enable Layout/LineLength

          # Parse the response the same way call_llm_service does
          parsed_response = JSON.parse(mock_response[:body])
          answer_content = parsed_response['answer']
          cleaned_content = answer_content.strip.gsub(/^```json\s*/, '').gsub(/\s*```$/, '')
          mock_client_response = JSON.parse(cleaned_content)

          allow_any_instance_of(IvcChampva::V1::UploadsController)
            .to receive(:call_llm_service)
            .and_return(mock_client_response)

          data = { form_id: '10-7959A', file:, attachment_id: 'test_document' }

          post '/ivc_champva/v1/forms/submit_supporting_documents', params: data

          expect(response).to have_http_status(:ok)
          resp = JSON.parse(response.body)

          # Should have the standard attachment data
          expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])

          # Should have LLM response data that matches MockClient structure
          expect(resp).to have_key('llm_response')
          expect(resp['llm_response']).to eq(mock_client_response)
        ensure
          # Restore original AWS config
          Aws.config = original_aws_config if defined?(original_aws_config)
        end

        it 'does not include llm_response for non-7959A forms even when flipper is enabled' do
          data = { form_id: '10-10D', file:, attachment_id: 'test_document' }

          post '/ivc_champva/v1/forms/submit_supporting_documents', params: data

          expect(response).to have_http_status(:ok)
          resp = JSON.parse(response.body)

          # Should have the standard attachment data
          expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])

          # Should NOT have LLM response data
          expect(resp).not_to have_key('llm_response')
        end

        it 'successfully processes LLM validation end-to-end' do
          # Mock background job launching to prevent OCR job from hanging
          allow_any_instance_of(IvcChampva::V1::UploadsController)
            .to receive(:launch_background_job)

          # Disable PDF conversion on upload for this test (not testing that feature here)
          allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(false)

          # Mock Common::ConvertToPdf to avoid ImageMagick issues in test environment
          dummy_pdf_path = Rails.root.join('tmp', 'test_converted.pdf').to_s
          allow_any_instance_of(Common::ConvertToPdf).to receive(:run).and_return(dummy_pdf_path)

          # Mock file existence check for LlmService.validate_file_exists
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(dummy_pdf_path).and_return(true)

          data = { form_id: '10-7959A', file:, attachment_id: 'test_document' }

          post '/ivc_champva/v1/forms/submit_supporting_documents', params: data

          expect(response).to have_http_status(:ok)
          resp = JSON.parse(response.body)

          # Should have the standard attachment data
          expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])

          # Should have LLM response data from MockClient
          expect(resp).to have_key('llm_response')
          expect(resp['llm_response']).to include(
            'doc_type' => 'EOB',
            'doc_type_matches' => true,
            'valid' => false,
            'confidence' => 0.9
          )
        end
      end

      context 'when LLM conditions are not met' do
        before do
          allow(Flipper).to receive(:enabled?).with(:champva_claims_llm_validation, @current_user).and_return(false)
        end

        it 'does not include llm_response when flipper is disabled' do
          data = { form_id: '10-7959A', file:, attachment_id: 'test_document' }

          post '/ivc_champva/v1/forms/submit_supporting_documents', params: data

          expect(response).to have_http_status(:ok)
          resp = JSON.parse(response.body)

          # Should have the standard attachment data
          expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])

          # Should NOT have LLM response data
          expect(resp).not_to have_key('llm_response')
        end
      end
    end

    context 'with an invalid form_id' do
      it 'returns an error' do
        post '/ivc_champva/v1/forms/submit_supporting_documents', params: { form_id: 'invalid', file: }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with an invalid file format' do
      it 'raises a validation error' do
        allow_any_instance_of(PersistentAttachments::MilitaryRecords).to receive(:valid?).and_return(false)
        post '/ivc_champva/v1/forms/submit_supporting_documents', params: { form_id: '10-10D', file: }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe '#submit_docs_only_resubmission' do
    let(:claim_uuid) { SecureRandom.uuid }
    let!(:claim_form) do
      create(
        :ivc_champva_form,
        form_uuid: claim_uuid,
        first_name: 'Pat',
        last_name: 'Veteran',
        email: 'pat@example.com',
        request_json: {
          'veteran' => {
            'ssn_or_tin' => '411111111',
            'date_of_birth' => '01-01-1958'
          },
          'applicants' => [
            {
              'applicant_name' => { 'first' => 'Sam', 'last' => 'Beneficiary' },
              'applicant_dob' => '01-04-2003'
            }
          ]
        }.to_json
      )
    end
    let!(:newer_claim_form_same_uuid) do
      create(
        :ivc_champva_form,
        form_uuid: claim_uuid,
        first_name: 'Pat',
        last_name: 'Veteran',
        email: 'pat@example.com',
        request_json: {
          'veteran' => {
            'ssn_or_tin' => '411111111',
            'date_of_birth' => '01-01-1958'
          },
          'applicants' => [
            {
              'applicant_name' => { 'first' => 'Sam', 'last' => 'Beneficiary' },
              'applicant_dob' => '01-04-2003'
            }
          ]
        }.to_json
      )
    end
    let!(:evidence_submission) do
      EvidenceSubmission.create!(
        claim_id: claim_form.id,
        user_account: create(:user_account),
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED],
        template_metadata: {
          personalisation: {
            file_name: 'birth-certificate.png',
            document_type: 'Birth certificate'
          }
        }.to_json
      )
    end
    let(:payload) do
      {
        form_number: '10-10D-EXTENDED',
        submission_type: 'existing',
        claim_id: claim_uuid,
        certifier_role: 'sponsor',
        veteran: {
          full_name: { first: 'Pat', last: 'Veteran' },
          ssn_or_tin: '411111111',
          date_of_birth: '01-01-1958'
        },
        applicants: [
          {
            applicant_name: { first: 'Sam', last: 'Beneficiary' },
            applicant_dob: '01-04-2003'
          }
        ],
        primary_contact_info: {
          email: 'pat@example.com',
          name: { first: 'Pat', last: 'Contact' }
        },
        certification: { date: '04-01-2026' },
        statement_of_truth_signature: 'Certifier Jones',
        supporting_docs: [
          {
            confirmation_code: 'd1fde9a6-b48f-4763-9cd5-9f06f32a6b56',
            attachment_id: 'Birth certificate',
            name: 'birth-certificate.png'
          }
        ]
      }
    end

    before do
      allow(PersistentAttachments::MilitaryRecords).to receive(:exists?).and_return(true)
    end

    it 'accepts docs-only resubmission when the flow is enabled' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything).and_return(true)
      allow_any_instance_of(IvcChampva::V1::UploadsController)
        .to receive(:handle_file_uploads_wrapper)
        .and_return({ json: {}, status: 200 })

      post '/ivc_champva/v1/forms/docs_only_resubmission', params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(evidence_submission.reload.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
    end

    it 'returns 422 when docs-only flow is disabled' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything).and_return(false)

      post '/ivc_champva/v1/forms/docs_only_resubmission', params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error_message']).to include('not enabled')
    end

    it 'hydrates applicant_dob from source request_json when missing in payload' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything).and_return(true)
      allow_any_instance_of(IvcChampva::V1::UploadsController)
        .to receive(:handle_file_uploads_wrapper)
        .and_return({ json: {}, status: 200 })

      bad_payload = payload.deep_dup
      bad_payload[:applicants][0].delete(:applicant_dob)

      post '/ivc_champva/v1/forms/docs_only_resubmission', params: bad_payload, as: :json

      expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    end

    it 'hydrates veteran ssn_or_tin from source request_json when missing in payload' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything).and_return(true)
      allow_any_instance_of(IvcChampva::V1::UploadsController)
        .to receive(:handle_file_uploads_wrapper)
        .and_return({ json: {}, status: 200 })

      bad_payload = payload.deep_dup
      bad_payload[:veteran].delete(:ssn_or_tin)

      post '/ivc_champva/v1/forms/docs_only_resubmission', params: bad_payload, as: :json

      expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    end

    it 'hydrates applicant_dob when payload uses applicantName camelCase' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:champva_cst_file_uploader_docs_only_resubmission, anything).and_return(true)
      allow_any_instance_of(IvcChampva::V1::UploadsController)
        .to receive(:handle_file_uploads_wrapper)
        .and_return({ json: {}, status: 200 })

      bad_payload = payload.deep_dup
      bad_payload[:applicants] = [
        {
          applicantName: { first: 'Sam', last: 'Beneficiary' }
        }
      ]

      post '/ivc_champva/v1/forms/docs_only_resubmission', params: bad_payload, as: :json

      expect(response).to have_http_status(:ok), -> { "body=#{response.body}" }
    end
  end

  describe '#unlock_file' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:file) { fixture_file_upload('locked_pdf_password_is_test.pdf') }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, @current_user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_use_hexapdf_to_unlock_pdfs, @current_user).and_return(true)
    end

    context 'with locked PDF and no provided password' do
      let(:locked_file) { fixture_file_upload('locked_pdf_password_is_test.pdf', 'application/pdf') }

      it 'rejects locked PDFs if no password is provided' do
        post '/ivc_champva/v1/forms/submit_supporting_documents', params: { form_id: '10-10D', file: locked_file }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(
          response.parsed_body['errors'].first['title']
        ).to eq("File #{I18n.t('errors.messages.uploads.pdf.invalid')}")
      end

      it 'accepts locked PDFs with the correct password' do
        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: locked_file, password: 'test' }
        expect(response).to have_http_status(:ok)
      end

      it 'rejects locked PDFs with the incorrect password' do
        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: locked_file, password: 'bad' }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors'].first['detail']).to eq(
          IvcChampva::Constants::INCORRECT_PASSWORD_DETAIL
        )
      end
    end

    it 'handles non-PDF files' do
      non_pdf_file = fixture_file_upload('doctors-note.gif')
      expect(controller.send(:unlock_file, non_pdf_file, nil)).to eq(non_pdf_file)
    end

    it 'handles PDFs with no password' do
      expect(controller.send(:unlock_file, file, nil)).to eq(file)
    end
  end

  describe '#unlock_file via pdftk' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:file) { fixture_file_upload('locked_pdf_password_is_test.pdf') }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, @current_user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_use_hexapdf_to_unlock_pdfs, @current_user).and_return(false)
    end

    context 'with locked PDF and no provided password' do
      let(:locked_file) { fixture_file_upload('locked_pdf_password_is_test.pdf', 'application/pdf') }

      it 'rejects locked PDFs if no password is provided' do
        post '/ivc_champva/v1/forms/submit_supporting_documents', params: { form_id: '10-10D', file: locked_file }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(
          response.parsed_body['errors'].first['title']
        ).to eq("File #{I18n.t('errors.messages.uploads.pdf.invalid')}")
      end

      it 'accepts locked PDFs with the correct password' do
        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: locked_file, password: 'test' }
        expect(response).to have_http_status(:ok)
      end

      it 'rejects locked PDFs with the incorrect password' do
        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: locked_file, password: 'bad' }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors'].first['detail']).to eq(
          IvcChampva::Constants::INCORRECT_PASSWORD_DETAIL
        )
      end
    end

    it 'handles non-PDF files' do
      non_pdf_file = fixture_file_upload('doctors-note.gif')
      expect(controller.send(:unlock_file, non_pdf_file, nil)).to eq(non_pdf_file)
    end

    it 'handles PDFs with no password' do
      expect(controller.send(:unlock_file, file, nil)).to eq(file)
    end
  end

  describe '#cleanup_supporting_doc_working_files' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    it 'removes tmp supporting_doc working files and keeps unrelated files' do
      supporting_path = Rails.root.join('tmp', "#{SecureRandom.uuid}_vha_10_10d_supporting_doc-0.pdf").to_s
      unrelated_path = Rails.root.join('tmp', "#{SecureRandom.uuid}_metadata.json").to_s

      File.write(supporting_path, 'supporting-temp')
      File.write(unrelated_path, 'keep-me')

      controller.send(:cleanup_supporting_doc_working_files, [supporting_path, unrelated_path, nil, ''])

      expect(File.exist?(supporting_path)).to be(false)
      expect(File.exist?(unrelated_path)).to be(true)

      FileUtils.rm_f(unrelated_path)
    end
  end

  describe '#convert_to_pdf' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:clamscan) { double(safe?: true) }
    let(:source_pdf_path) { Rails.root.join('spec', 'fixtures', 'files', 'attachment.pdf').to_s }

    before do
      allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
      # Allow all Flipper calls through by default, then override specific ones in contexts
      allow(Flipper).to receive(:enabled?).and_return(false)
    end

    context 'when feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(true)
      end

      it 'converts image files to PDF at upload time' do
        image_file = fixture_file_upload('doctors-note.png', 'image/png')

        # Create a temp file that mimics what ConvertToPdf would return
        temp_pdf = Tempfile.new(['converted', '.pdf'])
        FileUtils.cp(source_pdf_path, temp_pdf.path)

        allow_any_instance_of(Common::ConvertToPdf).to receive(:run).and_return(temp_pdf.path)

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: image_file }

        expect(response).to have_http_status(:ok)

        attachment = PersistentAttachment.last
        expect(attachment.file.content_type).to eq('application/pdf')
        expect(attachment.original_filename).to end_with('.pdf')
      ensure
        temp_pdf&.close
        temp_pdf&.unlink
      end

      it 'preserves the original filename with pdf extension' do
        image_file = fixture_file_upload('doctors-note.png', 'image/png')

        # Create a temp file that mimics what ConvertToPdf would return
        temp_pdf = Tempfile.new(['converted', '.pdf'])
        FileUtils.cp(source_pdf_path, temp_pdf.path)

        allow_any_instance_of(Common::ConvertToPdf).to receive(:run).and_return(temp_pdf.path)

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: image_file }

        expect(response).to have_http_status(:ok)

        attachment = PersistentAttachment.last
        expect(attachment.original_filename).to eq('doctors-note.pdf')
      ensure
        temp_pdf&.close
        temp_pdf&.unlink
      end

      it 'skips conversion for files that are already PDFs' do
        pdf_file = fixture_file_upload('attachment.pdf', 'application/pdf')

        # pre_convert_to_pdf! should return early when content_type is application/pdf
        # so ConvertToPdf should never be instantiated
        expect(Common::ConvertToPdf).not_to receive(:new)

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: pdf_file }

        expect(response).to have_http_status(:ok)

        attachment = PersistentAttachment.last
        expect(attachment.file.content_type).to eq('application/pdf')
      end
    end

    context 'when feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(false)
      end

      it 'does not convert image files to PDF at upload time' do
        image_file = fixture_file_upload('doctors-note.png', 'image/png')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: image_file }

        expect(response).to have_http_status(:ok)

        attachment = PersistentAttachment.last
        expect(attachment.file.content_type).to eq('image/png')
        expect(attachment.original_filename).to eq('doctors-note.png')
      end
    end

    context 'when conversion fails' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(true)
        allow_any_instance_of(Common::ConvertToPdf).to receive(:run).and_raise(StandardError, 'Conversion failed')
      end

      it 'raises an error and returns internal server error' do
        image_file = fixture_file_upload('doctors-note.png', 'image/png')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: image_file }

        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'HEIC/HEIF upload support' do
    let(:clamscan) { double(safe?: true) }
    let(:source_pdf_path) { Rails.root.join('spec', 'fixtures', 'files', 'attachment.pdf').to_s }

    before do
      allow(Common::VirusScan).to receive(:scan).and_return(clamscan)
      allow(Flipper).to receive(:enabled?).and_return(false)
    end

    context 'when champva_heif_attachments_enabled is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_heif_attachments_enabled, anything).and_return(true)
      end

      it 'accepts HEIC files as supporting documents' do
        heic_file = fixture_file_upload('test_fixture.heic', 'image/heic')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: heic_file }

        expect(response).to have_http_status(:ok)
        expect(PersistentAttachment.last).to be_a(PersistentAttachments::MilitaryRecords)
      end

      it 'accepts HEIF files as supporting documents' do
        heif_file = fixture_file_upload('test_fixture.heif', 'image/heif')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: heif_file }

        expect(response).to have_http_status(:ok)
        expect(PersistentAttachment.last).to be_a(PersistentAttachments::MilitaryRecords)
      end

      context 'with convert_to_pdf_on_upload enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:champva_convert_to_pdf_on_upload, anything).and_return(true)
        end

        it 'converts HEIC to PDF at upload time' do
          heic_file = fixture_file_upload('test_fixture.heic', 'image/heic')

          temp_pdf = Tempfile.new(['converted', '.pdf'])
          FileUtils.cp(source_pdf_path, temp_pdf.path)
          allow_any_instance_of(Common::ConvertToPdf).to receive(:run).and_return(temp_pdf.path)

          post '/ivc_champva/v1/forms/submit_supporting_documents',
               params: { form_id: '10-10D', file: heic_file }

          expect(response).to have_http_status(:ok)

          attachment = PersistentAttachment.last
          expect(attachment.file.content_type).to eq('application/pdf')
          expect(attachment.original_filename).to end_with('.pdf')
        ensure
          temp_pdf&.close
          temp_pdf&.unlink
        end
      end
    end

    context 'when champva_heif_attachments_enabled is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_heif_attachments_enabled, anything).and_return(false)
      end

      it 'rejects HEIC files' do
        heic_file = fixture_file_upload('test_fixture.heic', 'image/heic')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: heic_file }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects HEIF files' do
        heif_file = fixture_file_upload('test_fixture.heif', 'image/heif')

        post '/ivc_champva/v1/forms/submit_supporting_documents',
             params: { form_id: '10-10D', file: heif_file }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe '#content_type_from_extension' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    it 'returns image/heic for .heic' do
      expect(controller.send(:content_type_from_extension, '.heic')).to eq('image/heic')
    end

    it 'returns image/heif for .heif' do
      expect(controller.send(:content_type_from_extension, '.heif')).to eq('image/heif')
    end

    it 'returns image/jpeg for .jpg' do
      expect(controller.send(:content_type_from_extension, '.jpg')).to eq('image/jpeg')
    end

    it 'returns application/octet-stream for unknown extensions' do
      expect(controller.send(:content_type_from_extension, '.xyz')).to eq('application/octet-stream')
    end
  end

  describe '#get_form_id' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    it 'returns the correct form ID for a valid form number' do
      allow(controller).to receive(:params).and_return({ form_number: '10-10D' })
      form_id = controller.send(:get_form_id)

      expect(form_id).to eq('vha_10_10d')
    end

    it 'raises an error for a missing form number' do
      allow(controller).to receive(:params).and_return({})
      expect { controller.send(:get_form_id) }.to raise_error('Missing/malformed form_number in params')
    end
  end

  # NOTE: #get_attachment_ids_and_form was removed from the controller during the
  # DataTransformations refactor. Attachment ID building is now tested via:
  #   - spec/services/data_transformations_spec.rb (default logic)
  #   - spec/services/claims_attachment_ids_spec.rb (DTA/CVA/PDI overrides)
  # The metadata generation tests below remain here as they test form model behavior directly.

  describe 'resubmission metadata generation' do
    context 'when PDI number is selected' do
      let(:pdi_form_data) do
        {
          'form_number' => '10-7959A',
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'PDI number',
          'identifying_number' => 'PDI123456',
          'applicant_name' => { 'first' => 'Test', 'last' => 'User' },
          'applicant_address' => { 'postal_code' => '12345' },
          'applicant_member_number' => '123456789',
          'primary_contact_info' => { 'email' => 'test@example.com' }
        }
      end

      it 'includes pdi_number in metadata and excludes claim_number' do
        form = IvcChampva::VHA107959a.new(pdi_form_data)
        metadata = form.metadata

        expect(metadata['pdi_number']).to eq('PDI123456')
        expect(metadata['claim_number']).to be_nil
        expect(metadata['pdi_or_claim_number']).to eq('PDI number')
        expect(metadata['claim_status']).to eq('resubmission')
      end
    end

    context 'when Control number is selected' do
      let(:claim_form_data) do
        {
          'form_number' => '10-7959A',
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'Control number',
          'identifying_number' => 'CLAIM789',
          'applicant_name' => { 'first' => 'Test', 'last' => 'User' },
          'applicant_address' => { 'postal_code' => '12345' },
          'applicant_member_number' => '123456789',
          'primary_contact_info' => { 'email' => 'test@example.com' }
        }
      end

      it 'includes claim_number in metadata and excludes pdi_number' do
        form = IvcChampva::VHA107959a.new(claim_form_data)
        metadata = form.metadata

        expect(metadata['claim_number']).to eq('CLAIM789')
        expect(metadata['pdi_number']).to be_nil
        expect(metadata['pdi_or_claim_number']).to eq('Control number')
        expect(metadata['claim_status']).to eq('resubmission')
      end
    end
  end

  describe '7959A PDI resubmission end-to-end S3 upload' do
    let(:base_fixture) do
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959a.json')
      JSON.parse(fixture_path.read)
    end
    let(:pdi_resubmission_data) do
      base_fixture.merge(
        'form_number' => '10-7959A',
        'claim_status' => 'resubmission',
        'pdi_or_claim_number' => 'PDI number',
        'identifying_number' => 'PDI123456'
      )
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_resubmission_attachment_ids).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_log_all_s3_uploads, anything).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, anything).and_return(false)

      # Mock supporting document records (uses confirmation_codes from fixture)
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record', created_at: 1.day.ago, id: 'some_uuid', file: double(id: 'file0')))

      # Mock IvcChampvaForm
      mock_form = double(first_name: 'Veteran', last_name: 'Surname', form_uuid: 'some_uuid')
      allow(IvcChampvaForm).to receive(:first).and_return(mock_form)
    end

    it 'uploads documents to S3 with all documents labeled CVA Bene Response' do
      s3_uploads = []

      # Capture all S3 put_object calls to verify attachment_ids
      allow_any_instance_of(Aws::S3::Client).to receive(:put_object) do |_client, params|
        s3_uploads << params[:metadata]
        double('response', context: double('context', http_response: double('http_response', status_code: 200)))
      end

      post '/ivc_champva/v1/forms', params: pdi_resubmission_data

      expect(response).to have_http_status(:ok)

      # Filter out any uploads without attachment_id (like metadata JSON)
      doc_uploads = s3_uploads.select { |m| m&.key?('attachment_id') }

      # All document uploads should have "CVA Bene Response" attachment_id
      expect(doc_uploads).not_to be_empty
      doc_uploads.each do |upload|
        expect(upload['attachment_id']).to eq('CVA Bene Response')
      end
    end
  end

  # NOTE: #supporting_document_ids moved to DataTransformations mixin.
  # See spec/services/data_transformations_spec.rb for unit tests.

  describe '#get_file_paths_and_metadata' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_send_ves_to_pega, anything).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, anything).and_return(false)
    end

    form_numbers_and_classes.each do |form_number, form_class|
      context "when form_number is #{form_number}" do
        let(:parsed_form_data) do
          {
            'form_number' => form_number,
            'supporting_docs' => [
              { 'attachment_id' => 'doc1' },
              { 'attachment_id' => 'doc2' }
            ]
          }
        end

        it 'returns the correct file paths, metadata, and attachment IDs' do
          form_instance = form_class.new({})
          allow(controller).to receive(:get_form_id).and_return("vha_#{form_number.tr('-', '_').downcase}")
          allow(IvcChampva::FormVersionManager).to receive(:create_form_instance).and_return(form_instance)
          allow(form_instance).to receive_messages(
            prepare_submission_data: [%w[doc1 doc2], nil],
            validated_metadata: { 'metadata' => {} },
            handle_attachments: ['file_path']
          )
          allow(controller).to receive(:track_form_submission_metrics)
          allow_any_instance_of(IvcChampva::PdfFiller).to receive(:generate).and_return('file_path')

          file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

          expect(file_paths).to eq(['file_path'])
          expect(metadata).to eq({ 'metadata' => {}, 'attachment_ids' => %w[doc1 doc2] })
        end
      end
    end
  end

  describe '#get_docs_only_resubmission_file_paths_and_metadata' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:claim_uuid) { SecureRandom.uuid }
    let(:parsed_form_data) do
      {
        'form_number' => '10-10D-EXTENDED',
        'submission_type' => 'existing',
        'claim_id' => claim_uuid,
        'supporting_docs' => [{ 'confirmation_code' => 'abc', 'attachment_id' => 'Birth certificate' }]
      }
    end
    let(:form_instance) do
      double('FormInstance',
             metadata: { 'uuid' => SecureRandom.uuid },
             supporting_document_ids: ['Birth certificate'])
    end

    before do
      allow(controller).to receive(:form_id_for_form_number).with('10-10D-EXTENDED').and_return('vha_10_10d')
      allow(IvcChampva::FormVersionManager).to receive(:create_form_instance).and_return(form_instance)
      allow(controller).to receive(:track_form_submission_metrics)
      allow(form_instance).to receive(:uuid=)
      allow(controller).to receive(:docs_only_resubmission_supporting_paths_from_form)
        .and_return(['/tmp/supporting.pdf'])
      allow(IvcChampva::MetadataValidator).to receive(:validate) { |metadata| metadata }
    end

    it 'reuses the original claim UUID so supporting docs append to the existing case' do
      _file_paths, metadata = controller.send(:get_docs_only_resubmission_file_paths_and_metadata, parsed_form_data)

      expect(metadata['uuid']).to eq(claim_uuid)
      expect(metadata['docType']).to eq('10-10D-EXTENDED-EXISTING')
      expect(metadata['attachment_ids']).to eq(['Birth certificate'])
      expect(form_instance).to have_received(:uuid=).with(claim_uuid).once
    end
  end

  describe '#build_json' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    context 'when all status codes are 200' do
      it 'returns a status of 200' do
        expect(controller.send(:build_json, [200, 200], [nil, nil])).to eq({ json: {}, status: 200 })
      end
    end

    context 'when all status codes are 400' do
      it 'returns a status of 400 and an error message' do
        expect(controller.send(:build_json, [400, 400], %w[Error Error])).to eq({ json:
        { error_message: %w[Error Error] }, status: 400 })
      end
    end

    context 'when status codes include a 400' do
      it 'returns a status of 400' do
        expect(controller.send(:build_json, [200, 400], [nil, 'Error'])).to eq({ json:
        { error_message: [nil, 'Error'] }, status: 400 })
      end
    end

    context 'when status codes do not include 200 or 400' do
      it 'returns a status of 500' do
        expect(controller.send(:build_json, [300, 500], ['Multiple Choices', 'Error'])).to eq({ json:
        { error_message: 'An unknown error occurred while uploading document(s).' }, status: 500 })
      end
    end

    context 'when status codes are nil' do
      it 'handles nil values and returns a 500 error' do
        expect(controller.send(:build_json, nil, nil)).to eq({ json:
        { error_message: 'An unknown error occurred while uploading document(s).' }, status: 500 })
      end
    end
  end

  describe '#should_retry?' do
    let(:controller) { IvcChampva::V1::UploadsController.new }

    it 'returns true for retryable errors within max attempts' do
      retryable_errors = [
        'failed to generate file',
        'no such file or directory',
        'an error occurred while verifying stamp: some error',
        'unable to find file'
      ]

      retryable_errors.each do |error_message|
        expect(controller.send(:should_retry?, error_message.downcase, 1, 3)).to be true
      end
    end

    it 'returns false for non-retryable errors' do
      non_retryable_errors = [
        'some other error',
        'random error message'
      ]

      non_retryable_errors.each do |error_message|
        expect(controller.send(:should_retry?, error_message.downcase, 1, 3)).to be false
      end
    end

    it 'returns false when max attempts exceeded' do
      error_message = 'failed to generate file'
      expect(controller.send(:should_retry?, error_message.downcase, 4, 3)).to be false
    end
  end

  describe '#handle_file_uploads' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:form_id) { 'vha_10_10d' }
    let(:file_paths) { ['/path/to/file1.pdf', '/path/to/file2.pdf'] }
    let(:metadata) { { 'attachment_ids' => %w[id1 id2], 'uuid' => SecureRandom.uuid } }
    let(:file_uploader) { instance_double(IvcChampva::FileUploader, metadata:) }

    before do
      allow(IvcChampva::FileUploader).to receive(:new).and_return(file_uploader)
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
    end

    context 'when the retry method fails outside the retry block' do
      before do
        allow(IvcChampva::Retry).to receive(:do).and_raise(StandardError.new('Catastrophic failure'))
      end

      it 'raises the error' do
        expect do
          controller.send(:handle_file_uploads, form_id, file_paths, metadata)
        end.to raise_error(StandardError, 'Catastrophic failure')
      end
    end

    context 'when the retry method executes successfully' do
      before do
        allow(IvcChampva::Retry).to receive(:do).and_yield
        allow(file_uploader).to receive(:handle_uploads).and_return([[200, nil]])
      end

      it 'returns the values from handle_uploads' do
        statuses, error_messages = controller.send(:handle_file_uploads, form_id, file_paths, metadata)
        expect(statuses).to eq([200])
        expect(error_messages).to eq([nil])
      end
    end
  end

  # NOTE: #add_blank_doc_and_stamp and #build_stamped_page moved to DataTransformations mixin.
  # See spec/services/data_transformations_spec.rb for unit tests.

  describe '#validate_mpi_profiles' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:parsed_form_data) do
      JSON.parse(Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read)
    end
    let(:mock_mpi_service) { instance_double(IvcChampva::MPIService) }

    before do
      allow(IvcChampva::MPIService).to receive(:new).and_return(mock_mpi_service)
      allow(mock_mpi_service).to receive(:validate_profiles)
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
    end

    context 'when flipper is enabled and form_id is vha_10_10d' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:champva_mpi_validation, nil)
          .and_return(true)
      end

      it 'calls MpiService.validate_profiles' do
        controller.send(:validate_mpi_profiles, parsed_form_data, 'vha_10_10d')

        expect(IvcChampva::MPIService).to have_received(:new).with(no_args)
        expect(mock_mpi_service).to have_received(:validate_profiles).with(parsed_form_data)
      end
    end

    context 'when flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:champva_mpi_validation, nil)
          .and_return(false)
      end

      it 'does not call MpiService.validate_profiles' do
        controller.send(:validate_mpi_profiles, parsed_form_data, 'vha_10_10d')

        expect(IvcChampva::MPIService).not_to have_received(:new)
        expect(mock_mpi_service).not_to have_received(:validate_profiles)
      end
    end

    context 'when form_id is not vha_10_10d' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:champva_mpi_validation, nil)
          .and_return(true)
      end

      it 'does not call MpiService.validate_profiles' do
        controller.send(:validate_mpi_profiles, parsed_form_data, 'vha_10_7959c')

        expect(IvcChampva::MPIService).not_to have_received(:new)
        expect(mock_mpi_service).not_to have_received(:validate_profiles)
      end
    end

    context 'when MpiService raises an error' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:champva_mpi_validation, nil)
          .and_return(true)
        allow(mock_mpi_service).to receive(:validate_profiles)
          .and_raise(StandardError.new('MPI service error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and does not raise' do
        expect do
          controller.send(:validate_mpi_profiles, parsed_form_data, 'vha_10_10d')
        end.not_to raise_error

        expect(Rails.logger).to have_received(:error).with('Error validating MPI profiles: MPI service error')
      end
    end
  end

  describe '#generate_ves_json_file' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:parsed_form_data) do
      JSON.parse(Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read)
    end
    let(:mock_form) { double('Form', form_id: 'vha_10_10d', uuid: 'test-uuid-123') }
    let(:mock_ves_request) { double('VesRequest') }

    before do
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
      allow(IvcChampva::VesDataFormatter).to receive(:format_for_request).and_return(mock_ves_request)
      allow(mock_ves_request).to receive(:to_json).and_return('{"test": "data"}')
      allow(File).to receive(:write)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    it 'generates VES JSON file and returns file path' do
      expected_path = Rails.root.join("tmp/#{mock_form.uuid}_#{mock_form.form_id}_ves.json").to_s
      result = controller.send(:generate_ves_json_file, mock_form, parsed_form_data)

      expect(result).to eq(expected_path)
      expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
        .with(parsed_form_data, form_uuid: mock_form.uuid)
      expect(File).to have_received(:write).with(
        expected_path,
        '{"test": "data"}'
      )
      expect(Rails.logger).to have_received(:info).with(
        "VES JSON file generated for form #{mock_form.form_id}: #{expected_path}"
      )
    end

    context 'when VES data generation fails' do
      before do
        allow(IvcChampva::VesDataFormatter).to receive(:format_for_request)
          .and_raise(StandardError.new('VES formatting error'))
      end

      it 'logs the error and returns nil' do
        result = controller.send(:generate_ves_json_file, mock_form, parsed_form_data)

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error)
          .with('Error generating VES JSON file for form vha_10_10d: VES formatting error')
        expect(File).not_to have_received(:write)
      end
    end
  end

  describe '#generate_ves_json_files' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:mock_form) { double('Form', form_id: 'vha_10_10d', uuid: 'test-uuid-123') }
    let(:mock_ves_request) { double('VesRequest') }
    let(:mock_ohi_request) { double('VesOhiRequest') }

    before do
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
      allow(mock_ves_request).to receive(:to_json).and_return('{"test": "1010d_data"}')
      allow(mock_ohi_request).to receive(:to_json).and_return('{"test": "ohi_data"}')
      allow(IvcChampva::VesDataFormatter).to receive_messages(format_for_request: mock_ves_request,
                                                              format_for_ohi_request: [mock_ohi_request])
      allow(File).to receive(:write)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    context 'with form_number 10-10D' do
      let(:parsed_form_data) { { 'form_number' => '10-10D' } }

      it 'generates a single VES JSON file' do
        results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

        expect(results.size).to eq(1)
        expect(results.first[:attachment_id]).to eq('VES JSON')
        expect(results.first[:path]).to end_with('_ves.json')
        expect(IvcChampva::VesDataFormatter).to have_received(:format_for_request)
      end
    end

    context 'with form_number 10-10D-EXTENDED' do
      let(:parsed_form_data) { { 'form_number' => '10-10D-EXTENDED' } }

      it 'generates VES JSON + OHI VES JSON files' do
        results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

        expect(results.size).to eq(2)
        expect(results.first[:attachment_id]).to eq('VES JSON')
        expect(results.last[:attachment_id]).to eq('VES OHI JSON')
      end

      context 'with no OHI applicants' do
        before do
          allow(IvcChampva::VesDataFormatter).to receive(:format_for_ohi_request).and_return([])
        end

        it 'returns only the 10-10D VES JSON' do
          results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

          expect(results.size).to eq(1)
          expect(results.first[:attachment_id]).to eq('VES JSON')
        end
      end
    end

    context 'with form_number 10-7959C' do
      let(:parsed_form_data) { { 'form_number' => '10-7959C' } }

      it 'generates OHI VES JSON files only' do
        results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

        expect(results.size).to eq(1)
        expect(results.first[:attachment_id]).to eq('VES OHI JSON')
        expect(results.first[:path]).to include('_ohi_ves_')
        expect(IvcChampva::VesDataFormatter).not_to have_received(:format_for_request)
      end

      context 'with no OHI applicants' do
        before do
          allow(IvcChampva::VesDataFormatter).to receive(:format_for_ohi_request).and_return([])
        end

        it 'returns empty array' do
          results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

          expect(results).to eq([])
        end
      end

      context 'with multiple OHI applicants' do
        let(:second_ohi_request) { double('VesOhiRequest2') }

        before do
          allow(second_ohi_request).to receive(:to_json).and_return('{"test": "ohi_data_2"}')
          allow(IvcChampva::VesDataFormatter).to receive(:format_for_ohi_request)
            .and_return([mock_ohi_request, second_ohi_request])
        end

        it 'generates one file per OHI applicant' do
          results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

          expect(results.size).to eq(2)
          expect(results.all? { |r| r[:attachment_id] == 'VES OHI JSON' }).to be true
          expect(results.first[:path]).to include('_ohi_ves_0')
          expect(results.last[:path]).to include('_ohi_ves_1')
        end
      end
    end

    context 'with unknown form_number' do
      let(:parsed_form_data) { { 'form_number' => '10-7959A' } }

      it 'returns empty array' do
        results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

        expect(results).to eq([])
      end
    end

    context 'when write_1010d_ves_json fails' do
      let(:parsed_form_data) { { 'form_number' => '10-10D' } }

      before do
        allow(IvcChampva::VesDataFormatter).to receive(:format_for_request)
          .and_raise(StandardError.new('formatting error'))
      end

      it 'logs the error via the helper and returns empty results' do
        results = controller.send(:generate_ves_json_files, mock_form, parsed_form_data)

        expect(results).to eq([])
        expect(Rails.logger).to have_received(:error)
          .with(/Error writing 1010d VES JSON: formatting error/)
      end
    end
  end

  describe '#get_file_paths_and_metadata VES JSON integration' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:parsed_form_data) do
      JSON.parse(Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read)
    end
    let(:mock_form) { double('Form', form_id: 'vha_10_10d', uuid: 'test-uuid-123', data: {}, metadata: {}) }

    before do
      allow(controller).to receive(:instance_variable_get).with('@current_user').and_return(nil)
      allow(controller).to receive(:get_form_id).and_return('vha_10_10d')
      allow(controller).to receive_messages(should_generate_ves_json?: false,
                                            track_form_submission_metrics: nil)
      allow(controller).to receive(:generate_ves_json_file)
      allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(false)
      allow(IvcChampva::FormVersionManager).to receive_messages(create_form_instance: mock_form,
                                                                get_legacy_form_id: 'vha_10_10d')
      allow_any_instance_of(IvcChampva::PdfFiller).to receive(:generate).and_return('test_path.pdf')
      allow(mock_form).to receive_messages(prepare_submission_data: [['doc1'], nil], validated_metadata: {},
                                           handle_attachments: ['test_path.pdf'])
    end

    context 'when VES JSON generation conditions are met (old flag path)' do
      let(:expected_ves_path) { Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ves.json').to_s }

      before do
        allow(controller).to receive(:should_generate_ves_json?).with('vha_10_10d').and_return(true)
        allow(controller).to receive(:generate_ves_json_file).and_return(expected_ves_path)
      end

      it 'generates VES JSON file and adds it to file_paths and attachment_ids' do
        file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).to have_received(:should_generate_ves_json?).with('vha_10_10d')
        expect(controller).to have_received(:generate_ves_json_file).with(mock_form, parsed_form_data)
        expect(file_paths).to include(expected_ves_path)
        expect(metadata['attachment_ids']).to include('VES JSON')
      end
    end

    context 'when VES JSON generation conditions are not met' do
      before do
        allow(controller).to receive(:should_generate_ves_json?).with('vha_10_10d').and_return(false)
      end

      it 'does not generate VES JSON file' do
        file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).to have_received(:should_generate_ves_json?).with('vha_10_10d')
        expect(controller).not_to have_received(:generate_ves_json_file)
        expect(file_paths).not_to include('VES JSON')
        expect(metadata['attachment_ids']).not_to include('VES JSON')
      end
    end

    context 'when VES JSON generation fails (old flag path)' do
      before do
        allow(controller).to receive(:should_generate_ves_json?).with('vha_10_10d').and_return(true)
        allow(controller).to receive(:generate_ves_json_file).and_return(nil)
      end

      it 'does not add VES JSON to file_paths or attachment_ids' do
        file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).to have_received(:generate_ves_json_file).with(mock_form, parsed_form_data)
        expect(file_paths).not_to include(nil)
        expect(metadata['attachment_ids']).not_to include('VES JSON')
      end
    end

    context 'when champva_send_ohi_ves_to_pega is enabled (new flag path)' do
      let(:ves_json_path) { Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ves.json').to_s }
      let(:ohi_json_path) { Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ohi_ves_0.json').to_s }

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(true)
        allow(mock_form).to receive_messages(prepare_submission_data: [['vha_10_10d'], nil],
                                             handle_attachments: ['test-uuid-123_vha_10_10d-tmp.pdf'])
        allow(controller).to receive(:generate_ves_json_files)
          .and_return([{ path: ves_json_path, attachment_id: 'VES JSON' }])
      end

      it 'calls generate_ves_json_files and builds additional_file_metadata' do
        file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).to have_received(:generate_ves_json_files).with(mock_form, parsed_form_data)
        expect(file_paths).to include(ves_json_path)
        expect(metadata['attachment_ids']).to include('VES JSON')
        expect(metadata['additional_file_metadata']).to eq(
          'test-uuid-123_vha_10_10d.pdf' => { 'meta-jsonfile' => 'test-uuid-123_vha_10_10d_ves.json' }
        )
      end

      it 'does not call the old generate_ves_json_file' do
        controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).not_to have_received(:generate_ves_json_file)
      end

      context 'with multiple VES JSON files (EXTENDED)' do
        before do
          allow(controller).to receive(:generate_ves_json_files)
            .and_return([
                          { path: ves_json_path, attachment_id: 'VES JSON' },
                          { path: ohi_json_path, attachment_id: 'VES OHI JSON' }
                        ])
        end

        it 'adds all files and builds additional_file_metadata' do
          file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

          expect(file_paths).to include(ves_json_path, ohi_json_path)
          expect(metadata['attachment_ids']).to include('VES JSON', 'VES OHI JSON')
          pdf_meta = metadata.dig('additional_file_metadata', 'test-uuid-123_vha_10_10d.pdf')
          expect(pdf_meta).to include('meta-jsonfile' => 'test-uuid-123_vha_10_10d_ves.json')
        end
      end

      context 'with two OHI PDFs matched by attachment_id (EXTENDED)' do
        let(:ohi_pdf_one) { 'test-uuid-123_vha_10_10d_supporting_doc-1.pdf' }
        let(:ohi_pdf_two) { 'test-uuid-123_vha_10_10d_supporting_doc-2.pdf' }
        let(:ohi_json_one) do
          Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ohi_ves_0.json').to_s
        end
        let(:ohi_json_two) do
          Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ohi_ves_1.json').to_s
        end

        before do
          allow(mock_form).to receive_messages(
            prepare_submission_data: [
              ['vha_10_10d', 'VA form 10-7959c', 'VA form 10-7959c'], nil
            ],
            handle_attachments: ['test-uuid-123_vha_10_10d-tmp.pdf', ohi_pdf_one, ohi_pdf_two]
          )
          allow(controller).to receive(:generate_ves_json_files)
            .and_return([
                          { path: ves_json_path, attachment_id: 'VES JSON' },
                          { path: ohi_json_one, attachment_id: 'VES OHI JSON' },
                          { path: ohi_json_two, attachment_id: 'VES OHI JSON' }
                        ])
        end

        it 'maps each PDF to its corresponding VES JSON by position' do
          _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)
          afm = metadata['additional_file_metadata']

          expect(afm.dig('test-uuid-123_vha_10_10d.pdf', 'meta-jsonfile'))
            .to eq('test-uuid-123_vha_10_10d_ves.json')
          expect(afm.dig(ohi_pdf_one, 'meta-jsonfile'))
            .to eq('test-uuid-123_vha_10_10d_ohi_ves_0.json')
          expect(afm.dig(ohi_pdf_two, 'meta-jsonfile'))
            .to eq('test-uuid-123_vha_10_10d_ohi_ves_1.json')
        end
      end

      context 'when generate_ves_json_files returns empty' do
        before do
          allow(controller).to receive(:generate_ves_json_files).and_return([])
        end

        it 'does not add additional_file_metadata to metadata' do
          _file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

          expect(metadata).not_to have_key('additional_file_metadata')
        end
      end
    end

    context 'rollback safety: new flag off falls back to old flag path' do
      let(:expected_ves_path) { Rails.root.join('tmp', 'test-uuid-123_vha_10_10d_ves.json').to_s }

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_send_ohi_ves_to_pega, nil).and_return(false)
        allow(controller).to receive(:should_generate_ves_json?).with('vha_10_10d').and_return(true)
        allow(controller).to receive(:generate_ves_json_file).and_return(expected_ves_path)
      end

      it 'uses old generate_ves_json_file, not generate_ves_json_files' do
        allow(controller).to receive(:generate_ves_json_files)
        file_paths, metadata = controller.send(:get_file_paths_and_metadata, parsed_form_data)

        expect(controller).not_to have_received(:generate_ves_json_files)
        expect(controller).to have_received(:generate_ves_json_file).with(mock_form, parsed_form_data)
        expect(file_paths).to include(expected_ves_path)
        expect(metadata['attachment_ids']).to include('VES JSON')
        expect(metadata).not_to have_key('additional_file_metadata')
      end
    end
  end

  describe '#launch_background_job' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:file_path) { '/tmp/some_file.pdf' }
    let(:attachment_guid) { '12345' }
    let(:mock_file) do
      double('UploadedFile',
             original_filename: 'some_file.pdf',
             read: 'content',
             path: file_path,
             content_type: 'application/pdf').tap do |file|
        allow(file).to receive(:respond_to?).with(:original_filename).and_return(true)
        allow(file).to receive(:respond_to?).with(:content_type).and_return(true)
      end
    end
    let(:attachment) { double('PersistentAttachments::MilitaryRecords', id: 123, file: mock_file, guid: attachment_guid, to_pdf: file_path) }
    let(:tmpfile) { double('Tempfile', path: file_path, binmode: true, write: true, flush: true) }

    context 'when form_id is 10-7959A' do
      let(:form_id) { '10-7959A' }

      context 'when OCR feature is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, anything).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:champva_enable_llm_on_submit, anything).and_return(true)
        end

        it 'queues TesseractOcrLoggerJob with correct arguments' do
          job = class_double(IvcChampva::TesseractOcrLoggerJob).as_stubbed_const
          expect(job).to receive(:perform_async).with(
            form_id,
            attachment_guid,
            attachment.id,
            'EOB',
            anything
          )

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end

        it 'queues LlmLoggerJob with correct arguments' do
          llm_job = class_double(IvcChampva::LlmLoggerJob).as_stubbed_const
          expect(llm_job).to receive(:perform_async).with(
            form_id,
            attachment_guid,
            attachment.id, # attachment record ID instead of PDF path
            'EOB',
            anything
          )

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end
      end

      context 'when OCR feature is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, anything).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:champva_enable_llm_on_submit, anything).and_return(false)
        end

        it 'does not queue TesseractOcrLoggerJob' do
          job = class_double(IvcChampva::TesseractOcrLoggerJob).as_stubbed_const
          expect(job).not_to receive(:perform_async)

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end

        it 'does not queue LlmLoggerJob' do
          llm_job = class_double(IvcChampva::LlmLoggerJob).as_stubbed_const
          expect(llm_job).not_to receive(:perform_async)

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end
      end
    end

    context 'when form_id is not 10-7959A' do
      let(:form_id) { '10-10d' }

      context 'when OCR feature is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:champva_enable_ocr_on_submit, anything).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:champva_enable_llm_on_submit, anything).and_return(true)
        end

        it 'does not queue TesseractOcrLoggerJob' do
          job = class_double(IvcChampva::TesseractOcrLoggerJob).as_stubbed_const
          expect(job).not_to receive(:perform_async)

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end

        it 'does not queue LlmLoggerJob' do
          llm_job = class_double(IvcChampva::LlmLoggerJob).as_stubbed_const
          expect(llm_job).not_to receive(:perform_async)

          controller.send(:launch_background_job, attachment, form_id, 'EOB')
        end
      end
    end
  end

  describe '#tempfile_from_attachment' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:form_id) { '10-7959A' }
    let(:file_content) { 'test file content' }

    context 'when attachment.file responds to original_filename' do
      let(:mock_file) do
        double('UploadedFile',
               original_filename: 'some_file.gif',
               read: file_content)
      end

      let(:attachment) do
        instance_double(PersistentAttachments::MilitaryRecords, file: mock_file)
      end

      it 'creates a tempfile with the original filename and random code' do
        tmpfile = controller.send(:tempfile_from_attachment, attachment, form_id)

        expect(tmpfile).to be_a(Tempfile)
        expect(File.basename(tmpfile.path)).to match(/^10-7959A_attachment_[\w-]+\.gif$/)
        tmpfile.rewind
        expect(tmpfile.read).to eq(file_content)
        tmpfile.close
        tmpfile.unlink
      end
    end

    context 'when attachment.file does not respond to original_filename' do
      let(:mock_file) do
        double('File',
               path: '/tmp/some_other_file.png',
               read: file_content)
      end

      let(:attachment) do
        instance_double(PersistentAttachments::MilitaryRecords, file: mock_file)
      end

      it 'creates a tempfile with the basename and random code' do
        tmpfile = controller.send(:tempfile_from_attachment, attachment, form_id)

        expect(tmpfile).to be_a(Tempfile)
        expect(File.basename(tmpfile.path)).to match(/^10-7959A_attachment_[\w-]+\.png$/)
        tmpfile.rewind
        expect(tmpfile.read).to eq(file_content)
        tmpfile.close
        tmpfile.unlink
      end
    end
  end
end
