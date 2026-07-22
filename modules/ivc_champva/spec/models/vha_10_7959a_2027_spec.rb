# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::VHA107959a2027 do
  let(:current_user) { build(:user, :loa3) }

  let(:data) do
    {
      'primary_contact_info' => {
        'name' => { 'first' => 'Veteran', 'last' => 'Surname' },
        'email' => 'primary@example.com'
      },
      'applicant_email' => 'bene@example.com',
      'certifier_email' => 'signer@example.com',
      'applicant_member_number' => '123456789',
      'applicant_name' => { 'first' => 'John', 'middle' => 'P', 'last' => 'Doe' },
      'applicant_address' => { 'country' => 'USA', 'postal_code' => '12345' },
      'form_number' => '10-7959A',
      'has_ohi' => true,
      'policies' => [
        { 'type' => 'group', 'name' => 'BCBS', 'policy_num' => '1', 'provider_phone' => '555', 'other_type' => '' }
      ],
      'claims' => [
        { 'claim_is_auto_related' => true, 'claim_is_work_related' => false }
      ],
      'claim_is_auto_related' => true,
      'claim_is_work_related' => false
    }
  end

  let(:form) { described_class.new(data) }

  describe '#metadata' do
    it 'includes Pega-facing email fields and form expiration' do
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
      md = form.metadata

      expect(md['applicantEmail']).to eq('bene@example.com')
      expect(md['signerEmail']).to eq('signer@example.com')
      expect(md['formExpiration']).to eq('12/31/2027')
      expect(md['primaryContactEmail']).to eq('primary@example.com')
    end

    it 'passes the 2027 email and expiration fields through to the S3/Pega PDF metadata' do
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
      validated = form.validated_metadata

      result = IvcChampva::DataTransformations.metadata_for_s3(
        validated.merge('attachment_ids' => %w[vha_10_7959a]), 'vha_10_7959a'
      )

      expect(result).to include(
        'applicantEmail' => 'bene@example.com',
        'signerEmail' => 'signer@example.com',
        'formExpiration' => '12/31/2027',
        'attachment_id' => 'vha_10_7959a'
      )
      expect(result).not_to have_key('primaryContactInfo')
      expect(result).not_to have_key('attachment_ids')
    end
  end

  describe '#track_submission' do
    it 'tags StatsD with the 2027 form_version' do
      expect(StatsD).to receive(:increment).with(
        'api.ivc_champva_form.10_7959a.submission',
        satisfy { |opts| opts[:tags].include?('form_version:vha_10_7959a_2027') }
      )
      expect(Rails.logger).to receive(:info).with(
        'IVC ChampVA Forms - 10-7959A-2027 Submission',
        hash_including(form_version: 'vha_10_7959a_2027')
      )
      form.track_submission(current_user)
    end
  end

  it 'is not past OMB expiration date for the 2027-revision PDF' do
    omb_expiration_date = Date.strptime('12312027', '%m%d%Y')
    expect(omb_expiration_date.past?).to be(false)
  end

  describe 'FormVersionManager integration' do
    it 'resolves vha_10_7959a to the 2027 form id when versioning flags are on' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:champva_form_versioning, anything).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:champva_claims_insurance_dates, anything).and_return(true)

      expect(IvcChampva::FormVersionManager.resolve_form_version('vha_10_7959a', nil)).to eq('vha_10_7959a_2027')
      expect(IvcChampva::FormVersionManager.get_legacy_form_id('vha_10_7959a_2027')).to eq('vha_10_7959a')
    end
  end
end
