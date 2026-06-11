# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'persistent_attachment_remediation:run rake task', type: :task do
  before(:all) do
    Rake.application.rake_require '../rakelib/persistent_attachment_remediation'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['persistent_attachment_remediation:run'] }

  before { task.reenable }

  describe 'email sending via VANotify' do
    let(:claim_id) { '999' }
    let(:email_address) { 'veteran@example.com' }
    let(:template_id) { 'template-abc-123' }
    let(:api_key) { 'fake-api-key-value' }
    let(:vanotify_service) { '21p_527ez' }
    let(:form_id) { '21P-527EZ' }

    let(:parsed_form_data) do
      {
        'veteranFullName' => { 'first' => 'Test', 'last' => 'User' },
        'email' => email_address,
        'veteranSocialSecurityNumber' => '111223333',
        'files' => [
          { 'confirmationCode' => 'bad-guid-001', 'name' => 'testfile.pdf' }
        ]
      }
    end

    let(:open_struct_form) do
      JSON.parse(parsed_form_data.to_json, object_class: OpenStruct)
    end

    let(:claim) do
      instance_double(
        Pensions::SavedClaim,
        id: claim_id.to_i,
        type: 'Pensions::SavedClaim',
        class: Pensions::SavedClaim,
        form_id:,
        email: email_address,
        form: parsed_form_data.to_json,
        parsed_form: parsed_form_data,
        open_struct_form:,
        attachment_keys: [:files],
        respond_to?: nil,
        destroy!: true
      )
    end

    let(:bad_attachment) do
      instance_double(PersistentAttachment, id: 1, guid: 'bad-guid-001', saved_claim_id: nil)
    end

    let(:service_config) do
      OpenStruct.new(
        api_key:,
        email: OpenStruct.new(
          persistent_attachment_error: OpenStruct.new(template_id:)
        )
      )
    end

    before do
      allow(SavedClaim).to receive(:find_by).with(id: claim_id).and_return(claim)
      allow(claim).to receive(:respond_to?).with(:attachment_keys).and_return(true)
      allow(claim).to receive(:respond_to?).with(:open_struct_form).and_return(true)
      allow(claim).to receive(:respond_to?).with(:attachment_key_map).and_return(false)

      allow(PersistentAttachment).to receive(:where)
        .with(guid: ['bad-guid-001'])
        .and_return([bad_attachment])
      allow(bad_attachment).to receive(:file_data).and_raise(
        StandardError.new('KMS decrypt error')
      )
      allow(bad_attachment).to receive(:delete)

      allow(InProgressForm).to receive(:where).and_return(InProgressForm.none)

      allow(Settings.vanotify).to receive(:services).and_return(
        OpenStruct.new(vanotify_service => service_config)
      )
      allow(Settings.vanotify.services).to receive(:[])
        .with(vanotify_service).and_return(service_config)

      allow(VANotify::EmailJob).to receive(:perform_async)
      allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
    end

    context 'when va_notify_v2_persistent_attachment_remediation is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:va_notify_v2_persistent_attachment_remediation)
          .and_return(false)
      end

      it 'sends email via V1 EmailJob' do
        task.invoke(claim_id, 'false')

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          email_address,
          template_id,
          hash_including(
            first_name: 'Test',
            claim_type: 'Application for Veterans Pension (VA Form 21P-527EZ)',
            url: 'http://va.gov/pension/apply-for-veteran-pension-form-21p-527ez'
          ),
          api_key
        )
        expect(VANotify::V2::QueueEmailJob).not_to have_received(:enqueue)
      end
    end

    context 'when va_notify_v2_persistent_attachment_remediation is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:va_notify_v2_persistent_attachment_remediation)
          .and_return(true)
      end

      it 'sends email via V2 QueueEmailJob' do
        task.invoke(claim_id, 'false')

        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          email_address,
          template_id,
          hash_including(
            first_name: 'Test',
            claim_type: 'Application for Veterans Pension (VA Form 21P-527EZ)',
            url: 'http://va.gov/pension/apply-for-veteran-pension-form-21p-527ez'
          ),
          'Settings.vanotify.services.21p_527ez.api_key'
        )
        expect(VANotify::EmailJob).not_to have_received(:perform_async)
      end
    end
  end
end
