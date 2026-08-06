# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::VHA107959f1 do
  let(:data) do
    {
      'primary_contact_info' => {
        'name' => {
          'first' => 'Veteran',
          'last' => 'Surname'
        },
        'email' => 'email@address.com'
      },
      'veteran' => {
        'full_name' => { 'first' => 'John', 'middle' => 'P', 'last' => 'Doe' },
        'va_claim_number' => '123456789',
        'ssn' => '123456789',
        'mailing_address' => { 'country' => 'USA', 'postal_code' => '12345' }
      },
      'form_number' => '10-7959F-1',
      'veteran_supporting_documents' => [
        { 'confirmation_code' => 'abc123' },
        { 'confirmation_code' => 'def456' }
      ]
    }
  end
  let(:vha107959f1) { described_class.new(data) }
  let(:uuid) { SecureRandom.uuid }
  let(:instance) { IvcChampva::VHA107959f1.new(data) }

  before do
    allow(instance).to receive_messages(uuid:, get_attachments: [])
  end

  describe '#metadata' do
    context 'when champva_update_metadata_keys flipper is enabled' do
      it 'returns metadata for the form' do
        allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(true)
        metadata = vha107959f1.metadata

        expect(metadata).to include(
          'sponsorFirstName' => 'John',
          'sponsorMiddleName' => 'P',
          'sponsorLastName' => 'Doe',
          'fileNumber' => '123456789',
          'ssn_or_tin' => '123456789',
          'zipCode' => '12345',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '10-7959F-1',
          'businessLine' => 'CMP',
          'primaryContactInfo' => {
            'name' => {
              'first' => 'Veteran',
              'last' => 'Surname'
            },
            'email' => 'email@address.com'
          },
          'primaryContactEmail' => 'email@address.com'
        )
      end
    end

    context 'when champva_update_metadata_keys flipper is disabled' do
      it 'returns metadata for the form' do
        allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
        metadata = vha107959f1.metadata

        expect(metadata).to include(
          'veteranFirstName' => 'John',
          'veteranMiddleName' => 'P',
          'veteranLastName' => 'Doe',
          'fileNumber' => '123456789',
          'ssn_or_tin' => '123456789',
          'zipCode' => '12345',
          'country' => 'USA',
          'source' => 'VA Platform Digital Forms',
          'docType' => '10-7959F-1',
          'businessLine' => 'CMP',
          'primaryContactInfo' => {
            'name' => {
              'first' => 'Veteran',
              'last' => 'Surname'
            },
            'email' => 'email@address.com'
          },
          'primaryContactEmail' => 'email@address.com'
        )
      end
    end
  end

  describe '#metadata built from the JSON fixture (Pega payload)' do
    let(:fixture_data) do
      JSON.parse(
        Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_7959f_1.json').read
      )
    end
    let(:known_uuid) { 'test-uuid-10-7959f-1' }
    let(:form) { described_class.new(fixture_data) }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_update_metadata_keys).and_return(false)
      allow(SecureRandom).to receive(:uuid).and_return(known_uuid)
    end

    it 'produces the full metadata.json body from the fixture data' do
      expect(form.metadata).to eq(
        'veteranFirstName' => 'Veteran',
        'veteranMiddleName' => 'B',
        'veteranLastName' => 'Surname',
        'fileNumber' => '123456789',
        'zipCode' => '12345',
        'country' => 'USA',
        'source' => 'VA Platform Digital Forms',
        'ssn_or_tin' => '222554444',
        'docType' => '10-7959F-1',
        'businessLine' => 'CMP',
        'uuid' => known_uuid,
        'primaryContactInfo' => {
          'name' => { 'first' => 'Veteran', 'last' => 'Surname' },
          'email' => 'email@address.com'
        },
        'primaryContactEmail' => 'email@address.com'
      )
    end

    it 'transforms validated metadata into the S3/Pega PDF attachment metadata' do
      validated = form.validated_metadata

      result = IvcChampva::DataTransformations.metadata_for_s3(
        validated.merge('attachment_ids' => %w[vha_10_7959f_1]), form.form_id
      )

      expect(result).to eq(validated.except('primaryContactInfo').merge('attachment_id' => 'vha_10_7959f_1'))
      expect(result).not_to have_key('primaryContactInfo')
      expect(result).not_to have_key('attachment_ids')
    end
  end

  describe '#handle_attachments' do
    let(:file_path) { "#{uuid}_vha_10_7959f_1-tmp.pdf" }

    it 'renames the file and returns the new file path' do
      allow(File).to receive(:rename)
      result = instance.handle_attachments(file_path)
      expect(result).to eq(["#{uuid}_vha_10_7959f_1-tmp.pdf"])
    end
  end

  # rubocop:disable Naming/VariableNumber
  describe '#track_email_usage' do
    let(:statsd_key) { 'api.ivc_champva_form.10_7959f_1' }
    let(:vha_10_7959f_1) { described_class.new(data) }

    context 'when email is used' do
      let(:data) { { 'primary_contact_info' => { 'email' => 'test@example.com' } } }

      it 'increments the StatsD for email used and logs the info' do
        expect(StatsD).to receive(:increment).with("#{statsd_key}.yes")
        expect(Rails.logger).to receive(:info).with('IVC ChampVA Forms - 10-7959F-1 Email Used', email_used: 'yes')
        vha_10_7959f_1.track_email_usage
      end
    end

    context 'when email is not used' do
      let(:data) { { 'primary_contact_info' => {} } }

      it 'increments the StatsD for email not used and logs the info' do
        expect(StatsD).to receive(:increment).with("#{statsd_key}.no")
        expect(Rails.logger).to receive(:info).with('IVC ChampVA Forms - 10-7959F-1 Email Used', email_used: 'no')
        vha_10_7959f_1.track_email_usage
      end
    end
  end
  # rubocop:enable Naming/VariableNumber

  describe '#track_submission' do
    let(:statsd_key) { 'api.ivc_champva_form.10_7959f_1' }
    let(:mock_verification) { double(verified?: true) }
    let(:mock_user) { double(loa: { current: 3 }, user_verification: mock_verification) }

    context 'with a verified user' do
      let(:form_instance) { described_class.new(data) }

      it 'increments StatsD with tags and logs submission info including ial' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:', 'current_user_loa:3',
                 'current_user_ial:2', 'email_used:yes', 'form_version:vha_10_7959f_1']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959F-1 Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: nil,
          current_user_loa: 3,
          current_user_ial: 2,
          email_used: 'yes',
          form_version: 'vha_10_7959f_1'
        )

        form_instance.track_submission(mock_user)
      end
    end

    context 'when current_user is nil' do
      let(:form_instance) { described_class.new(data) }

      it 'defaults loa to 0 and ial to 0' do
        expect(StatsD).to receive(:increment).with(
          "#{statsd_key}.submission",
          tags: ["form_uuid:#{form_instance.metadata['uuid']}", 'identity:', 'current_user_loa:0',
                 'current_user_ial:0', 'email_used:yes', 'form_version:vha_10_7959f_1']
        )
        expect(Rails.logger).to receive(:info).with(
          'IVC ChampVA Forms - 10-7959F-1 Submission',
          form_uuid: form_instance.metadata['uuid'],
          identity: nil,
          current_user_loa: 0,
          current_user_ial: 0,
          email_used: 'yes',
          form_version: 'vha_10_7959f_1'
        )

        form_instance.track_submission(nil)
      end
    end
  end

  it 'is not past OMB expiration date' do
    # Update this date string to match the current PDF OMB expiration date:
    omb_expiration_date = Date.strptime('03312027', '%m%d%Y')
    error_message = <<~MSG
      If this test is failing it likely means the form 10-7959f-1 PDF has reached
      OMB expiration date. Please see ivc_champva module README for details on updating the PDF file.
    MSG

    expect(omb_expiration_date.past?).to be(false), error_message
  end
end
