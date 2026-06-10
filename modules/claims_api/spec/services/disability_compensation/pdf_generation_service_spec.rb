# frozen_string_literal: true

require 'rails_helper'
require_relative '../../rails_helper'
require './modules/claims_api/app/services/claims_api/disability_compensation/pdf_generation_service'
require_relative '../../support/form_526_fixture_helper'

describe ClaimsApi::DisabilityCompensation::PdfGenerationService do
  let(:pdf_generation_service) { described_class.new }
  let(:user) { create(:user, :loa3) }
  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end
  let(:claim_date) { (Date.current - 1.day).to_s }
  let(:anticipated_separation_date) { 2.days.from_now.strftime('%m-%d-%Y') }
  let(:form_data) do
    temp = Form526FixtureHelper.new.data
    attributes = temp['data']['attributes']
    attributes['claimDate'] = claim_date
    attributes['serviceInformation']['federalActivation']['anticipatedSeparationDate'] = anticipated_separation_date

    temp['data']['attributes']
  end
  let(:claim) do
    claim = create(:auto_established_claim, :pending, form_data:)
    claim.auth_headers = auth_headers
    claim.transaction_id = '00000000-0000-0000-000000000000'
    claim.save
    claim
  end
  let(:created_at) { claim.created_at.strftime('%Y-%m-%d').to_s }
  let(:middle_initial) { ' ' }
  let(:mapped_claim) do
    { data: { attributes: { claimProcessType: 'STANDARD_CLAIM_PROCESS' } } }
  end

  describe '#generate' do
    it 'returns the claim status' do
      VCR.use_cassette('claims_api/pdf_client') do
        allow(pdf_generation_service).to receive(:generate_mapped_claim).with(claim,
                                                                              middle_initial).and_return(mapped_claim)

        expect(pdf_generation_service.send(:generate, claim.id, middle_initial)).to eq('pending')
      end
    end

    it 'logs the transaction_id' do
      VCR.use_cassette('claims_api/pdf_client') do
        allow(Rails.logger).to receive(:info)
        allow(pdf_generation_service).to receive(:generate_mapped_claim).with(claim,
                                                                              middle_initial).and_return(mapped_claim)
        pdf_generation_service.send(:generate, claim.id, middle_initial)
        expect(Rails.logger).to have_received(:info).with(/#{claim.transaction_id}/).at_least(:once)
      end
    end

    context 'when the pdf string is empty' do
      before do
        allow(pdf_generation_service).to receive(:generate_mapped_claim).with(claim,
                                                                              middle_initial).and_return(mapped_claim)
        allow(pdf_generation_service).to receive(:generate_526_pdf).with(mapped_claim).and_return('')
      end

      it 'returns the errored claim status' do
        VCR.use_cassette('claims_api/pdf_client') do
          expect(pdf_generation_service.send(:generate, claim.id, middle_initial)).to eq('errored')
        end
      end
    end

    context 'calling the PDF Generation Service' do
      it 'calls pdf_mapper_service with the correct params' do
        VCR.use_cassette('claims_api/pdf_client') do
          mock_mapper = instance_double(ClaimsApi::V2::DisabilityCompensationPdfMapper)

          expect(ClaimsApi::V2::DisabilityCompensationPdfMapper).to receive(:new).with(
            claim.form_data,
            pdf_generation_service.send(:get_pdf_data),
            claim.auth_headers,
            middle_initial,
            created_at
          ).and_return(mock_mapper)

          allow(mock_mapper).to receive(:map_claim).and_return(mapped_claim)
          allow(pdf_generation_service).to receive(:generate_526_pdf).with(mapped_claim).and_return('pdf_string')
          allow(Common::FileHelpers).to receive(:generate_random_file).and_return('tmp/some_file')
          allow(Common::FileHelpers).to receive(:delete_file_if_exists)
          allow(File).to receive(:open).and_return(double('file'))

          pdf_generation_service.send(:generate, claim.id, middle_initial)
        end
      end

      context 'with an invalid claimDate' do
        let(:claim_date) { '2026-02-30' }
        let(:expected_error_message) do
          [{ 'title' => 'Unprocessable entity', 'detail' => 'Invalid claim date provided',
             'status' => '422' }]
        end

        it 'raises a 422' do
          VCR.use_cassette('claims_api/pdf_client') do
            expect { pdf_generation_service.send(:generate, claim.id, middle_initial) }
              .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::UnprocessableEntity,
                              /Invalid claim date provided/)
          end
        end

        it 'sets claim status to errored' do
          VCR.use_cassette('claims_api/pdf_client') do
            begin
              pdf_generation_service.send(:generate, claim.id, middle_initial)
            rescue
              nil
            end

            claim.reload
            expect(claim.evss_response).to eq(expected_error_message)
            expect(claim.status).to eq('errored')
          end
        end
      end
    end
  end
end
