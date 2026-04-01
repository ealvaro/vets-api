# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../../rails_helper'
require 'bd/bd'
require 'bgs_service/person_web_service'

class FakeController
  include ClaimsApi::V2::ClaimsRequests::SupportingDocuments

  def local_bgs_service
    if Flipper.enabled? :claims_api_use_person_web_service
      ClaimsApi::PersonWebService.new(
        external_uid: target_veteran.participant_id,
        external_key: target_veteran.participant_id
      )
    else
      ClaimsApi::LocalBGS.new(
        external_uid: target_veteran.participant_id,
        external_key: target_veteran.participant_id
      )
    end
  end

  def target_veteran
    OpenStruct.new(
      icn: '1012667169V030190',
      first_name: 'Ralph',
      last_name: 'Lee',
      loa: { current: 3, highest: 3 },
      ssn: '796378782',
      edipi: '8040545646',
      participant_id: '600045025',
      mpi: OpenStruct.new(
        icn: '1012667169V030190',
        profile: OpenStruct.new(ssn: '796378782')
      )
    )
  end

  def request
    { request_id: '222222222' }
  end

  def benefits_doc_api
    @benefits_doc_api ||= ClaimsApi::BD.new
  end

  def claims_v2_logging(*)
    true
  end

  def params
    { id: '600397218' }
  end
end

describe ClaimsApi::V2::ClaimsRequests::SupportingDocuments do
  let(:bgs_claim) do
    {
      benefit_claim_details_dto: {
        benefit_claim_id: '600397218'
      }
    }
  end
  let(:ssn) { '796378782' }

  let(:dummy_class) { Class.new { include ClaimsApi::V2::ClaimsRequests::SupportingDocuments } }

  let(:controller) { FakeController.new }

  before do
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_use_birls_id).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:claims_api_use_person_web_service).and_return(false)
    stub_claims_api_auth_token
  end

  describe '#build_supporting_docs from Benefits Documents' do
    context 'when participant_id is present' do
      it 'builds and returns the correct number of docs using participant_id' do
        VCR.use_cassette('claims_api/bd/search_with_participant_id') do
          result = controller.build_supporting_docs(bgs_claim, ssn)
          expect(result.length).to eq(1)
        end
      end

      it 'builds the correct doc output using participant_id' do
        VCR.use_cassette('claims_api/bd/search_with_participant_id') do
          result = controller.build_supporting_docs(bgs_claim, ssn)

          expect(result[0][:document_id]).to eq('{6A40E389-EB12-473C-8C23-D1D6C996C544}')
          expect(result[0][:document_uuid]).to eq('{29421740-dc43-4634-be42-17dfabf3502e}')
          expect(result[0][:document_type_label]).to eq('VA 21-526EZ, Fully Developed Claim (Compensation)')
          expect(result[0][:original_file_name]).to eq('RALPH_LEE_600397218_526.pdf')
          expect(result[0][:tracked_item_id]).to be_nil
          expect(result[0][:upload_date]).to eq('2023-04-14')
          expect(result[0][:upload_date_time]).to eq('2023-04-14T13:55:00Z')
        end
      end
    end

    context 'when participant_id is not present' do
      before do
        allow(controller.target_veteran).to receive(:participant_id).and_return(nil)
        allow(controller).to receive(:get_file_number).with('796378782').and_return('796378782')
      end

      it 'builds and returns the correct number of docs using file_number' do
        VCR.use_cassette('claims_api/bd/search_with_file_number') do
          result = controller.build_supporting_docs(bgs_claim, ssn)
          expect(result.length).to eq(1)
        end
      end

      it 'builds the correct doc output using file_number' do
        VCR.use_cassette('claims_api/bd/search_with_file_number') do
          result = controller.build_supporting_docs(bgs_claim, ssn)

          expect(result[0][:document_id]).to eq('{6A40E389-EB12-473C-8C23-D1D6C996C544}')
          expect(result[0][:document_uuid]).to eq('{29421740-dc43-4634-be42-17dfabf3502e}')
          expect(result[0][:document_type_label]).to eq('VA 21-526EZ, Fully Developed Claim (Compensation)')
          expect(result[0][:original_file_name]).to eq('RALPH_LEE_600397218_526.pdf')
          expect(result[0][:tracked_item_id]).to be_nil
          expect(result[0][:upload_date]).to eq('2023-04-14')
          expect(result[0][:upload_date_time]).to eq('2023-04-14T13:55:00Z')
        end
      end
    end
  end

  describe '#bd_upload_date' do
    it 'properly formats the date when a date is sent' do
      result = controller.bd_upload_date('2023-04-14T13:55:00Z')
      expect(result).to eq('2023-04-14')
    end

    it 'returns nil if the date is empty' do
      result = controller.bd_upload_date(nil)
      expect(result).to be_nil
    end
  end

  describe '#upload_date' do
    it 'properly formats the date when a date is sent' do
      result = controller.upload_date(1_414_781_700_000)

      expect(result).to eq('2014-10-31')
    end

    it 'returns nil if the date is empty' do
      result = controller.upload_date(nil)
      expect(result).to be_nil
    end
  end

  describe 'when the claims_api_use_person_web_service flipper is on' do
    let(:person_web_service) { instance_double(ClaimsApi::PersonWebService) }

    before do
      allow(Flipper).to receive(:enabled?).with(:claims_api_use_person_web_service).and_return true
      allow(ClaimsApi::PersonWebService).to receive(:new).with(external_uid: anything,
                                                               external_key: anything)
                                                         .and_return(person_web_service)
      allow(person_web_service).to receive(:find_by_ssn).and_return({ file_nbr: '796378782' })
    end

    it 'calls local bgs services instead of bgs-ext' do
      controller.find_by_ssn(ssn) # rubocop:disable Rails/DynamicFindBy
      expect(person_web_service).to have_received(:find_by_ssn)
    end
  end
end
