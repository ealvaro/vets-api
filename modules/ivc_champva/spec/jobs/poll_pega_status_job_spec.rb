# frozen_string_literal: true

require 'rails_helper'
require 'pega_api/client'

RSpec.describe IvcChampva::PollPegaStatusJob do
  subject(:job) { described_class.new }

  let(:form_uuid) { SecureRandom.uuid }
  let(:created_at) { 2.hours.ago }

  def pega_report(case_id:, status:, uuid: form_uuid)
    {
      'PEGA Case ID' => case_id,
      'Doctype' => 'Application under 65',
      'Determination Type' => status,
      'Eligibity Date' => nil,
      'UUID' => uuid
    }
  end

  def stub_pega(reports:, uuid: form_uuid)
    allow_any_instance_of(IvcChampva::PegaApi::Client)
      .to receive(:get_status_by_uuid)
      .with(uuid)
      .and_return(reports)
  end

  before { allow(Flipper).to receive(:enabled?).with(described_class::FEATURE_TOGGLE).and_return(true) }

  describe '#perform' do
    context 'when the feature flag is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(described_class::FEATURE_TOGGLE).and_return(false) }

      it 'does not poll Pega and returns immediately' do
        expect_any_instance_of(IvcChampva::PegaApi::Client).not_to receive(:get_status_by_uuid)
        job.perform
      end
    end

    context 'when there are no forms to poll' do
      it 'does not call Pega' do
        expect_any_instance_of(IvcChampva::PegaApi::Client).not_to receive(:get_status_by_uuid)
        job.perform
      end
    end

    context 'when a form has no submitted_by_icn' do
      it 'still polls by form_uuid' do
        create(:ivc_champva_form, form_uuid:, submitted_by_icn: nil, pega_status: nil, created_at:)
        expect_any_instance_of(IvcChampva::PegaApi::Client)
          .to receive(:get_status_by_uuid).with(form_uuid).and_return([])
        job.perform
      end
    end

    context 'when a form already has a complete/terminal pega_status' do
      described_class::COMPLETE_STATUSES.each do |terminal_status|
        it "does not poll forms with status '#{terminal_status}'" do
          create(:ivc_champva_form, form_uuid:,
                                    pega_status: terminal_status, created_at:)
          expect_any_instance_of(IvcChampva::PegaApi::Client).not_to receive(:get_status_by_uuid)
          job.perform
        end
      end
    end

    context 'when a form has nil pega_status and no case_id (webhook never fired)' do
      let!(:forms) do
        create_list(:ivc_champva_form, 2, form_uuid:,
                                          pega_status: nil, case_id: nil, created_at:)
      end

      before do
        stub_pega(reports: [pega_report(case_id: 'D-12345', status: 'Received')])
      end

      it 'updates pega_status on all records sharing the form_uuid' do
        job.perform
        forms.each { |f| expect(f.reload.pega_status).to eq('Received') }
      end

      it 'assigns the case_id from the first report to all records' do
        job.perform
        forms.each { |f| expect(f.reload.case_id).to eq('D-12345') }
      end
    end

    context 'when a form already has a case_id' do
      let!(:form) do
        create(:ivc_champva_form, form_uuid:,
                                  pega_status: 'Open', case_id: 'D-100017', created_at:)
      end

      before do
        stub_pega(reports: [
                    pega_report(case_id: 'D-100018', status: 'Open'),
                    pega_report(case_id: 'D-100017', status: 'Processed')
                  ])
      end

      it 'updates using the report that matches the existing case_id, not the first report' do
        job.perform
        expect(form.reload.pega_status).to eq('Processed')
        expect(form.reload.case_id).to eq('D-100017')
      end
    end

    context 'when the matching report has unchanged status and case_id' do
      let!(:form) do
        create(:ivc_champva_form, form_uuid:,
                                  pega_status: 'Processed', case_id: 'D-100017', created_at:)
      end

      before do
        stub_pega(reports: [pega_report(case_id: 'D-100017', status: 'Processed')])
      end

      it 'does not write an update' do
        original_updated_at = form.updated_at
        sleep 0.01
        job.perform
        expect(form.reload.updated_at).to eq(original_updated_at)
      end
    end

    context 'when a form has a case_id that no longer appears in the Pega response' do
      let!(:form) do
        create(:ivc_champva_form, form_uuid:,
                                  pega_status: 'Open', case_id: 'D-GONE', created_at:)
      end

      before do
        stub_pega(reports: [pega_report(case_id: 'D-100018', status: 'Processed')])
      end

      it 'leaves pega_status unchanged' do
        job.perform
        expect(form.reload.pega_status).to eq('Open')
      end
    end

    context 'when a form has an in-progress status' do
      %w[submitted Submitted Received Processed].each do |in_progress_status|
        it "polls forms with status '#{in_progress_status}'" do
          uuid = SecureRandom.uuid
          form = create(:ivc_champva_form, form_uuid: uuid,
                                           pega_status: in_progress_status, case_id: nil, created_at:)
          stub_pega(uuid:, reports: [pega_report(case_id: 'D-new', status: 'Processed', uuid:)])
          job.perform
          expect(form.reload.pega_status).to eq('Processed')
        end
      end
    end

    context 'when Pega returns an empty array' do
      let!(:form) { create(:ivc_champva_form, form_uuid:, pega_status: nil, created_at:) }

      before do
        stub_pega(reports: [])
      end

      it 'leaves pega_status unchanged' do
        job.perform
        expect(form.reload.pega_status).to be_nil
      end
    end

    context 'when Pega returns a report with a blank status' do
      let!(:form) do
        create(:ivc_champva_form, form_uuid:,
                                  pega_status: nil, case_id: nil, created_at:)
      end

      before do
        stub_pega(reports: [pega_report(case_id: 'D-000', status: '')])
      end

      it 'leaves pega_status unchanged' do
        job.perform
        expect(form.reload.pega_status).to be_nil
      end
    end

    context 'when Pega returns the misspelled determination key' do
      let!(:form) do
        create(:ivc_champva_form, form_uuid:,
                                  pega_status: nil, case_id: nil, created_at:)
      end

      before do
        stub_pega(reports: [{
                    'PEGA Case ID' => 'D-777',
                    'Deternimation Type' => 'Processed',
                    'UUID' => form_uuid
                  }])
      end

      it 'uses Deternimation Type as a fallback for status' do
        job.perform
        expect(form.reload.pega_status).to eq('Processed')
        expect(form.reload.case_id).to eq('D-777')
      end
    end

    context 'when the Pega API raises a PegaApiError' do
      let!(:form) { create(:ivc_champva_form, form_uuid:, pega_status: nil, created_at:) }

      before do
        allow_any_instance_of(IvcChampva::PegaApi::Client)
          .to receive(:get_status_by_uuid)
          .and_raise(IvcChampva::PegaApi::PegaApiError, 'API timeout')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error' do
        job.perform
        expect(Rails.logger).to have_received(:error).with(/PegaApiError.*API timeout/)
      end

      it 'does not raise and continues to completion' do
        expect { job.perform }.not_to raise_error
      end

      it 'does not update pega_status' do
        job.perform
        expect(form.reload.pega_status).to be_nil
      end
    end

    context 'when multiple form_uuids are in different states' do
      let(:uuid_pending)  { SecureRandom.uuid }
      let(:uuid_received) { SecureRandom.uuid }
      let(:uuid_complete) { SecureRandom.uuid }
      let!(:pending_form) do
        create(:ivc_champva_form, form_uuid: uuid_pending,  pega_status: nil,        case_id: nil, created_at:)
      end
      let!(:received_form) do
        create(:ivc_champva_form, form_uuid: uuid_received, pega_status: 'Received', case_id: nil, created_at:)
      end
      let!(:complete_form) do
        create(:ivc_champva_form, form_uuid: uuid_complete, pega_status: 'eligible - issued a card', created_at:)
      end

      before do
        reports_by_uuid = {
          uuid_pending => [pega_report(case_id: 'D-1', status: 'Processed', uuid: uuid_pending)],
          uuid_received => [pega_report(case_id: 'D-2', status: 'Processed', uuid: uuid_received)]
        }
        allow_any_instance_of(IvcChampva::PegaApi::Client).to receive(:get_status_by_uuid) do |_, uuid|
          reports_by_uuid[uuid] || []
        end
      end

      it 'updates pending and in-progress forms' do
        job.perform
        expect(pending_form.reload.pega_status).to eq('Processed')
        expect(received_form.reload.pega_status).to eq('Processed')
      end

      it 'skips complete forms without updating their status' do
        job.perform
        expect(complete_form.reload.pega_status).to eq('eligible - issued a card')
      end
    end
  end
end
