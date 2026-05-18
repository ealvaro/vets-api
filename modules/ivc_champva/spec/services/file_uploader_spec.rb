# frozen_string_literal: true

require 'rails_helper'

describe IvcChampva::FileUploader do
  let(:form_id) { '123' }
  let(:metadata) do
    { 'uuid' => '4171e61a-03b5-49f3-8717-dbf340310473',
      'attachment_ids' => ['Social Security card', 'Birth certificate', 'VES JSON'] }
  end
  let(:file_paths) do
    [
      'tmp/file1.pdf',
      'tmp/file2.png',
      'tmp/4171e61a-03b5-49f3-8717-dbf340310473_vha_10_10d_ves.json'
    ]
  end
  let(:insert_db_row) { false }
  let(:current_user) { nil }
  let(:parsed_form_data) { { 'form_number' => '10-10D', 'applicants' => [] } }
  let(:uploader) { IvcChampva::FileUploader.new(form_id, metadata, file_paths, insert_db_row:) }

  describe '#initialize' do
    context 'when champva_store_request_json flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_store_request_json, current_user).and_return(true)
      end

      it 'stores parsed_form_data when provided' do
        uploader_with_data = IvcChampva::FileUploader.new(
          form_id, metadata, file_paths,
          insert_db_row:, current_user:, parsed_form_data:
        )
        expect(uploader_with_data.instance_variable_get(:@parsed_form_data)).to eq(parsed_form_data)
      end

      it 'stores nil when parsed_form_data is not provided' do
        uploader_without_data = IvcChampva::FileUploader.new(
          form_id, metadata, file_paths,
          insert_db_row:, current_user:
        )
        expect(uploader_without_data.instance_variable_get(:@parsed_form_data)).to be_nil
      end
    end

    context 'when champva_store_request_json flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_store_request_json, current_user).and_return(false)
      end

      it 'does not store parsed_form_data even when provided' do
        uploader_with_data = IvcChampva::FileUploader.new(
          form_id, metadata, file_paths,
          insert_db_row:, current_user:, parsed_form_data:
        )
        expect(uploader_with_data.instance_variable_get(:@parsed_form_data)).to be_nil
      end
    end
  end

  describe '#handle_uploads' do
    context 'when all PDF uploads succeed' do
      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_metadata_json_file_for_1010d,
                                                  @current_user).and_return(false)
      end

      it 'generates and uploads meta JSON' do
        expect(uploader).to receive(:generate_and_upload_meta_json).and_return([200, nil])
        uploader.handle_uploads
      end
    end

    context 'when all PDF uploads succeed for form 10-10d' do
      let(:form_id) { 'vha_10_10d' }

      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_metadata_json_file_for_1010d,
                                                  @current_user).and_return(false)
      end

      it 'generates and uploads meta JSON' do
        expect(uploader).to receive(:generate_and_upload_meta_json).and_return([200, nil])
        uploader.handle_uploads
      end
    end

    context 'when champva_bypass_metadata_json_file_for_1010d flipper is enabled and form is not 10-10d' do
      let(:form_id) { 'vha_10_7959c' }

      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_metadata_json_file_for_1010d,
                                                  @current_user).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form1010d_enhanced_flow_enabled,
                                                  @current_user).and_return(false)
      end

      it 'generates and uploads meta JSON' do
        expect(uploader).to receive(:generate_and_upload_meta_json).and_return([200, nil])
        uploader.handle_uploads
      end
    end

    context 'when champva_bypass_metadata_json_file_for_1010d flipper is enabled and form is 10-10d' do
      let(:form_id) { 'vha_10_10d' }

      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_metadata_json_file_for_1010d,
                                                  @current_user).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form1010d_enhanced_flow_enabled,
                                                  @current_user).and_return(false)
      end

      it 'skips generating and uploading meta JSON' do
        expect(uploader).not_to receive(:generate_and_upload_meta_json)
        result = uploader.handle_uploads

        expect(result).to eq([200, nil])
      end
    end

    context 'when enhanced flow is enabled and docType is 10-10D-SUPPLEMENTAL' do
      let(:form_id) { 'vha_10_10d' }
      let(:metadata) do
        { 'uuid' => '4171e61a-03b5-49f3-8717-dbf340310473',
          'docType' => '10-10D-SUPPLEMENTAL',
          'attachment_ids' => ['Birth certificate'] }
      end

      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:form1010d_enhanced_flow_enabled,
                                                  @current_user).and_return(true)
      end

      it 'generates and uploads meta JSON for supplemental submissions' do
        expect(uploader).to receive(:generate_and_upload_meta_json).and_return([200, nil])
        uploader.handle_uploads
      end
    end

    context 'when at least one PDF upload fails:' do
      before do
        allow(uploader).to receive(:upload).and_return([400, 'Upload failed'])
      end

      it 'raises an error' do
        # Updated this test to account for new error being raised. This is so submissions are blocked
        # from completing if any files fail to make it to S3. Formerly, the expectation was:
        # `expect(uploader.handle_uploads).to eq([[400, 'Upload failed'], [400, 'Upload failed']])`
        expect { uploader.handle_uploads }.to raise_error(StandardError, /Upload failed/)
      end
    end

    context 'when FMP single file upload flipper is enabled' do
      let(:form_id) { 'vha_10_7959f_2' }
      let(:combined_pdf_path) { File.join('tmp/', "#{metadata['uuid']}_#{form_id}_combined.pdf") }
      let(:file_paths) do
        ['modules/ivc_champva/spec/fixtures/pdfs/vha_10_7959f_2-filled.pdf',
         'modules/ivc_champva/spec/fixtures/images/test_image.pdf',
         'spec/fixtures/files/doctors-note.pdf']
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_fmp_single_file_upload, @current_user).and_return(true)
        allow(FileUtils).to receive(:rm_f)
      end

      it 'combines PDFs and uploads as a single file' do
        expect(IvcChampva::PdfCombiner).to receive(:combine)
          .with(combined_pdf_path, file_paths.compact, anything)
          .and_return(combined_pdf_path)

        expect(uploader).to receive(:upload)
          .with(File.basename(combined_pdf_path), combined_pdf_path, anything)
          .and_return([200])

        expect(uploader).to receive(:generate_and_upload_meta_json).and_return([200, nil])

        result = uploader.handle_uploads
        expect(result).to eq([200, nil])

        expect(FileUtils).to have_received(:rm_f).with(combined_pdf_path)
      end

      it 'handles errors during PDF combination' do
        expect(IvcChampva::PdfCombiner).to receive(:combine)
          .with(combined_pdf_path, file_paths.compact, anything)
          .and_raise(StandardError.new('PDF combination failed'))

        expect(FileUtils).to receive(:rm_f).with(combined_pdf_path)

        expect { uploader.handle_uploads }.to raise_error(StandardError, 'PDF combination failed')
      end

      it 'handles meta data upload failures' do
        expect(IvcChampva::PdfCombiner).to receive(:combine)
          .with(combined_pdf_path, file_paths.compact, anything)
          .and_return(combined_pdf_path)

        expect(uploader).to receive(:upload)
          .with(File.basename(combined_pdf_path), combined_pdf_path, anything)
          .and_return([200])

        expect(uploader).to receive(:generate_and_upload_meta_json)
          .and_return([400, 'Metadata upload failed'])

        result = uploader.handle_uploads
        expect(result).to eq([400, 'Metadata upload failed'])

        expect(FileUtils).to have_received(:rm_f).with(combined_pdf_path)
      end

      it 'inserts all original files plus the combined file into the database when insert_db_row is true' do
        mixed_file_paths = [
          'path/to/main_form.pdf',
          'path/to/supporting_doc_1.pdf',
          'path/to/regular_attachment.pdf',
          'path/to/supporting_doc_2.pdf',
          'path/to/another_file.pdf'
        ]

        test_uploader = IvcChampva::FileUploader.new(
          form_id,
          metadata.merge('attachment_ids' => [1, 2, 3, 4, 5]),
          mixed_file_paths,
          insert_db_row: true, current_user: @current_user
        )

        inserted = []
        allow(test_uploader).to receive(:insert_form) do |file_name, status|
          inserted << { name: file_name, status: }
          nil
        end

        test_uploader.send(:insert_combined_pdf_and_docs, combined_pdf_path, [200])

        expect(inserted.size).to eq(6)

        # combined PDF gets the actual s3 response status
        expect(inserted[0][:name]).to eq(combined_pdf_path)
        expect(inserted[0][:status]).to eq([200])

        # originals get nil s3_status since they were not individually uploaded
        originals = inserted[1..]
        expect(originals.size).to eq(5)
        expect(originals.map { |r| r[:name] }).to match_array(
          %w[main_form.pdf supporting_doc_1.pdf regular_attachment.pdf supporting_doc_2.pdf another_file.pdf]
        )
        expect(originals.map { |r| r[:status] }).to all(be_nil)
      end

      it 'returns metadata upload results when require_all_s3_success is enabled' do
        allow(Flipper).to receive(:enabled?).with(:champva_require_all_s3_success, @current_user).and_return(true)

        expect(IvcChampva::PdfCombiner).to receive(:combine)
          .with(combined_pdf_path, file_paths.compact, anything)
          .and_return(combined_pdf_path)

        expect(uploader).to receive(:upload)
          .with(File.basename(combined_pdf_path), combined_pdf_path, anything)
          .and_return([200])

        expect(uploader).to receive(:generate_and_upload_meta_json)
          .and_return([400, 'Metadata upload failed'])

        result = uploader.handle_uploads
        expect(result).to eq([400, 'Metadata upload failed'])

        expect(FileUtils).to have_received(:rm_f).with(combined_pdf_path)
      end
    end
  end

  describe '#insert_form' do
    it 're-raises the exception when inserting into the DB fails' do
      allow(IvcChampvaForm).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(IvcChampvaForm.new))

      expect do
        uploader.send(:insert_form, 'test_file.pdf', [400, 'Upload failed'])
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#generate_and_upload_meta_json' do
    let(:meta_file_path) { "tmp/#{metadata['uuid']}_#{form_id}_metadata.json" }

    before do
      allow(File).to receive(:write)
      allow(uploader).to receive(:upload).and_return([200, nil])
      allow(FileUtils).to receive(:rm_f)
    end

    it 'writes metadata to a JSON file and uploads it' do
      expect(File).to receive(:write).with(meta_file_path, metadata.to_json)
      expect(uploader).to receive(:upload).with(
        "#{metadata['uuid']}_#{form_id}_metadata.json",
        meta_file_path
      ).and_return([200, nil])
      uploader.send(:generate_and_upload_meta_json)
    end

    context 'when meta upload succeeds' do
      it 'deletes the meta file and returns success' do
        expect(FileUtils).to receive(:rm_f).with(meta_file_path)
        expect(uploader.send(:generate_and_upload_meta_json)).to eq([200, nil])
      end
    end

    context 'when meta upload fails' do
      before do
        allow(uploader).to receive(:upload).and_return([400, 'Upload failed'])
      end

      it 'returns the upload error' do
        expect(uploader.send(:generate_and_upload_meta_json)).to eq([400, 'Upload failed'])
      end
    end
  end

  describe '#upload' do
    let(:s3_client) { double('S3Client') }

    before do
      allow(uploader).to receive(:client).and_return(s3_client)
    end

    it 'uploads the file to S3 and returns the upload status' do
      expect(s3_client).to receive(:put_object).and_return({ success: true })
      expect(uploader.send(:upload, 'file_name', 'file_path', 'attachment_id')).to eq([200])
    end

    context 'when upload fails' do
      it 'returns the error message' do
        expect(s3_client).to receive(:put_object).and_return({ success: false, error_message: 'Upload failed' })
        expect(uploader.send(:upload,
                             'file_name',
                             'file_path',
                             'attachment_id')).to eq([400, 'Upload failed'])
      end
    end

    context 'when unexpected response from S3' do
      it 'returns an unexpected response error' do
        expect(s3_client).to receive(:put_object).and_return(nil)
        expect(uploader.send(:upload,
                             'file_name',
                             'file_path',
                             attachment_ids: 'attachment_ids')).to eq([500, 'Unexpected response from S3 upload'])
      end
    end
  end

  describe '#handle_iterative_uploads' do
    let(:insert_db_row) { true }

    context 'when champva_bypass_persisting_ves_json_to_database is enabled' do
      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_persisting_ves_json_to_database,
                                                  @current_user).and_return(true)
      end

      it 'uploads the _ves.json file but does not insert it into the database' do
        expect(uploader).to receive(:upload).exactly(3).times
        expect(uploader).to receive(:insert_form).with('file1.pdf', [200])
        expect(uploader).to receive(:insert_form).with('file2.png', [200])
        expect(uploader).not_to receive(:insert_form).with(
          '4171e61a-03b5-49f3-8717-dbf340310473_vha_10_10d_ves.json',
          [200]
        )

        uploader.send(:handle_iterative_uploads)
      end
    end

    context 'when champva_bypass_persisting_ves_json_to_database is disabled' do
      before do
        allow(uploader).to receive(:upload).and_return([200])
        allow(Flipper).to receive(:enabled?).with(:champva_bypass_persisting_ves_json_to_database,
                                                  @current_user).and_return(false)
      end

      it 'uploads the _ves.json file and inserts it into the database' do
        expect(uploader).to receive(:upload).exactly(3).times
        expect(uploader).to receive(:insert_form).with('file1.pdf', [200])
        expect(uploader).to receive(:insert_form).with('file2.png', [200])
        expect(uploader).to receive(:insert_form).with(
          '4171e61a-03b5-49f3-8717-dbf340310473_vha_10_10d_ves.json',
          [200]
        )

        uploader.send(:handle_iterative_uploads)
      end
    end
  end

  describe '#insert_combined_docs' do
    let(:insert_db_row) { true }
    let(:combined_file_path) { 'tmp/uuid_vha_10_7959a_duty_to_assist_0_0_combined.pdf' }
    let(:original_files) do
      [
        { file_path: 'tmp/uuid_vha_10_7959a.pdf', attachment_id: 'Duty to Assist', index: 0 },
        { file_path: 'tmp/uuid_vha_10_7959a_supporting_doc-0.pdf', attachment_id: 'Duty to Assist', index: 1 },
        { file_path: 'tmp/uuid_vha_10_7959a_supporting_doc-1.pdf', attachment_id: 'Duty to Assist', index: 2 }
      ]
    end

    let(:combined_uploader) do
      uploader_instance = IvcChampva::FileUploader.new(form_id, metadata, file_paths, insert_db_row:)
      uploader_instance.instance_variable_set(:@merge_map, { combined_file_path => original_files })
      uploader_instance
    end

    it 'inserts a record for each original file with nil s3_status' do
      inserted = []
      allow(combined_uploader).to receive(:insert_form) { |name, status| inserted << { name:, status: } }

      combined_uploader.send(:insert_combined_docs, combined_file_path)

      expect(inserted.length).to eq(3)
      expect(inserted.map { |r| r[:name] }).to eq([
                                                    'uuid_vha_10_7959a.pdf',
                                                    'uuid_vha_10_7959a_supporting_doc-0.pdf',
                                                    'uuid_vha_10_7959a_supporting_doc-1.pdf'
                                                  ])
      expect(inserted.map { |r| r[:status] }).to all(be_nil)
    end

    it 'is a no-op when file_path is not in merge_map' do
      expect(combined_uploader).not_to receive(:insert_form)

      combined_uploader.send(:insert_combined_docs, 'tmp/not_a_combined_file.pdf')
    end
  end

  describe '#apply_document_combining' do
    before do
      allow(Flipper).to receive(:enabled?).and_return(false)
    end

    it 'is a no-op when feature flags are disabled' do
      original_paths = uploader.instance_variable_get(:@file_paths).dup
      original_ids = uploader.instance_variable_get(:@metadata)['attachment_ids'].dup

      uploader.send(:apply_document_combining)

      expect(uploader.instance_variable_get(:@file_paths)).to eq(original_paths)
      expect(uploader.instance_variable_get(:@metadata)['attachment_ids']).to eq(original_ids)
      expect(uploader.instance_variable_get(:@merge_map)).to eq({})
    end
  end

  describe 'DTA document combining integration' do
    let(:uuid) { '4171e61a-03b5-49f3-8717-dbf340310473' }
    let(:dta_form_id) { 'vha_10_7959a' }
    let(:fixture_base) { Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures') }
    let(:pdf_fixture_front) { fixture_base.join('images', 'test-medicare-part-a-and-b-card-front.pdf').to_s }
    let(:pdf_fixture_back) { fixture_base.join('images', 'test-medicare-part-a-and-b-card-back.pdf').to_s }
    let(:pdf_fixture_eob) { fixture_base.join('files', 'SampleEOB.pdf').to_s }

    let(:dta_file_paths) { [pdf_fixture_front, pdf_fixture_back, pdf_fixture_eob] }
    let(:dta_attachment_ids) { ['Duty to Assist', 'Duty to Assist', 'Duty to Assist'] }
    let(:dta_metadata) do
      {
        'uuid' => uuid,
        'docType' => '10-7959A',
        'attachment_ids' => dta_attachment_ids,
        'primaryContactInfo' => {
          'name' => { 'first' => 'Test', 'last' => 'User' },
          'email' => 'test@example.com'
        }
      }
    end

    let(:dta_uploader) do
      IvcChampva::FileUploader.new(dta_form_id, dta_metadata, dta_file_paths, insert_db_row: true)
    end

    before do
      allow(Flipper).to receive(:enabled?).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:champva_document_merging, anything).and_return(true)
      allow(Flipper).to receive(:enabled?).with('champva_docmerge_10_7959a_duty_to_assist', anything).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_bypass_persisting_ves_json_to_database,
                                                anything).and_return(true)
      allow(dta_uploader).to receive_messages(upload: [200], generate_and_upload_meta_json: [200, nil])
    end

    after do
      Dir.glob("tmp/*#{IvcChampva::FileNaming::COMBINED_PDF_SUFFIX}").each { |file| FileUtils.rm_f(file) }
    end

    it 'combines DTA files and creates correct DB records' do
      dta_uploader.handle_uploads

      records = IvcChampvaForm.where(form_uuid: uuid)

      combined_records = records.select { |r| r.file_name.include?(IvcChampva::FileNaming::COMBINED_PDF_SUFFIX) }
      expect(combined_records.length).to eq(1)
      expect(combined_records.first.s3_status).to eq('[200]')

      original_records = records.reject { |r| r.file_name.include?(IvcChampva::FileNaming::COMBINED_PDF_SUFFIX) }
      expect(original_records.length).to eq(3)
      expect(original_records.map(&:s3_status)).to all(be_nil)
    end

    it 'uploads only the combined PDF to S3 (not individual files)' do
      dta_uploader.handle_uploads

      # Only the combined PDF should be uploaded, not the 3 individual DTA files
      expect(dta_uploader).to have_received(:upload).once
    end
  end
end
