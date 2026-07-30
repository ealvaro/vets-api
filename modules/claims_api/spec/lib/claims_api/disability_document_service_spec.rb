# frozen_string_literal: true

require 'rails_helper'
require_relative '../../rails_helper'

describe ClaimsApi::DisabilityCompensation::DisabilityDocumentService do
  subject { described_class.new }

  let(:claim) { create(:auto_established_claim, evss_id: 600_400_688, id: '581128c6-ad08-4b1e-8b82-c3640e829fb3') }
  let(:body) { 'test body' }

  before do
    allow_any_instance_of(ClaimsApi::V2::BenefitsDocuments::Service)
      .to receive(:get_auth_token).and_return('some-value-here')
  end

  describe 'disability comp (doc_type: L122)' do
    let(:veteran_name) { 'John_Smith' }
    let(:claim_id) { '600_400_688' }
    let(:form_name) { '526EZ' }
    let(:original_filename) { '' }
    let(:doc_type) { 'L122' }

    it 'generates the correct filename for L122' do
      result = subject.send(:generate_file_name, veteran_name:, claim_id:, form_name:, original_filename:)
      expect(result).to be_a String
      expect(result).to eq 'John_Smith_600_400_688_526EZ.pdf'
    end
  end

  describe 'other attachments (doc_type: L023)' do
    let(:veteran_name) { 'John_Smith' }
    let(:claim_id) { '600_400_688' }
    let(:form_name) { 'supporting' }
    let(:original_filename) { 'original_filename_IRT56SX99qs.pdf' }
    let(:doc_type) { 'L023' }

    it 'generates the correct filename for L023' do
      result = subject.send(:generate_file_name, veteran_name:, claim_id:, form_name:, original_filename:)
      expect(result).to be_a String
      expect(result).to eq 'John_Smith_600_400_688_original_filename.pdf'
    end
  end

  describe '#generate_body' do
    let(:pdf_path) { Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s }

    context 'when participantId is present in auth_headers' do
      let(:claim) do
        create(:auto_established_claim, evss_id: 600_400_688,
                                        auth_headers: {
                                          'va_eauth_firstName' => 'John',
                                          'va_eauth_lastName' => 'Smith',
                                          'va_eauth_pid' => '600043284',
                                          'va_eauth_birlsfilenumber' => '796378782'
                                        })
      end

      it 'uses participantId and does not include fileNumber' do
        result = subject.send(:generate_body, claim:, doc_type: 'L122', pdf_path:)
        params_json = result[:parameters].read
        data = JSON.parse(params_json)['data']

        expect(data['participantId']).to eq('600043284')
        expect(data).not_to have_key('fileNumber')
      end
    end

    context 'systemName by version' do
      it 'defaults to the v2 systemName when no version is given' do
        result = subject.send(:generate_body, claim:, doc_type: 'L122', pdf_path:)
        params_json = result[:parameters].read
        data = JSON.parse(params_json)['data']

        expect(data['systemName']).to eq('VA.gov')
      end

      it "uses the v2 systemName when version: 'v2' is given" do
        result = subject.send(:generate_body, claim:, doc_type: 'L122', pdf_path:, version: 'v2')
        params_json = result[:parameters].read
        data = JSON.parse(params_json)['data']

        expect(data['systemName']).to eq('VA.gov')
      end

      it "uses the v1 systemName when version: 'v1' is given" do
        result = subject.send(:generate_body, claim:, doc_type: 'L122', pdf_path:, version: 'v1')
        params_json = result[:parameters].read
        data = JSON.parse(params_json)['data']

        expect(data['systemName']).to eq('Lighthouse')
      end
    end
  end

  describe '#document_upload_system_name' do
    it 'returns the mapped systemName for a known version' do
      expect(subject.send(:document_upload_system_name, 'v1')).to eq('Lighthouse')
      expect(subject.send(:document_upload_system_name, 'v2')).to eq('VA.gov')
    end

    it 'normalizes case and surrounding whitespace' do
      expect(subject.send(:document_upload_system_name, ' V1 ')).to eq('Lighthouse')
    end

    it 'raises ArgumentError for an unknown version' do
      expect do
        subject.send(:document_upload_system_name, 'v3')
      end.to raise_error(ArgumentError, /Unknown document upload version/)
    end

    it 'raises ArgumentError for a nil version' do
      expect do
        subject.send(:document_upload_system_name, nil)
      end.to raise_error(ArgumentError, /Unknown document upload version/)
    end
  end
end
