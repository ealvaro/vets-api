# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormRecorder do
  let(:metadata) do
    {
      'uuid' => '4171e61a-03b5-49f3-8717-dbf340310473',
      'docType' => '10-10D',
      'primaryContactInfo' => {
        'email' => 'test@example.com',
        'name' => { 'first' => 'John', 'last' => 'Doe' }
      }
    }
  end
  let(:form_id) { 'vha_10_10d' }
  let(:current_user) { double('User', icn: 'ICN123') }
  let(:parsed_form_data) { { 'form_number' => '10-10D' } }
  let(:recorder) do
    described_class.new(metadata, form_id, current_user:, parsed_form_data:)
  end

  describe '#insert_form' do
    it 'creates an IvcChampvaForm record with correct attributes' do
      expect(IvcChampvaForm).to receive(:create!).with(
        hash_including(
          form_uuid: '4171e61a-03b5-49f3-8717-dbf340310473',
          email: 'test@example.com',
          first_name: 'John',
          last_name: 'Doe',
          submitted_by_icn: 'ICN123',
          form_number: '10-10D',
          file_name: 'test_file.pdf',
          s3_status: '[200]',
          pega_status: 'Submitted',
          request_json: parsed_form_data.to_json
        )
      ).and_return(double('IvcChampvaForm'))

      allow_any_instance_of(IvcChampva::Monitor).to receive(:track_insert_form)

      recorder.insert_form('test_file.pdf', [200])
    end

    it "sets s3_status to '[200, nil]' and pega_status to 'Submitted' for a [200, nil] response" do
      expect(IvcChampvaForm).to receive(:create!).with(
        hash_including(
          form_uuid: '4171e61a-03b5-49f3-8717-dbf340310473',
          form_number: '10-10D',
          first_name: 'John',
          last_name: 'Doe',
          s3_status: '[200, nil]',
          pega_status: 'Submitted'
        )
      ).and_return(double('IvcChampvaForm'))

      allow_any_instance_of(IvcChampva::Monitor).to receive(:track_insert_form)

      recorder.insert_form('some_file.pdf', [200, nil])
    end

    it 'sets pega_status to nil when S3 upload fails' do
      expect(IvcChampvaForm).to receive(:create!).with(
        hash_including(
          pega_status: nil,
          s3_status: '[400, "Upload failed"]'
        )
      ).and_return(double('IvcChampvaForm'))

      allow_any_instance_of(IvcChampva::Monitor).to receive(:track_insert_form)

      recorder.insert_form('test_file.pdf', [400, 'Upload failed'])
    end

    it 're-raises the exception when inserting into the DB fails' do
      allow(IvcChampvaForm).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(IvcChampvaForm.new))

      expect do
        recorder.insert_form('test_file.pdf', [400, 'Upload failed'])
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'handles nil metadata gracefully' do
      nil_recorder = described_class.new(nil, form_id, current_user:)

      expect(IvcChampvaForm).to receive(:create!).with(
        hash_including(
          form_uuid: nil,
          email: nil,
          first_name: nil,
          last_name: nil
        )
      ).and_return(double('IvcChampvaForm'))

      allow_any_instance_of(IvcChampva::Monitor).to receive(:track_insert_form)

      nil_recorder.insert_form('test_file.pdf', [200])
    end

    it 'handles nil current_user' do
      no_user_recorder = described_class.new(metadata, form_id, current_user: nil)

      expect(IvcChampvaForm).to receive(:create!).with(
        hash_including(submitted_by_icn: nil)
      ).and_return(double('IvcChampvaForm'))

      allow_any_instance_of(IvcChampva::Monitor).to receive(:track_insert_form)

      no_user_recorder.insert_form('test_file.pdf', [200])
    end
  end

  describe '#insert_combined_docs' do
    let(:merge_map) do
      {
        'tmp/combined.pdf' => [
          { file_path: 'tmp/original1-tmp.pdf' },
          { file_path: 'tmp/original2.pdf' }
        ]
      }
    end

    it 'inserts a record for each original file in the merge map' do
      expect(recorder).to receive(:insert_form).with('original1.pdf', nil)
      expect(recorder).to receive(:insert_form).with('original2.pdf', nil)

      recorder.insert_combined_docs('tmp/combined.pdf', merge_map, insert_db_row: true)
    end

    it 'is a no-op when insert_db_row is false' do
      expect(recorder).not_to receive(:insert_form)

      recorder.insert_combined_docs('tmp/combined.pdf', merge_map, insert_db_row: false)
    end

    it 'is a no-op when file_path is not in the merge map' do
      expect(recorder).not_to receive(:insert_form)

      recorder.insert_combined_docs('tmp/not_in_map.pdf', merge_map, insert_db_row: true)
    end
  end

  describe '#insert_combined_pdf_and_docs' do
    let(:file_paths) { ['path/to/main_form.pdf', 'path/to/supporting_doc.pdf', 'path/to/another.pdf'] }

    it 'inserts the combined PDF and a shadow record for each original file' do
      inserted = []
      allow(recorder).to receive(:insert_form) do |file_name, status|
        inserted << { name: file_name, status: }
      end

      recorder.insert_combined_pdf_and_docs('combined.pdf', [200], file_paths)

      # 1 combined PDF + 3 originals = 4 total
      expect(inserted.size).to eq(4)

      expect(inserted[0]).to eq({ name: 'combined.pdf', status: [200] })
      expect(inserted[1]).to eq({ name: 'main_form.pdf', status: nil })
      expect(inserted[2]).to eq({ name: 'supporting_doc.pdf', status: nil })
      expect(inserted[3]).to eq({ name: 'another.pdf', status: nil })
    end

    it 'skips blank file paths' do
      allow(recorder).to receive(:insert_form)

      recorder.insert_combined_pdf_and_docs('combined.pdf', [200], ['path/to/file.pdf', nil, ''])

      # 1 combined + 1 non-blank original = 2
      expect(recorder).to have_received(:insert_form).exactly(2).times
    end

    it 'strips -tmp from original file names' do
      allow(recorder).to receive(:insert_form)

      recorder.insert_combined_pdf_and_docs('combined.pdf', [200], ['path/to/form-tmp.pdf'])

      expect(recorder).to have_received(:insert_form).with('form.pdf', nil)
    end
  end

  describe '#validate_email (private)' do
    it 'returns valid emails' do
      expect(recorder.send(:validate_email, 'user@example.com')).to eq('user@example.com')
    end

    it 'returns nil for invalid emails' do
      expect(recorder.send(:validate_email, 'not-an-email')).to be_nil
    end

    it 'returns nil for empty string' do
      expect(recorder.send(:validate_email, '')).to be_nil
    end

    it 'returns nil for nil' do
      expect(recorder.send(:validate_email, nil)).to be_nil
    end

    it 'accepts emails with subdomains' do
      expect(recorder.send(:validate_email, 'user@mail.example.com')).to eq('user@mail.example.com')
    end

    it 'accepts emails with dots and hyphens in local part' do
      expect(recorder.send(:validate_email, 'first.last-name@example.com')).to eq('first.last-name@example.com')
    end
  end
end
