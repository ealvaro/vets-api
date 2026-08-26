# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::VANotifyDeclinedJob, type: :job do
  subject { described_class.new }

  let(:va_notify_key) { ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController::VA_NOTIFY_KEY.to_s }
  let(:lockbox) { Lockbox.new(key: Settings.lockbox.master_key) }
  let(:vanotify_service) { instance_double(VaNotify::Service) }
  let(:ptcpnt_id) { '123456789' }
  let(:first_name) { 'Jane' }
  let(:encrypted_ptcpnt_id) { Base64.strict_encode64(lockbox.encrypt(ptcpnt_id)) }
  let(:encrypted_first_name) { Base64.strict_encode64(lockbox.encrypt(first_name)) }

  before do
    allow(Flipper).to receive(:enabled?)
      .with(ClaimsApi::AccreditationTables::FLAG).and_return(false)
  end

  context 'when the representative is a service organization' do
    let(:representative_id) { '123' }

    before do
      allow(VaNotify::Service).to receive(:new).with(anything).and_return(vanotify_service)
    end

    shared_examples 'sends a declined service organization notification' do
      let(:expected_form_type_text) do
        'Appointment of Veterans Service Organization as Claimantʼs Representative (VA Form 21-22)'
      end

      it 'sends a declined service organization notification' do
        expect(vanotify_service).to receive(:send_email)
          .with({
                  recipient_identifier: {
                    id_type: 'PID',
                    id_value: ptcpnt_id
                  },
                  personalisation: {
                    first_name:,
                    form_type: expected_form_type_text
                  },
                  template_id: Settings.claims_api.vanotify.declined_service_organization_template_id
                })

        subject.perform(encrypted_ptcpnt_id, encrypted_first_name, representative_id)
      end
    end

    context 'when the claims accreditation tables flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(ClaimsApi::AccreditationTables::FLAG).and_return(false)
        create(:veteran_representative, representative_id:, user_types: ['veteran_service_officer'])
      end

      include_examples 'sends a declined service organization notification'
    end

    context 'when the claims accreditation tables flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(ClaimsApi::AccreditationTables::FLAG).and_return(true)
        create(:claims_api_representative, representative_id:, user_types: ['veteran_service_officer'])
      end

      include_examples 'sends a declined service organization notification'
    end
  end

  context 'when the representative is an individual' do
    let(:representative_id) { '456' }

    before do
      allow(VaNotify::Service).to receive(:new).with(anything).and_return(vanotify_service)
    end

    shared_examples 'sends a declined individual/representative notification' do
      it 'sends a declined individual/representative notification' do
        expect(vanotify_service).to receive(:send_email)
          .with({
                  recipient_identifier: {
                    id_type: 'PID',
                    id_value: ptcpnt_id
                  },
                  personalisation: {
                    first_name:,
                    representative_type: 'claims agent',
                    representative_type_abbreviated: 'claims agent',
                    form_type: 'Appointment of Individual as Claimantʼs Representative (VA Form 21-22a)'
                  },
                  template_id: Settings.claims_api.vanotify.declined_service_organization_template_id
                })

        subject.perform(encrypted_ptcpnt_id, encrypted_first_name, representative_id)
      end
    end

    context 'when the claims accreditation tables flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(ClaimsApi::AccreditationTables::FLAG).and_return(false)
        create(:veteran_representative, representative_id:, user_types: ['claim_agents'])
      end

      include_examples 'sends a declined individual/representative notification'
    end

    context 'when the claims accreditation tables flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(ClaimsApi::AccreditationTables::FLAG).and_return(true)
        create(:claims_api_representative, representative_id:, user_types: ['claim_agents'])
      end

      include_examples 'sends a declined individual/representative notification'
    end
  end

  describe '#vanotify_service' do
    context 'when claims_api_vanotify_service_migration is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(true)
      end

      it 'initializes VaNotify::Service with the new settings path' do
        expect(VaNotify::Service).to receive(:new)
          .with(Settings.vanotify.services.lighthouse_benefits_claims.api_key)
        subject.send(:vanotify_service)
      end
    end

    context 'when claims_api_vanotify_service_migration is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(false)
      end

      it 'initializes VaNotify::Service with the legacy settings path' do
        expect(VaNotify::Service).to receive(:new)
          .with(Settings.claims_api.vanotify.services.lighthouse.api_key)
        subject.send(:vanotify_service)
      end
    end
  end

  describe 'template_id selection' do
    let(:vanotify_service) { instance_double(VaNotify::Service) }

    before do
      allow(VaNotify::Service).to receive(:new).with(anything).and_return(vanotify_service)
      allow(vanotify_service).to receive(:send_email).and_return(nil)
    end

    context 'when claims_api_vanotify_service_migration is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(true)
      end

      it 'uses the new template_id for organization declined email' do
        expect(vanotify_service).to receive(:send_email).with(
          hash_including(
            template_id: Settings.vanotify.services.lighthouse_benefits_claims.template_id.declined_service_organization
          )
        )
        subject.send(:send_organization_notification, ptcpnt_id:, first_name:)
      end

      it 'uses the new template_id for representative declined email' do
        expect(vanotify_service).to receive(:send_email).with(
          hash_including(
            template_id: Settings.vanotify.services.lighthouse_benefits_claims.template_id.declined_representative
          )
        )
        subject.send(:send_representative_notification, ptcpnt_id:, first_name:, representative_type: 'attorney')
      end
    end

    context 'when claims_api_vanotify_service_migration is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(false)
      end

      it 'uses the legacy template_id for organization declined email' do
        expect(vanotify_service).to receive(:send_email).with(
          hash_including(
            template_id: Settings.claims_api.vanotify.declined_service_organization_template_id
          )
        )
        subject.send(:send_organization_notification, ptcpnt_id:, first_name:)
      end

      it 'uses the legacy template_id for representative declined email' do
        expect(vanotify_service).to receive(:send_email).with(
          hash_including(
            template_id: Settings.claims_api.vanotify.declined_representative_template_id
          )
        )
        subject.send(:send_representative_notification, ptcpnt_id:, first_name:, representative_type: 'attorney')
      end
    end
  end
end
