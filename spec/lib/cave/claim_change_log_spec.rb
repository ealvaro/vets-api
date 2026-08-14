# frozen_string_literal: true

require 'rails_helper'
require 'cave/claim_change_log'
require 'idp/client'

RSpec.describe Cave::ClaimChangeLog do
  let(:submission) do
    CaveSubmission.create!(
      cave_response: { 'VETERAN_NAME' => 'JON A DOE' }.to_json,
      cave_document_id: 'doc-1',
      kvpid: 'kvp-1',
      idp_user_id: 'user-1'
    )
  end

  let(:form_data) do
    { 'files' => [{ 'idpArtifacts' => { 'dd214' => [{ 'veteranName' => { 'first' => 'John', 'last' => 'Doe' } }] } }] }
  end

  let(:saved_claim) { instance_double(SavedClaim, id: 1, cave_submissions: [submission]) }

  it 'returns the formatted change-log remarks' do
    remarks = described_class.remarks_for(saved_claim, form_data)
    expect(remarks).to start_with('SYSTEM GENERATED TO DOCUMENT USER CHANGES')
    expect(remarks).to include('Veteran name: OCR Extracted Value: JON A DOE; User Updated Value: John Doe;')
  end

  it 'persists the change log on the submission' do
    described_class.remarks_for(saved_claim, form_data)
    expect(submission.reload.parsed_change_log.first).to include('field' => 'VETERAN_NAME')
  end

  describe 'forwarding corrections to CAVE' do
    let(:client) { instance_double(Idp::Client) }

    before do
      allow(Idp).to receive(:client).and_return(client)
      allow(Flipper).to receive(:enabled?).and_call_original
    end

    it 'does not forward when the flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:cave_change_log_forward_corrections).and_return(false)
      expect(client).not_to receive(:corrections)
      described_class.remarks_for(saved_claim, form_data)
    end

    it 'forwards the corrections payload when enabled' do
      allow(Flipper).to receive(:enabled?).with(:cave_change_log_forward_corrections).and_return(true)
      expect(client).to receive(:corrections)
        .with('doc-1', kvpid: 'kvp-1', payload: hash_including(:corrections), user_id: 'user-1')
      described_class.remarks_for(saved_claim, form_data)
    end

    it 'never lets a CAVE forwarding failure abort PDF generation' do
      allow(Flipper).to receive(:enabled?).with(:cave_change_log_forward_corrections).and_return(true)
      allow(client).to receive(:corrections).and_raise(StandardError, 'boom')
      expect { described_class.remarks_for(saved_claim, form_data) }.not_to raise_error
    end
  end
end
