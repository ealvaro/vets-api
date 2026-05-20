# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::FileData do
  describe '#set_file_data!' do
    let(:document) { build(:supporting_document) }
    let(:uploader_double) { instance_double(ClaimsApi::SupportingDocumentUploader) }
    let(:file) do
      Rack::Test::UploadedFile.new(
        Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'extras.pdf').to_s
      )
    end

    context 'when a virus is detected' do
      before do
        allow(Flipper).to receive(:enabled?).with(:claims_load_testing).and_return(false)
        allow(document).to receive(:uploader).and_return(uploader_double)
        allow(uploader_double).to receive(:store!).and_raise(UploaderVirusScan::VirusFoundError)
      end

      it 'raises UnprocessableEntity with a safe message' do
        expect { document.set_file_data!(file, 'L023') }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |e|
          expect(e.errors.first.detail).to eq('We were unable to process your file. Please try again.')
        end
      end
    end
  end
end
