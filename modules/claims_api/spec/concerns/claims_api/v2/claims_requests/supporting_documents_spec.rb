# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../../rails_helper'
require 'bd/bd'
require 'bgs_service/person_web_service'
require_relative '../../../../support/vcr_helpers'

describe ClaimsApi::V2::ClaimsRequests::SupportingDocuments do
  # supporting document filtering common methods
  def pre_filtered_uuids(search_data, letters_data)
    original_search_uuids = search_data[:data][:documents].to_set { |doc| doc[:documentUuid].gsub(/[{}]/, '') }
    original_letters_uuids = letters_data[:data][:documents].to_set { |doc| doc[:documentUuid].gsub(/[{}]/, '') }
    [original_search_uuids, original_letters_uuids]
  end

  def common_filtering_expectations(controller, claim_id, file_number, original_search_uuids, original_letters_uuids)
    result = controller.build_supporting_docs(
      { benefit_claim_details_dto: { benefit_claim_id: claim_id } }, file_number
    )
    # Check if there are common documents between search and letters responses
    common_documents = original_search_uuids & original_letters_uuids
    expect(common_documents).to be_present

    # Verify filtering occurred - result should equal search count minus filtered documents
    search_document_count = original_search_uuids.length
    expected_result_count = search_document_count - common_documents.length
    expect(result.length).to eq(expected_result_count)

    # Verify VA-generated documents (from letters_data) are not included in the results
    result_uuids = result.to_set { |doc| doc[:document_uuid].gsub(/[{}]/, '') }
    expect(result_uuids & original_letters_uuids).to be_empty
  end

  let(:fake_documents_controller_class) do
    Class.new do
      include ClaimsApi::V2::ClaimsRequests::SupportingDocuments

      def local_bgs_service
        id = target_veteran.participant_id
        if Flipper.enabled? :claims_api_use_person_web_service
          ClaimsApi::PersonWebService.new(
            external_uid: id,
            external_key: id
          )
        else
          ClaimsApi::LocalBGS.new(
            external_uid: id,
            external_key: id
          )
        end
      end

      def target_veteran
        @target_veteran ||= OpenStruct.new(
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
  end
  let(:bgs_claim) do
    {
      benefit_claim_details_dto: {
        benefit_claim_id: '600397218'
      }
    }
  end
  let(:ssn) { '796378782' }

  let(:controller) { fake_documents_controller_class.new }

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

    context 'when claim is looked up by UUID (params[:id] is a UUID, claim_id is numeric)' do
      before do
        allow(controller).to receive(:params).and_return({ id: 'abc12345-6789-def0-1234-abcdef567890' })
      end

      it 'uses the resolved claim_id from bgs_claim, not params[:id]' do
        VCR.use_cassette('claims_api/bd/search_with_participant_id') do
          expect(controller.benefits_doc_api).to receive(:search).with('600397218', participant_id: '600045025')
                                                                 .and_call_original
          result = controller.build_supporting_docs(bgs_claim, ssn)
          expect(result.length).to eq(1)
          expect(result[0][:document_id]).to eq('{6A40E389-EB12-473C-8C23-D1D6C996C544}')
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

  describe 'when VA generated document filtering is enabled' do
    let(:file_number) { '796378782' }
    let(:participant_id) { '600045025' }
    let(:claim_id) { '600397218' }

    let(:bd_service) { instance_double(ClaimsApi::BD) }

    let(:search_data) do
      VcrHelpers.load_vcr_response_data('claims_api/bd/claim_with_mixed_documents_search', 1)
    end
    let(:letters_data) do
      VcrHelpers.load_vcr_response_data('claims_api/bd/claim_with_mixed_documents_letters_search', 1)
    end

    before do
      # stub BD service methods
      allow(ClaimsApi::BD).to receive(:new).and_return(bd_service)
      allow(bd_service).to receive(:search).with(claim_id, participant_id:).and_return(search_data)
      allow(bd_service).to receive(:claim_letters_search).with(
        file_number: nil, participant_id:
      ).and_return(letters_data)
    end

    context 'when searching with a participant_id and bd.search includes VA documents' do
      before do
        allow(controller).to receive(:determine_veteran_identifier).and_return({ participant_id: })
      end

      it 'filters out VA-generated documents from the documents/search response' do
        # Extract UUIDs before mutation occurs
        original_search_uuids, original_letters_uuids = pre_filtered_uuids(search_data, letters_data)
        common_filtering_expectations(controller, claim_id, file_number, original_search_uuids, original_letters_uuids)
        expect(bd_service).to have_received(:search).with(claim_id, participant_id:)
        expect(bd_service).to have_received(:claim_letters_search).with(participant_id:, file_number: nil)
      end
    end

    context 'when using file_number for search' do
      let(:participant_id) { nil }

      before do
        allow(controller).to receive(:determine_veteran_identifier).and_return({ file_number: })
        # Override the stubs for file_number search
        allow(bd_service).to receive(:search).with(claim_id, file_number:).and_return(search_data)
        allow(bd_service).to receive(:claim_letters_search).with(
          file_number:, participant_id: nil
        ).and_return(letters_data)
      end

      it 'uses file_number when participant_id is not available' do
        # Extract UUIDs before mutation occurs
        original_search_uuids, original_letters_uuids = pre_filtered_uuids(search_data, letters_data)
        common_filtering_expectations(controller, claim_id, file_number, original_search_uuids, original_letters_uuids)
        expect(bd_service).to have_received(:search).with(claim_id, file_number:)
        expect(bd_service).to have_received(:claim_letters_search).with(file_number:, participant_id: nil)
      end
    end

    context 'when no letters are found in claim_letters_search' do
      let(:empty_letters_data) { { data: { documents: [] } } }

      before do
        allow(controller).to receive(:determine_veteran_identifier).and_return({ participant_id: })
        allow(bd_service).to receive(:claim_letters_search).with(
          file_number: nil, participant_id:
        ).and_return(empty_letters_data)
      end

      it 'returns all documents from the documents/search response' do
        # Extract UUIDs before mutation occurs
        original_search_uuids, = pre_filtered_uuids(search_data, letters_data)

        result = controller.build_supporting_docs(
          { benefit_claim_details_dto: { benefit_claim_id: claim_id } }, file_number
        )

        # Should return all documents since no filtering occurs
        expect(result.length).to eq(search_data[:data][:documents].length)
        expect(result.map { |doc| doc[:document_uuid].gsub(/[{}]/, '') }).to match_array(original_search_uuids)
        expect(bd_service).to have_received(:claim_letters_search).with(participant_id:, file_number: nil)
      end
    end
  end
end
