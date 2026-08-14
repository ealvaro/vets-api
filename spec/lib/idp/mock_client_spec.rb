# frozen_string_literal: true

require 'rails_helper'
require 'idp'
require 'idp/mock_client'

RSpec.describe Idp::MockClient do
  subject(:client) { described_class.new }

  let(:invalid_document_ids) { ['../../etc/passwd', '/etc/passwd'] }

  describe '#intake' do
    it 'returns id, bucket, and pdf_key' do
      result = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))

      expect(result).to include('id', 'bucket', 'pdf_key')
      expect(result['bucket']).to eq('local-idp')
    end
  end

  describe '#status' do
    it 'returns status for an ingested document' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))
      result = client.status(contract['id'])

      expect(result['scan_status']).to eq('completed')
      expect(result['file_name']).to eq('test.pdf')
    end

    it 'raises an error for an unknown document' do
      expect { client.status('00000000-0000-0000-0000-000000000000') }.to raise_error(Idp::Error, /not found/)
    end

    it 'rejects invalid document ids before reading from disk' do
      invalid_document_ids.each do |invalid_id|
        expect { client.status(invalid_id) }.to raise_error(Idp::Error, /Invalid document id/)
      end
    end
  end

  describe '#output' do
    it 'returns artifact forms for an ingested document' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))
      result = client.output(contract['id'], type: 'artifact')

      expect(result['forms']).to be_an(Array)
      expect(result['forms'].map { |f| f['artifactType'] }).to include('DD214', 'DEATH')
    end

    it 'rejects invalid document ids before reading from disk' do
      invalid_document_ids.each do |invalid_id|
        expect { client.output(invalid_id, type: 'artifact') }.to raise_error(Idp::Error, /Invalid document id/)
      end
    end
  end

  describe '#download' do
    it 'returns artifact data by kvpid' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))
      forms = client.output(contract['id'], type: 'artifact')['forms']
      kvpid = forms.first['mmsArtifactValidationId']

      result = client.download(contract['id'], kvpid:)

      expect(result).to include('FIRST_NAME', 'LAST_NAME')
    end

    it 'raises an error for an unknown kvpid' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))

      expect { client.download(contract['id'], kvpid: 'bad-kvp') }
        .to raise_error(Idp::Error, /not found/)
    end

    it 'rejects invalid document ids before reading from disk' do
      invalid_document_ids.each do |invalid_id|
        expect { client.download(invalid_id, kvpid: 'bad-kvp') }.to raise_error(Idp::Error, /Invalid document id/)
      end
    end
  end

  describe '#update' do
    let(:updated_payload) do
      {
        'FIRST_NAME' => 'Ada',
        'LAST_NAME' => 'Lovelace',
        'BIRTH_DATE' => '1815-12-10'
      }
    end

    it 'updates and persists artifact data for a kvpid' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))
      forms = client.output(contract['id'], type: 'artifact')['forms']
      kvpid = forms.first['mmsArtifactValidationId']

      result = client.update(contract['id'], kvpid:, payload: updated_payload)

      expect(result).to eq(updated_payload)
      expect(client.download(contract['id'], kvpid:)).to eq(updated_payload)
    end

    it 'raises an error for an unknown kvpid' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))

      expect { client.update(contract['id'], kvpid: 'bad-kvp', payload: updated_payload) }
        .to raise_error(Idp::Error, /not found/)
    end

    it 'raises an error for a non-object payload' do
      contract = client.intake(file_name: 'test.pdf', pdf_base64: Base64.encode64('fake pdf content'))
      forms = client.output(contract['id'], type: 'artifact')['forms']
      kvpid = forms.first['mmsArtifactValidationId']

      expect { client.update(contract['id'], kvpid:, payload: ['invalid']) }
        .to raise_error(Idp::Error, /JSON object/)
    end

    it 'rejects invalid document ids before reading from disk' do
      invalid_document_ids.each do |invalid_id|
        expect { client.update(invalid_id, kvpid: 'bad-kvp', payload: updated_payload) }
          .to raise_error(Idp::Error, /Invalid document id/)
      end
    end
  end
end
