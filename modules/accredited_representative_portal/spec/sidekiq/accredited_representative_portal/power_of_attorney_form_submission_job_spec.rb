# frozen_string_literal: true

require 'rails_helper'
require_relative '../../spec_helper'
require 'sidekiq/testing'

RSpec.describe AccreditedRepresentativePortal::PowerOfAttorneyFormSubmissionJob, type: :job do
  subject { described_class.new }

  let(:poa_request) { create(:power_of_attorney_request, :with_veteran_claimant) }
  let(:claimant_icn) { '123498767V234859' }

  let(:poa_form_submission) do
    create(:power_of_attorney_form_submission,
           service_id: '29b7c214-4a61-425e-97f2-1a56de869524',
           power_of_attorney_request: poa_request)
  end

  before do
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('<TOKEN>')
    poa_form_submission.power_of_attorney_request.claimant.update(icn: claimant_icn)
  end

  describe '#perform' do
    context 'successful LH submission' do
      context 'data shows status of pending' do
        let(:service_response) do
          File.read('modules/accredited_representative_portal/spec' \
                    '/fixtures/power_of_attorney_form_submission/pending.json')
        end

        it 'the form submission remains in enqueue_succeeded status' do
          expect do
            use_cassette('200_pending_response') do
              subject.perform(poa_form_submission.id)
            end
          end.to raise_error(described_class::PendingSubmissionError)
          poa_form_submission.reload
          expect(poa_form_submission.status).to eq 'enqueue_succeeded'
          expect(JSON.parse(poa_form_submission.service_response)).to eq JSON.parse(service_response)
          expect(poa_form_submission.status_updated_at).not_to be_nil
        end
      end

      context 'data shows status of submitted' do
        let(:service_response) do
          File.read('modules/accredited_representative_portal/spec' \
                    '/fixtures/power_of_attorney_form_submission/submitted.json')
        end

        it 'the form submission remains in enqueue_succeeded status' do
          expect do
            use_cassette('200_submitted_response') do
              subject.perform(poa_form_submission.id)
            end
          end.to raise_error(described_class::PendingSubmissionError)
          poa_form_submission.reload
          expect(poa_form_submission.status).to eq 'enqueue_succeeded'
          expect(JSON.parse(poa_form_submission.service_response)).to eq JSON.parse(service_response)
          expect(poa_form_submission.status_updated_at).not_to be_nil
        end
      end

      context 'successful submission' do
        let(:service_response) do
          File.read('modules/accredited_representative_portal/spec' \
                    '/fixtures/power_of_attorney_form_submission/updated.json')
        end

        it 'updates the form submission as successful' do
          use_cassette('200_updated_response') do
            subject.perform(poa_form_submission.id)
          end
          poa_form_submission.reload
          expect(poa_form_submission.status).to eq 'succeeded'
          expect(JSON.parse(poa_form_submission.service_response)).to eq JSON.parse(service_response)
          expect(poa_form_submission.status_updated_at).not_to be_nil
        end

        context 'data shows any steps have failed' do
          let(:expected_error_message) do
            '[{"title":"some error","detail":"error detail","code":"PDF_SUBMISSION"}]'
          end
          let(:service_response) do
            File.read('modules/accredited_representative_portal/spec' \
                      '/fixtures/power_of_attorney_form_submission/error.json')
          end

          it 'updates the form submission as failed' do
            use_cassette('200_errored_response') do
              subject.perform(poa_form_submission.id)
            end
            poa_form_submission.reload
            expect(poa_form_submission.status).to eq 'failed'
            expect(JSON.parse(poa_form_submission.service_response)).to eq JSON.parse(service_response)
            expect(poa_form_submission.error_message).to eq expected_error_message
            expect(poa_form_submission.status_updated_at).not_to be_nil
          end
        end

        context 'the job retries are exhausted' do
          let(:lh_service) { double }

          it 'updates the status as failed' do
            subject.sidekiq_retries_exhausted_block.call({ 'args' => [poa_form_submission.id] })
            poa_form_submission.reload
            expect(poa_form_submission.status).to eq('failed')
          end
        end
      end
    end

    context 'submission not found' do
      let(:rails_logger) { double }

      it 'updates the form submission and raises an error' do
        poa_form_submission.update(service_id: '491b878a-d977-40b8-8de9-7ba302307a48')
        expect do
          use_cassette('404_response') do
            subject.perform(poa_form_submission.id)
          end
        end.to raise_error(Common::Exceptions::ResourceNotFound)
        poa_form_submission.reload
        expect(poa_form_submission.error_message).to eq 'Resource not found'
        expect(poa_form_submission.status_updated_at).not_to be_nil
      end
    end

    context 'when the claimant is a Veteran' do
      let(:service) { instance_double(BenefitsClaims::Service) }
      let(:cassette) { '200_updated_response' }
      let(:service_response) do
        File.read('modules/accredited_representative_portal/spec' \
                  '/fixtures/power_of_attorney_form_submission/updated.json')
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(true)

        allow(AccreditedRepresentativePortal::ClaimantLookupService).to receive(:get_icn)

        allow(BenefitsClaims::Service).to receive(:new).and_return(service)
        allow(service).to receive(:get_2122_submission).and_return(JSON.parse(service_response))
      end

      it 'does not call ClaimantLookupService.get_icn' do
        expect(AccreditedRepresentativePortal::ClaimantLookupService).not_to receive(:get_icn)

        use_cassette(cassette) do
          subject.perform(poa_form_submission.id)
        end
      end

      it 'calls BenefitsClaims::Service.new with the claimant (Veteran) ICN' do
        expect(BenefitsClaims::Service).to receive(:new).with(claimant_icn)

        use_cassette(cassette) do
          subject.perform(poa_form_submission.id)
        end
      end
    end

    context 'when the claimant is a dependent' do
      let(:poa_request) { create(:power_of_attorney_request, :with_dependent_claimant) }
      let(:veteran_icn) { '1000000000V000000' }
      let(:service) { instance_double(BenefitsClaims::Service) }
      let(:cassette) { 'dependent_claimant/200_updated_response' }
      let(:service_response) do
        File.read('modules/accredited_representative_portal/spec' \
                  '/fixtures/power_of_attorney_form_submission/updated.json')
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(true)

        allow(AccreditedRepresentativePortal::ClaimantLookupService).to receive(:get_icn).and_return(veteran_icn)

        allow(BenefitsClaims::Service).to receive(:new).and_return(service)
        allow(service).to receive(:get_2122_submission).and_return(JSON.parse(service_response))
      end

      it 'calls ClaimantLookupService.get_icn with the proper Veteran arguments' do
        expect(AccreditedRepresentativePortal::ClaimantLookupService).to receive(:get_icn)
          .with('John', 'Doe', '123456789', '1980-12-31')

        use_cassette(cassette) do
          subject.perform(poa_form_submission.id)
        end
      end

      it 'calls BenefitsClaims::Service.new with the Veteran ICN' do
        expect(BenefitsClaims::Service).to receive(:new).with(veteran_icn)

        use_cassette(cassette) do
          subject.perform(poa_form_submission.id)
        end
      end
    end
  end
end
