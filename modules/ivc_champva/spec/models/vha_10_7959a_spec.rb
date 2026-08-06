# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::VHA107959a do
  let(:current_user) { build(:user, :loa3) }

  let(:data) do
    {
      'primary_contact_info' => {
        'name' => {
          'first' => 'Veteran',
          'last' => 'Surname'
        },
        'email' => 'veteran.contact@example.com'
      },
      'applicant_member_number' => '123456789',
      'applicant_name' => { 'first' => 'John', 'middle' => 'P', 'last' => 'Doe' },
      'applicant_address' => { 'country' => 'USA', 'postal_code' => '12345' },
      'form_number' => '10-7959A',
      'veteran_supporting_documents' => [
        { 'confirmation_code' => 'abc123' },
        { 'confirmation_code' => 'def456' }
      ]
    }
  end
  let(:vha_10_7959a) { described_class.new(data) }

  let(:medical_resubmission_data) do
    data.merge(
      'claim_status' => 'resubmission',
      'pdi_or_claim_number' => 'PDI number',
      'identifying_number' => 'va12345678',
      'claim_type' => 'medical',
      'provider_name' => 'BCBS',
      'beginning_date_of_service' => '01-01-1999',
      'end_date_of_service' => '01-02-1999'
    )
  end
  let(:vha107959a_medical_resubmission) { described_class.new(medical_resubmission_data) }

  describe '#metadata' do
    context 'when champva_update_metadata_keys flipper is enabled' do
      it 'returns metadata for the form' do
        allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(true)
        metadata = vha_10_7959a.metadata

        expect(metadata).to include(
          'sponsorFirstName' => 'John',
          'sponsorLastName' => 'Doe',
          'zipCode' => '12345',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '10-7959A',
          'ssn_or_tin' => '123456789',
          'fileNumber' => '123456789',
          'businessLine' => 'CMP',
          'primaryContactInfo' => {
            'name' => {
              'first' => 'Veteran',
              'last' => 'Surname'
            },
            'email' => 'veteran.contact@example.com'
          },
          'primaryContactEmail' => 'veteran.contact@example.com'
        )
      end
    end

    context 'when champva_update_metadata_keys flipper is disabled' do
      it 'returns metadata for the form' do
        allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
        metadata = vha_10_7959a.metadata

        expect(metadata).to include(
          'veteranFirstName' => 'John',
          'veteranLastName' => 'Doe',
          'zipCode' => '12345',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '10-7959A',
          'ssn_or_tin' => '123456789',
          'fileNumber' => '123456789',
          'businessLine' => 'CMP',
          'primaryContactInfo' => {
            'name' => {
              'first' => 'Veteran',
              'last' => 'Surname'
            },
            'email' => 'veteran.contact@example.com'
          },
          'primaryContactEmail' => 'veteran.contact@example.com'
        )
      end
    end
  end

  describe '#metadata built from the JSON fixture (Pega payload)' do
    let(:fixture_data) do
      JSON.parse(
        Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959a.json').read
      )
    end
    let(:known_uuid) { 'test-uuid-10-7959a' }
    let(:form) { described_class.new(fixture_data) }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
      allow(SecureRandom).to receive(:uuid).and_return(known_uuid)
    end

    it 'produces the full metadata.json body from the fixture data' do
      expect(form.metadata).to eq(
        'veteranFirstName' => 'GI',
        'veteranLastName' => 'Joe',
        'zipCode' => '12345',
        'source' => 'VA Platform Digital Forms',
        'docType' => '10-7959A',
        'businessLine' => 'CMP',
        'ssn_or_tin' => '12345678',
        'member_number' => '12345678',
        'fileNumber' => '12345678',
        'country' => 'USA',
        'uuid' => known_uuid,
        'primaryContactInfo' => {
          'name' => { 'first' => 'Beneficiary', 'last' => 'Jones' },
          'email' => 'beneficiary.contact@example.com',
          'phone' => '1231231234'
        },
        'primaryContactEmail' => 'beneficiary.contact@example.com',
        'claim_type' => 'medical'
      )
    end

    it 'transforms validated metadata into the S3/Pega PDF attachment metadata' do
      validated = form.validated_metadata

      result = IvcChampva::DataTransformations.metadata_for_s3(
        validated.merge('attachment_ids' => %w[vha_10_7959a vha_10_7959a 0 1]), form.form_id
      )

      expect(result).to eq(validated.except('primaryContactInfo').merge('attachment_id' => 'vha_10_7959a'))
      expect(result).not_to have_key('primaryContactInfo')
      expect(result).not_to have_key('attachment_ids')
    end
  end

  describe '#add_resubmission_properties' do
    context 'when medical claim resubmission data is present' do
      it 'includes a key for each present resubmission property' do
        res = vha107959a_medical_resubmission.add_resubmission_properties
        expect(res.keys.include?('claim_status')).to be(true)
        expect(res.keys.include?('pdi_or_claim_number')).to be(true)
        expect(res.keys.include?('claim_type')).to be(true)
        expect(res.keys.include?('provider_name')).to be(true)
        expect(res.keys.include?('beginning_date_of_service')).to be(true)
        expect(res.keys.include?('end_date_of_service')).to be(true)
        expect(res.keys.include?('pdi_number')).to be(true)
      end

      it 'contains resubmission data' do
        res = vha107959a_medical_resubmission.add_resubmission_properties
        expect(res['claim_status']).to eq('resubmission')
      end

      it 'includes relevant pdi field and excludes claim number field when pdi number was specified' do
        res = vha107959a_medical_resubmission.add_resubmission_properties
        expect(res.keys.include?('pdi_number')).to be(true)
        expect(res.keys.include?('claim_number')).to be(false)
      end
    end

    context 'when resubmission properties are missing' do
      context 'when champva_update_metadata_keys flipper is enabled' do
        it 'does not interfere with metadata creation' do
          allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(true)

          expect(vha_10_7959a.metadata.keys.include?('sponsorFirstName')).to be(true)
        end
      end

      context 'when champva_update_metadata_keys flipper is disabled' do
        it 'does not interfere with metadata creation' do
          allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)

          expect(vha_10_7959a.metadata.keys.include?('veteranFirstName')).to be(true)
        end
      end

      it 'does not include resubmission property if there is no corresponding value' do
        # vha_10_7959a was initialized with no resubmission values
        res = vha_10_7959a.add_resubmission_properties
        # this key will not be present even though `add_resubmission_properties` attempts to get it from the form data
        expect(res.keys.include?('claim_status')).to be(false)
      end
    end
  end

  describe '#stamp_metadata' do
    context 'when champva_claims_duty_to_assist flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(false)
      end

      it 'returns nil' do
        expect(vha_10_7959a.stamp_metadata).to be_nil
      end
    end

    context 'when champva_claims_duty_to_assist flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
      end

      context 'when has_claim_docs is nil' do
        it 'returns nil because DTA does not apply' do
          expect(vha_10_7959a.stamp_metadata).to be_nil
        end
      end

      context 'when has_claim_docs is true (user has docs)' do
        let(:data_with_docs) { data.merge('has_claim_docs' => true) }
        let(:form_with_docs) { described_class.new(data_with_docs) }

        it 'returns nil because DTA does not apply' do
          expect(form_with_docs.stamp_metadata).to be_nil
        end
      end

      context 'when has_claim_docs is false (DTA applies)' do
        let(:dta_data) { data.merge('has_claim_docs' => false, 'provider_name' => 'Memorial Hospital') }
        let(:form_dta) { described_class.new(dta_data) }

        it 'returns metadata hash with attachment_id' do
          result = form_dta.stamp_metadata

          expect(result).to be_a(Hash)
          expect(result[:attachment_id]).to eq('Duty to Assist')
          expect(result[:metadata]).to include('provider_name', 'service_start_date', 'service_end_date')
        end
      end
    end
  end

  describe '#dta?' do
    context 'when has_claim_docs is true' do
      let(:data_with_docs) { data.merge('has_claim_docs' => true) }
      let(:form_with_docs) { described_class.new(data_with_docs) }

      it 'returns false' do
        expect(form_with_docs.dta?).to be(false)
      end
    end

    context 'when has_claim_docs is false' do
      let(:data_without_docs) { data.merge('has_claim_docs' => false) }
      let(:form_without_docs) { described_class.new(data_without_docs) }

      it 'returns true' do
        expect(form_without_docs.dta?).to be(true)
      end
    end

    context 'when has_claim_docs is nil' do
      it 'returns false' do
        expect(vha_10_7959a.dta?).to be(false)
      end
    end
  end

  describe '#build_dta_metadata' do
    it 'always returns all DTA field keys' do
      result = vha_10_7959a.build_dta_metadata

      expect(result.keys).to contain_exactly(
        'provider_name',
        'provider_phone',
        'provider_fax',
        'provider_email',
        'service_start_date',
        'service_end_date',
        'additional_comments'
      )
    end

    context 'when DTA fields have values' do
      let(:dta_data) do
        data.merge(
          'provider_name' => 'Memorial Hospital',
          'provider_phone' => '555-123-4567',
          'service_start_date' => '2024-01-15'
        )
      end
      let(:form_with_dta) { described_class.new(dta_data) }

      it 'includes the provided values' do
        result = form_with_dta.build_dta_metadata

        expect(result['provider_name']).to eq('Memorial Hospital')
        expect(result['provider_phone']).to eq('555-123-4567')
        expect(result['service_start_date']).to eq('2024-01-15')
        expect(result['service_end_date']).to be_nil
      end
    end
  end

  describe '#track_email_usage' do
    let(:statsd_key) { 'api.ivc_champva_form.10_7959a' }

    context 'when email is used' do
      let(:data) { { 'primary_contact_info' => { 'email' => 'test@example.com' } } }

      it 'increments the StatsD for email used and logs the info' do
        expect(StatsD).to receive(:increment).with("#{statsd_key}.yes")
        expect(Rails.logger).to receive(:info).with('IVC ChampVA Forms - 10-7959A Email Used', email_used: 'yes')
        vha_10_7959a.track_email_usage
      end
    end

    context 'when email is not used' do
      let(:data) { { 'primary_contact_info' => {} } }

      it 'increments the StatsD for email not used and logs the info' do
        expect(StatsD).to receive(:increment).with("#{statsd_key}.no")
        expect(Rails.logger).to receive(:info).with('IVC ChampVA Forms - 10-7959A Email Used', email_used: 'no')
        vha_10_7959a.track_email_usage
      end
    end
  end

  describe '#track_current_user_loa' do
    it 'logs current user loa' do
      expect(Rails.logger).to receive(:info)
        .with('IVC ChampVA Forms - 10-7959A Current User LOA', { current_user_loa: 3 })
      vha_10_7959a.track_current_user_loa(current_user)
    end
  end

  describe '#track_submission' do
    let(:statsd_key) { 'api.ivc_champva_form.10_7959a' }
    let(:form_version) { 'vha_10_7959a' }
    let(:mock_verification) { double(verified?: true) }
    let(:mock_user) { double(loa: { current: 3 }, user_verification: mock_verification) }

    context 'with standard form flow' do
      let(:submission_data) do
        {
          'certifier_role' => 'applicant',
          'primary_contact_info' => { 'email' => 'test@example.com' },
          'form_number' => '10-7959A'
        }
      end
      let(:form_instance) { described_class.new(submission_data) }

      it 'increments StatsD with tags and logs submission info' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:applicant', 'current_user_loa:3',
                 'current_user_ial:2', 'email_used:yes', 'form_version:vha_10_7959a', 'claim_status:',
                 'duty_to_assist:false', 'pdi_or_claim_number:']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959A Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: 'applicant',
          current_user_loa: 3,
          current_user_ial: 2,
          email_used: 'yes',
          form_version:,
          claim_status: nil,
          duty_to_assist: false,
          pdi_or_claim_number: nil
        )

        form_instance.track_submission(mock_user)
      end
    end

    context 'when current_user is nil' do
      let(:submission_data) do
        {
          'certifier_role' => 'applicant',
          'primary_contact_info' => {},
          'form_number' => '10-7959A'
        }
      end
      let(:form_instance) { described_class.new(submission_data) }

      it 'defaults loa to 0 and ial to 0' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:applicant', 'current_user_loa:0',
                 'current_user_ial:0', 'email_used:no', 'form_version:vha_10_7959a', 'claim_status:',
                 'duty_to_assist:false', 'pdi_or_claim_number:']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959A Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: 'applicant',
          current_user_loa: 0,
          current_user_ial: 0,
          email_used: 'no',
          form_version:,
          claim_status: nil,
          duty_to_assist: false,
          pdi_or_claim_number: nil
        )

        form_instance.track_submission(nil)
      end
    end

    context 'with resubmission data' do
      let(:resubmission_data) do
        {
          'certifier_role' => 'sponsor',
          'primary_contact_info' => { 'email' => 'sponsor@example.com' },
          'form_number' => '10-7959A',
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'PDI number'
        }
      end
      let(:form_instance) { described_class.new(resubmission_data) }

      it 'includes resubmission tags in StatsD and logs' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:sponsor', 'current_user_loa:3',
                 'current_user_ial:2', 'email_used:yes', 'form_version:vha_10_7959a', 'claim_status:resubmission',
                 'duty_to_assist:false', 'pdi_or_claim_number:PDI number']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959A Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: 'sponsor',
          current_user_loa: 3,
          current_user_ial: 2,
          email_used: 'yes',
          form_version:,
          claim_status: 'resubmission',
          duty_to_assist: false,
          pdi_or_claim_number: 'PDI number'
        )

        form_instance.track_submission(mock_user)
      end
    end

    context 'with Control number resubmission' do
      let(:control_number_data) do
        {
          'certifier_role' => 'sponsor',
          'primary_contact_info' => {},
          'form_number' => '10-7959A',
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'Control number'
        }
      end
      let(:form_instance) { described_class.new(control_number_data) }

      it 'tracks Control number in pdi_or_claim_number tag' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:sponsor', 'current_user_loa:3',
                 'current_user_ial:2', 'email_used:no', 'form_version:vha_10_7959a', 'claim_status:resubmission',
                 'duty_to_assist:false', 'pdi_or_claim_number:Control number']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959A Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: 'sponsor',
          current_user_loa: 3,
          current_user_ial: 2,
          email_used: 'no',
          form_version:,
          claim_status: 'resubmission',
          duty_to_assist: false,
          pdi_or_claim_number: 'Control number'
        )

        form_instance.track_submission(mock_user)
      end
    end
  end

  it 'is not past OMB expiration date' do
    # Update this date string to match the current PDF OMB expiration date:
    omb_expiration_date = Date.strptime('12312027', '%m%d%Y')
    error_message = <<~MSG
      If this test is failing it likely means the form 10-7959a PDF has reached
      OMB expiration date. Please see ivc_champva module README for details on updating the PDF file.
    MSG

    expect(omb_expiration_date.past?).to be(false), error_message
  end
end
