# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::PowerOfAttorney, type: :model do
  let(:pending_record) { create(:power_of_attorney) }

  describe 'encrypted attributes' do
    it 'does the thing' do
      expect(subject).to encrypt_attr(:form_data)
      expect(subject).to encrypt_attr(:auth_headers)
    end
  end

  describe 'encrypted attribute' do
    it 'does the thing' do
      expect(subject).to encrypt_attr(:file_data)
    end
  end

  describe '#set_file_data!' do
    it 'stores the file_data and give me a full evss document' do
      attachment = build(:power_of_attorney)

      file = Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      )

      attachment.set_file_data!(file, 'docType')
      attachment.save!
      attachment.reload

      expect(attachment.file_data).to have_key('filename')
      expect(attachment.file_data).to have_key('doc_type')

      expect(attachment.file_name).to eq(attachment.file_data['filename'])
      expect(attachment.document_type).to eq(attachment.file_data['doc_type'])
    end
  end

  describe '#find_using_identifier_and_source' do
    let(:auth_headers) do
      { 'X-VA-SSN': '796-04-3735',
        'X-VA-First-Name': 'WESLEY',
        'X-VA-Last-Name': 'FORD',
        'X-Consumer-Username': 'TestConsumer',
        'X-VA-Birth-Date': '1986-05-06T00:00:00+00:00',
        'X-VA-Gender': 'M' }
    end

    let(:attributes) do
      {
        status: ClaimsApi::PowerOfAttorney::PENDING,
        auth_headers:,
        form_data: {},
        current_poa: '072',
        cid: 'cid'
      }
    end

    let(:source_data) do
      {
        'name' => 'source_name',
        'email' => 'source_email'
      }
    end

    it 'can find a sha256 hash' do
      attributes.merge!({ source_data: })
      power_of_attorney = ClaimsApi::PowerOfAttorney.create(attributes)
      primary_identifier = { header_hash: power_of_attorney.header_hash }
      res = ClaimsApi::PowerOfAttorney.find_using_identifier_and_source(primary_identifier, 'source_name')
      expect(res.source_data).to eq(source_data)
    end

    it 'can find an md5 record when missing sha256' do
      attributes.merge!({ source_data: })
      power_of_attorney = ClaimsApi::PowerOfAttorney.create(attributes)
      header_hash = power_of_attorney.header_hash

      power_of_attorney.update_columns header_hash: nil # rubocop:disable Rails/SkipsModelValidations

      header_hash_id = { header_hash: }
      res = ClaimsApi::PowerOfAttorney.find_using_identifier_and_source(header_hash_id, 'source_name')
      expect(res).to be_blank

      md5_id = { md5: power_of_attorney.md5 }
      res = ClaimsApi::PowerOfAttorney.find_using_identifier_and_source(md5_id, 'source_name')
      expect(res.source_data).to eq(source_data)
    end
  end

  describe 'pending?' do
    context 'no pending records' do
      it 'is false' do
        expect(described_class.pending?('123')).to be(false)
      end
    end

    context 'with pending records' do
      it 'truthies and return the record' do
        result = described_class.pending?(pending_record.id)
        expect(result).to be_truthy
        expect(result.id).to eq(pending_record.id)
      end
    end
  end

  describe "persisting 'cid' (OKTA client_id)" do
    it "stores 'cid' in the DB upon creation" do
      pending_record.cid = 'ABC123'
      pending_record.save!

      claim = ClaimsApi::PowerOfAttorney.last

      expect(claim.cid).to eq('ABC123')
    end
  end

  describe '#belongs_to_veteran?' do
    let(:veteran_pid) { '600049703' }
    let(:dependent_pid) { '600264235' }
    let(:poa_with_veteran_only) do
      create(:power_of_attorney, auth_headers: { 'va_eauth_pid' => veteran_pid })
    end
    let(:poa_with_dependent) do
      create(:power_of_attorney, auth_headers: {
               'va_eauth_pid' => veteran_pid,
               'dependent' => { 'participant_id' => dependent_pid }
             })
    end
    let(:poa_with_legacy_key) do
      create(:power_of_attorney, auth_headers: { 'participant_id' => veteran_pid })
    end

    context 'when the POA has no dependent' do
      it 'returns true when participant_id matches va_eauth_pid' do
        expect(poa_with_veteran_only.belongs_to_veteran?(veteran_pid)).to be true
      end

      it 'returns false when participant_id does not match' do
        expect(poa_with_veteran_only.belongs_to_veteran?('9999999')).to be false
      end
    end

    context 'when the POA uses the legacy participant_id key' do
      it 'returns true when participant_id matches' do
        expect(poa_with_legacy_key.belongs_to_veteran?(veteran_pid)).to be true
      end

      it 'returns false when participant_id does not match' do
        expect(poa_with_legacy_key.belongs_to_veteran?('9999999')).to be false
      end
    end

    context 'when participant_id types differ (string vs integer)' do
      it 'matches after coercion to string' do
        poa = create(:power_of_attorney, auth_headers: { 'va_eauth_pid' => 600_049_703 })
        expect(poa.belongs_to_veteran?('600049703')).to be true
      end
    end

    context 'when the POA has a dependent claimant' do
      it 'returns true when participant_id matches the veteran' do
        expect(poa_with_dependent.belongs_to_veteran?(veteran_pid)).to be true
      end

      it 'returns true when participant_id matches the dependent' do
        expect(poa_with_dependent.belongs_to_veteran?(dependent_pid)).to be true
      end

      it 'returns false when participant_id matches neither' do
        expect(poa_with_dependent.belongs_to_veteran?('9999999')).to be false
      end
    end

    context 'when auth_headers is empty' do
      it 'returns false' do
        poa = create(:power_of_attorney, auth_headers: {})
        expect(poa.belongs_to_veteran?(veteran_pid)).to be false
      end
    end

    context 'when participant_id is nil or blank' do
      it 'returns false for nil' do
        expect(poa_with_veteran_only.belongs_to_veteran?(nil)).to be false
      end

      it 'returns false for empty string' do
        expect(poa_with_veteran_only.belongs_to_veteran?('')).to be false
      end
    end
  end

  describe 'process error handling' do
    let(:poa) do
      ClaimsApi::PowerOfAttorney.create!(
        auth_headers: {},
        status: '',
        form_data: {},
        current_poa: '',
        header_hash: {},
        cid: '123'
      )
    end

    it 'gets ClaimsApi::Process errors and does not override ActiveRecord errors' do
      # Create a process and add an error message
      process = ClaimsApi::Process.create!(
        processable: poa,
        step_type: 'PDF_SUBMISSION',
        step_status: 'IN_PROGRESS'
      )
      process.error_messages.push(
        { 'title' => 'BGS Error', 'detail' => 'updatePoaAccess: No POA found on system of record',
          'code' => 'POA_ACCESS_UPDATE' }
      )
      process.save!

      # Reload POA and verify process association
      rec = ClaimsApi::PowerOfAttorney.find(poa.id)
      expect(rec.processes.map(&:id)).to include(process.id)

      # This test covers a bug with method name collision between ActiveRecord::Errors and our custom method.
      # Before fix: rec.errors would attempt to use the active record method and break because errors was an array
      # After fix: rec.errors should be an active record errors object, process_errors should return the process error
      expect(rec.errors).to be_empty

      expect(rec.process_errors).to eq([
                                         {
                                           title: 'BGS Error',
                                           detail: 'updatePoaAccess: No POA found on system of record',
                                           code: 'PDF_SUBMISSION'
                                         }
                                       ])

      # Should be able to update and save the POA without error
      rec[:status] = 'testing'
      expect { rec.save! }.not_to raise_error
    end
  end
end
