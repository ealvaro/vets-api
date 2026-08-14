# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::HeicConverter do
  subject(:converter) { described_class.new(user) }

  let(:user) { build(:user) }

  let(:test_image_base64) do
    fixture_path = Rails.root.join('modules', 'travel_pay', 'spec', 'fixtures', 'pixel-working.heic')
    Base64.strict_encode64(File.binread(fixture_path))
  end

  before do
    allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_heic_conversion, user).and_return(true)
  end

  describe '#convert_if_heic' do
    context 'when params contain a HEIC receipt' do
      let(:params) do
        {
          'claimId' => '123',
          'expenseType' => 'parking',
          'expenseReceipt' => {
            'fileName' => 'receipt.heic',
            'contentType' => 'image/heic',
            'fileData' => test_image_base64,
            'length' => '500'
          }
        }
      end

      it 'converts the receipt to JPG and preserves other params' do
        result = converter.convert_if_heic(params)
        receipt = result['expenseReceipt']

        expect(receipt['contentType']).to eq('image/jpeg')
        expect(receipt['fileName']).to eq('receipt.jpg')
        expect(receipt['length'].to_i).to be_positive
        expect(receipt['fileData']).to be_present
        expect { Base64.strict_decode64(receipt['fileData']) }.not_to raise_error
        expect(result['claimId']).to eq('123')
        expect(result['expenseType']).to eq('parking')
      end

      it 'does not mutate the original params' do
        original_content_type = params['expenseReceipt']['contentType']
        converter.convert_if_heic(params)

        expect(params['expenseReceipt']['contentType']).to eq(original_content_type)
      end
    end

    context 'when params contain a HEIF receipt' do
      let(:params) do
        {
          'expenseReceipt' => {
            'fileName' => 'photo.heif',
            'contentType' => 'image/heif',
            'fileData' => test_image_base64,
            'length' => '500'
          }
        }
      end

      it 'converts HEIF to JPG' do
        result = converter.convert_if_heic(params)

        expect(result['expenseReceipt']['contentType']).to eq('image/jpeg')
        expect(result['expenseReceipt']['fileName']).to eq('photo.jpg')
      end
    end

    context 'when content type casing varies' do
      let(:params) do
        {
          'expenseReceipt' => {
            'fileName' => 'receipt.HEIC',
            'contentType' => 'IMAGE/HEIC',
            'fileData' => test_image_base64,
            'length' => '500'
          }
        }
      end

      it 'detects HEIC regardless of case' do
        result = converter.convert_if_heic(params)

        expect(result['expenseReceipt']['contentType']).to eq('image/jpeg')
      end
    end

    context 'when receipt is not HEIC/HEIF' do
      it 'returns params unchanged for JPEG' do
        params = { 'expenseReceipt' => { 'fileName' => 'receipt.jpg', 'contentType' => 'image/jpeg',
                                         'fileData' => test_image_base64, 'length' => '500' } }
        expect(converter.convert_if_heic(params)).to eq(params)
      end

      it 'returns params unchanged for PDF' do
        params = { 'expenseReceipt' => { 'fileName' => 'receipt.pdf', 'contentType' => 'application/pdf',
                                         'fileData' => 'some-data', 'length' => '1000' } }
        expect(converter.convert_if_heic(params)).to eq(params)
      end
    end

    context 'when no receipt is present' do
      let(:params) { { 'claimId' => '123', 'expenseType' => 'parking' } }

      it 'returns params unchanged' do
        result = converter.convert_if_heic(params)

        expect(result).to eq(params)
      end
    end

    context 'when conversion fails' do
      context 'due to invalid Base64' do
        let(:params) do
          {
            'expenseReceipt' => {
              'fileName' => 'receipt.heic',
              'contentType' => 'image/heic',
              'fileData' => 'invalid-base64-data!!!',
              'length' => '500'
            }
          }
        end

        it 'raises UnprocessableEntity and logs the error on decode failure' do
          expect(Rails.logger).to receive(:error)
            .with(a_string_matching(/HEIC conversion failed: ArgumentError - invalid base64/),
                  hash_including(service: 'travel-pay'))

          expect { converter.convert_if_heic(params) }
            .to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end

      context 'due to forced conversion failure' do
        let(:valid_base64_data) { Base64.strict_encode64('fake image data') }

        let(:params) do
          {
            'expenseReceipt' => {
              'fileName' => 'receipt.heic',
              'contentType' => 'image/heic',
              'fileData' => valid_base64_data,
              'length' => '500'
            }
          }
        end

        before do
          # Force convert_image_to_jpg to fail
          allow(MiniMagick::Image).to receive(:open).and_raise(StandardError.new('boom!'))
        end

        it 'raises UnprocessableEntity and logs the error with class and message' do
          expect(Rails.logger).to receive(:error)
            .with('HEIC conversion failed: StandardError - boom!',
                  hash_including(service: 'travel-pay'))

          expect { converter.convert_if_heic(params) }
            .to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end
    end

    context 'when feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_heic_conversion, user).and_return(false)
      end

      let(:heic_params) do
        {
          'expenseReceipt' => {
            'fileName' => 'receipt.heic',
            'contentType' => 'image/heic',
            'fileData' => test_image_base64,
            'length' => '500'
          }
        }
      end

      let(:jpeg_params) do
        {
          'expenseReceipt' => {
            'fileName' => 'receipt.jpg',
            'contentType' => 'image/jpeg',
            'fileData' => test_image_base64,
            'length' => '500'
          }
        }
      end

      it 'raises UnprocessableEntity for HEIC receipts' do
        expect { converter.convert_if_heic(heic_params) }
          .to raise_error(Common::Exceptions::UnprocessableEntity)
      end

      it 'returns params unchanged for non-HEIC receipts' do
        expect(converter.convert_if_heic(jpeg_params)).to eq(jpeg_params)
      end
    end
  end

  describe '#convert_file_to_jpg' do
    let(:heic_binary) do
      fixture_path = Rails.root.join('modules', 'travel_pay', 'spec', 'fixtures', 'pixel-working.heic')
      File.binread(fixture_path)
    end

    context 'when given a HEIC uploaded file' do
      let(:uploaded_file) do
        tempfile = Tempfile.new(['test', '.heic'])
        tempfile.binmode
        tempfile.write(heic_binary)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename: 'photo.heic',
          type: 'image/heic'
        )
      end

      it 'returns an UploadedFile with JPG content type' do
        converter.convert_file_to_jpg(uploaded_file) do |result|
          expect(result).to be_a(ActionDispatch::Http::UploadedFile)
          expect(result.content_type).to eq('image/jpeg')
        end
      end

      it 'renames the filename from .heic to .jpg' do
        converter.convert_file_to_jpg(uploaded_file) do |result|
          expect(result.original_filename).to eq('photo.jpg')
        end
      end

      it 'produces a non-empty tempfile' do
        converter.convert_file_to_jpg(uploaded_file) do |result|
          expect(result.tempfile.size).to be_positive
        end
      end

      it 'logs the conversion' do
        expect(Rails.logger).to receive(:info).with(
          'Converting HEIC document upload to JPG',
          hash_including(service: 'travel-pay')
        )

        converter.convert_file_to_jpg(uploaded_file) { |_| nil }
      end
    end

    context 'when given a HEIF uploaded file' do
      let(:uploaded_file) do
        tempfile = Tempfile.new(['test', '.heif'])
        tempfile.binmode
        tempfile.write(heic_binary)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename: 'photo.HEIF',
          type: 'image/heif'
        )
      end

      it 'renames the filename from .HEIF to .jpg' do
        converter.convert_file_to_jpg(uploaded_file) do |result|
          expect(result.original_filename).to eq('photo.jpg')
        end
      end
    end

    context 'when conversion fails' do
      let(:uploaded_file) do
        tempfile = Tempfile.new(['test', '.heic'])
        tempfile.binmode
        tempfile.write('not a real image')
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename: 'bad.heic',
          type: 'image/heic'
        )
      end

      before do
        allow(MiniMagick::Image).to receive(:open).and_raise(StandardError.new('conversion error'))
      end

      it 'raises UnprocessableEntity and logs the error' do
        expect(Rails.logger).to receive(:error)
          .with('HEIC conversion failed: StandardError - conversion error',
                hash_including(service: 'travel-pay'))

        expect { converter.convert_file_to_jpg(uploaded_file) { |_| nil } }
          .to raise_error(Common::Exceptions::UnprocessableEntity)
      end
    end
  end
end
