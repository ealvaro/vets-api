# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::EventBusGatewayController, type: :controller do
  let(:participant_id) { '1234567890' }
  let(:template_id) { 'template_123' }
  let(:email_template_id) { 'email_template_456' }
  let(:push_template_id) { 'push_template_789' }
  let(:sms_template_id) { 'sms_template_101' }

  let(:service_account_access_token) do
    instance_double(
      SignIn::ServiceAccountAccessToken,
      user_attributes: { 'participant_id' => participant_id }
    )
  end

  before do
    controller.instance_variable_set(:@service_account_access_token, service_account_access_token)
    allow(controller).to receive(:authenticate_service_account).and_return(true)
  end

  describe 'POST #send_email' do
    let(:params) { { template_id: } }

    it 'enqueues LetterReadyEmailJob with correct parameters' do
      expect(EventBusGateway::LetterReadyEmailJob)
        .to receive(:perform_async)
        .with(participant_id, template_id)

      post :send_email, params:
    end

    it 'returns 200 OK status' do
      allow(EventBusGateway::LetterReadyEmailJob).to receive(:perform_async)

      post(:send_email, params:)

      expect(response).to have_http_status(:ok)
    end

    it 'returns no content in response body' do
      allow(EventBusGateway::LetterReadyEmailJob).to receive(:perform_async)

      post(:send_email, params:)

      expect(response.body).to be_empty
    end

    context 'with missing template_id' do
      let(:params) { {} }

      it 'returns 400 Bad Request' do
        post(:send_email, params:)
        expect(response).to have_http_status(:bad_request)
      end

      it 'does not enqueue the job' do
        expect(EventBusGateway::LetterReadyEmailJob).not_to receive(:perform_async)
        post(:send_email, params:)
      end
    end

    context 'with additional unpermitted parameters' do
      let(:params) { { template_id:, extra_param: 'should_be_filtered' } }

      it 'filters out unpermitted parameters' do
        expect(EventBusGateway::LetterReadyEmailJob)
          .to receive(:perform_async)
          .with(participant_id, template_id)

        post :send_email, params:
      end
    end
  end

  describe 'POST #send_push' do
    let(:params) { { template_id: } }

    it 'enqueues LetterReadyPushJob with correct parameters' do
      expect(EventBusGateway::LetterReadyPushJob)
        .to receive(:perform_async)
        .with(participant_id, template_id)

      post :send_push, params:
    end

    it 'returns 200 OK status' do
      allow(EventBusGateway::LetterReadyPushJob).to receive(:perform_async)

      post(:send_push, params:)

      expect(response).to have_http_status(:ok)
    end

    it 'returns no content in response body' do
      allow(EventBusGateway::LetterReadyPushJob).to receive(:perform_async)

      post(:send_push, params:)

      expect(response.body).to be_empty
    end

    context 'with missing template_id' do
      let(:params) { {} }

      it 'returns 400 Bad Request' do
        post(:send_push, params:)
        expect(response).to have_http_status(:bad_request)
      end

      it 'does not enqueue the job' do
        expect(EventBusGateway::LetterReadyPushJob).not_to receive(:perform_async)
        post(:send_push, params:)
      end
    end

    context 'with additional unpermitted parameters' do
      let(:params) { { template_id:, malicious_param: 'filtered' } }

      it 'filters out unpermitted parameters' do
        expect(EventBusGateway::LetterReadyPushJob)
          .to receive(:perform_async)
          .with(participant_id, template_id)

        post :send_push, params:
      end
    end
  end

  describe 'POST #send_sms' do
    let(:params) { { template_id: } }

    it 'enqueues LetterReadySmsJob with correct parameters' do
      expect(EventBusGateway::LetterReadySmsJob)
        .to receive(:perform_async)
        .with(participant_id, template_id)

      post :send_sms, params:
    end

    it 'returns 200 OK status' do
      allow(EventBusGateway::LetterReadySmsJob).to receive(:perform_async)

      post(:send_sms, params:)

      expect(response).to have_http_status(:ok)
    end

    it 'returns no content in response body' do
      allow(EventBusGateway::LetterReadySmsJob).to receive(:perform_async)

      post(:send_sms, params:)

      expect(response.body).to be_empty
    end

    context 'with missing template_id' do
      let(:params) { {} }

      it 'returns 400 Bad Request' do
        post(:send_sms, params:)
        expect(response).to have_http_status(:bad_request)
      end

      it 'does not enqueue the job' do
        expect(EventBusGateway::LetterReadySmsJob).not_to receive(:perform_async)
        post(:send_sms, params:)
      end
    end

    context 'with additional unpermitted parameters' do
      let(:params) { { template_id:, extra_param: 'should_be_filtered' } }

      it 'filters out unpermitted parameters' do
        expect(EventBusGateway::LetterReadySmsJob)
          .to receive(:perform_async)
          .with(participant_id, template_id)

        post :send_sms, params:
      end
    end
  end

  describe 'POST #send_notifications' do
    context 'with both email and push template IDs' do
      let(:params) do
        {
          email_template_id:,
          push_template_id:
        }
      end

      it 'enqueues LetterReadyNotificationJob with correct parameters' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => email_template_id, 'push' => push_template_id, 'sms' => nil })

        post :send_notifications, params:
      end

      it 'returns 200 OK status' do
        allow(EventBusGateway::LetterReadyNotificationJob).to receive(:perform_async)

        post(:send_notifications, params:)

        expect(response).to have_http_status(:ok)
      end

      it 'returns no content in response body' do
        allow(EventBusGateway::LetterReadyNotificationJob).to receive(:perform_async)

        post(:send_notifications, params:)

        expect(response.body).to be_empty
      end
    end

    context 'with only email_template_id' do
      let(:params) { { email_template_id: } }

      it 'enqueues job with nil push_template_id' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => email_template_id, 'push' => nil, 'sms' => nil })

        post :send_notifications, params:
      end
    end

    context 'with only push_template_id' do
      let(:params) { { push_template_id: } }

      it 'enqueues job with nil email_template_id' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => nil, 'push' => push_template_id, 'sms' => nil })

        post :send_notifications, params:
      end
    end

    context 'with only sms_template_id' do
      let(:params) { { sms_template_id: } }

      it 'enqueues job with nil email and push template IDs' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => nil, 'push' => nil, 'sms' => sms_template_id })

        post :send_notifications, params:
      end
    end

    context 'with no template IDs' do
      let(:params) { {} }

      it 'returns 400 Bad Request' do
        post(:send_notifications, params:)
        expect(response).to have_http_status(:bad_request)
      end

      it 'returns error message about missing templates' do
        post(:send_notifications, params:)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['detail'])
          .to include('At least one of email_template_id, push_template_id, or sms_template_id is required')
      end

      it 'does not enqueue the job' do
        expect(EventBusGateway::LetterReadyNotificationJob).not_to receive(:perform_async)
        post(:send_notifications, params:)
      end
    end

    context 'with additional unpermitted parameters' do
      let(:params) do
        {
          email_template_id:,
          push_template_id:,
          unauthorized_param: 'should_not_pass'
        }
      end

      it 'filters out unpermitted parameters' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => email_template_id, 'push' => push_template_id, 'sms' => nil })

        post :send_notifications, params:
      end
    end
  end

  describe '#participant_id' do
    it 'extracts participant_id from service account access token' do
      expect(controller.send(:participant_id)).to eq(participant_id)
    end

    it 'memoizes the participant_id' do
      expect(service_account_access_token).to receive(:user_attributes).once.and_return(
        { 'participant_id' => participant_id }
      )

      controller.send(:participant_id)
      controller.send(:participant_id)
    end

    context 'when participant_id is not in token attributes' do
      let(:service_account_access_token) do
        instance_double(
          SignIn::ServiceAccountAccessToken,
          user_attributes: {}
        )
      end

      before do
        controller.instance_variable_set(:@service_account_access_token, service_account_access_token)
      end

      it 'returns nil' do
        expect(controller.send(:participant_id)).to be_nil
      end
    end
  end

  describe 'authentication' do
    context 'when service account authentication fails' do
      before do
        allow(controller).to receive(:authenticate_service_account) do
          controller.render json: { errors: 'Unauthorized' }, status: :unauthorized
          false
        end
      end

      it 'does not enqueue email job' do
        expect(EventBusGateway::LetterReadyEmailJob).not_to receive(:perform_async)

        post :send_email, params: { template_id: }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not enqueue push job' do
        expect(EventBusGateway::LetterReadyPushJob).not_to receive(:perform_async)

        post :send_push, params: { template_id: }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not enqueue sms job' do
        expect(EventBusGateway::LetterReadySmsJob).not_to receive(:perform_async)

        post :send_sms, params: { template_id: }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not enqueue notification job' do
        expect(EventBusGateway::LetterReadyNotificationJob).not_to receive(:perform_async)

        post :send_notifications, params: {
          email_template_id:,
          push_template_id:
        }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'service tagging' do
    it 'has the correct service tag' do
      expect(described_class.trace_service_tag).to eq('event_bus_gateway')
    end
  end

  describe '.deployment_environment' do
    context 'when Settings.vsp_environment is set' do
      before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

      it 'returns the vsp_environment value' do
        expect(described_class.deployment_environment).to eq('staging')
      end
    end

    context 'when Settings.vsp_environment is nil' do
      before { allow(Settings).to receive(:vsp_environment).and_return(nil) }

      it 'returns Rails.env' do
        expect(described_class.deployment_environment).to eq(Rails.env.to_s)
      end
    end

    context 'when environment is not in valid list' do
      before { allow(Settings).to receive(:vsp_environment).and_return('sandbox') }

      it 'returns blank' do
        expect(described_class.deployment_environment).to eq('blank')
      end
    end

    context 'when environment is in valid list' do
      %w[development test staging production].each do |env|
        it "returns #{env} when environment is #{env}" do
          allow(Settings).to receive(:vsp_environment).and_return(env)
          expect(described_class.deployment_environment).to eq(env)
        end
      end
    end

    it 'only allows five specific environments' do
      # Test valid environments return themselves
      %w[development test staging production].each do |env|
        allow(Settings).to receive(:vsp_environment).and_return(env)
        expect(described_class.deployment_environment).to eq(env)
      end

      # Test invalid environments return blank
      %w[sandbox local custom invalid].each do |env|
        allow(Settings).to receive(:vsp_environment).and_return(env)
        expect(described_class.deployment_environment).to eq('blank')
      end
    end
  end

  describe 'TEMPLATES constant' do
    it 'loads from YAML file' do
      expect(described_class::TEMPLATES).to be_a(Hash)
    end

    it 'is frozen' do
      expect(described_class::TEMPLATES).to be_frozen
    end

    it 'contains email template configuration' do
      expect(described_class::TEMPLATES['email']).to be_a(Hash)
    end

    it 'loads configuration for current deployment environment' do
      current_env = described_class.deployment_environment
      yaml_config = YAML.safe_load_file(
        Rails.root.join('config', 'event_bus_gateway', 'templates.yml')
      )

      expect(described_class::TEMPLATES).to eq(yaml_config[current_env])
    end

    context 'all five deployment environments are in YAML' do
      let(:yaml_config) do
        YAML.safe_load_file(Rails.root.join('config', 'event_bus_gateway', 'templates.yml'))
      end

      %w[development test staging production blank].each do |env|
        it "has configuration for #{env} environment" do
          expect(yaml_config).to have_key(env)
          expect(yaml_config[env]).to be_a(Hash)
          expect(yaml_config[env]).to have_key('email')
        end

        it "#{env} environment has required email template keys" do
          email_config = yaml_config[env]['email']
          expect(email_config).to have_key('default_template')
          expect(email_config).to have_key('mobile_link_template')
          expect(email_config).to have_key('pension_claims_template')
          expect(email_config).to have_key('pension_mobile_link_template')
        end
      end
    end

    context 'template structure validation' do
      it 'has all required email template keys' do
        email_templates = described_class::TEMPLATES['email']
        expect(email_templates).to have_key('default_template')
        expect(email_templates).to have_key('mobile_link_template')
        expect(email_templates).to have_key('pension_claims_template')
        expect(email_templates).to have_key('pension_mobile_link_template')
      end

      it 'template values are strings or nil' do
        email_templates = described_class::TEMPLATES['email']
        email_templates.each_value do |template_value|
          expect(template_value).to be_a(String).or be_nil
        end
      end
    end

    context 'when templates.yml file is missing' do
      it 'gracefully returns empty hash instead of crashing' do
        stub_const('V0::EventBusGatewayController::TEMPLATES', {})
        expect(described_class::TEMPLATES).to eq({})
      end

      it 'results in invalid templates (missing_required_templates returns all required)' do
        stub_const('V0::EventBusGatewayController::TEMPLATES', {})
        missing = described_class.missing_required_templates
        expect(missing).to match_array(described_class::REQUIRED_EMAIL_TEMPLATES)
      end

      it 'causes validate_templates to return false' do
        stub_const('V0::EventBusGatewayController::TEMPLATES', {})
        # When TEMPLATES is empty, missing_required_templates returns all required templates
        # which is not empty, so validate_templates returns false
        expect(described_class.validate_templates).to be false
      end

      it 'logs warning when YAML.safe_load_file raises Errno::ENOENT' do
        # Mock YAML.safe_load_file to raise file not found error
        allow(YAML).to receive(:safe_load_file).and_raise(
          Errno::ENOENT.new('No such file or directory')
        )

        expect(Rails.logger).to receive(:warn).with(
          match(/EventBusGatewayController: Failed to load templates.yml:.*No such file/)
        )

        # Call the load_templates method which handles the error
        test_templates = described_class.load_templates

        expect(test_templates).to eq({})
      end

      it 'logs warning when YAML.safe_load_file raises Psych::BadAlias' do
        # Mock YAML.safe_load_file to raise YAML parsing error
        allow(YAML).to receive(:safe_load_file).and_raise(
          Psych::BadAlias.new('Unknown alias: missing_key')
        )

        expect(Rails.logger).to receive(:warn).with(
          match(/EventBusGatewayController: Failed to load templates.yml:.*Unknown alias/)
        )

        # Call the load_templates method which handles the error
        test_templates = described_class.load_templates

        expect(test_templates).to eq({})
      end

      it 'verifies that Errno::ENOENT is actually raised for non-existent files' do
        non_existent_path = Rails.root.join('config', 'event_bus_gateway', 'non_existent_file_xyz.yml')

        expect do
          YAML.safe_load_file(non_existent_path)
        end.to raise_error(Errno::ENOENT)
      end

      it 'verifies that Psych::BadAlias is actually raised for invalid YAML aliases' do
        # Create a temporary YAML file with a bad alias
        temp_yaml_path = Rails.root.join('tmp', 'bad_alias_test.yml')
        bad_yaml_content = "default: &anchor\n  key: value\nbad_reference: *undefined_anchor"

        File.write(temp_yaml_path, bad_yaml_content)

        begin
          expect do
            YAML.safe_load_file(temp_yaml_path)
          end.to raise_error(Psych::BadAlias)
        ensure
          FileUtils.rm_f(temp_yaml_path)
        end
      end
    end
  end

  describe 'REQUIRED_EMAIL_TEMPLATES constant' do
    it 'contains exactly 4 required template keys' do
      expect(described_class::REQUIRED_EMAIL_TEMPLATES).to contain_exactly(
        'default_template',
        'mobile_link_template',
        'pension_claims_template',
        'pension_mobile_link_template'
      )
    end

    it 'is frozen' do
      expect(described_class::REQUIRED_EMAIL_TEMPLATES).to be_frozen
    end
  end

  describe 'TEMPLATES_VALID constant' do
    it 'is a boolean value' do
      expect(described_class::TEMPLATES_VALID).to satisfy { |v| [true, false].include?(v) }
    end

    it 'is frozen' do
      expect(described_class::TEMPLATES_VALID).to be_frozen
    end

    it 'reflects the result of validate_templates' do
      # In test environment, templates should be valid
      expect(described_class::TEMPLATES_VALID).to eq(described_class.validate_templates)
    end

    context 'in test environment' do
      it 'is true when all required templates are present' do
        # Test environment should have all templates configured
        expect(described_class::TEMPLATES_VALID).to be true
      end
    end
  end

  describe '.missing_required_templates' do
    let(:templates_config) do
      {
        'email' => {
          'default_template' => 'template1',
          'mobile_link_template' => 'template2',
          'pension_claims_template' => 'template3',
          'pension_mobile_link_template' => 'template4'
        }
      }
    end

    before do
      stub_const('V0::EventBusGatewayController::TEMPLATES', templates_config)
    end

    context 'when all required templates are present' do
      it 'returns an empty array' do
        expect(described_class.missing_required_templates).to eq([])
      end
    end

    context 'when email templates are nil' do
      let(:templates_config) { {} }

      it 'returns all required templates' do
        expect(described_class.missing_required_templates).to match_array(
          described_class::REQUIRED_EMAIL_TEMPLATES
        )
      end
    end

    context 'when some templates are blank' do
      let(:templates_config) do
        {
          'email' => {
            'default_template' => 'template1',
            'mobile_link_template' => '',
            'pension_claims_template' => 'template3',
            'pension_mobile_link_template' => nil
          }
        }
      end

      it 'returns only the missing templates' do
        expect(described_class.missing_required_templates).to match_array(
          %w[mobile_link_template pension_mobile_link_template]
        )
      end
    end

    context 'when all templates are blank' do
      let(:templates_config) do
        {
          'email' => {
            'default_template' => '',
            'mobile_link_template' => '',
            'pension_claims_template' => '',
            'pension_mobile_link_template' => ''
          }
        }
      end

      it 'returns all required templates' do
        expect(described_class.missing_required_templates).to match_array(
          described_class::REQUIRED_EMAIL_TEMPLATES
        )
      end
    end
  end

  describe '.validate_templates' do
    context 'when no templates are missing' do
      before do
        allow(described_class).to receive(:missing_required_templates).and_return([])
      end

      it 'returns true' do
        expect(described_class.validate_templates).to be true
      end
    end

    context 'when templates are missing' do
      before do
        allow(described_class).to receive(:missing_required_templates).and_return(['mobile_link_template'])
      end

      it 'returns false' do
        expect(described_class.validate_templates).to be false
      end
    end
  end

  describe '#select_email_template' do
    let(:original_template) { 'test_template123' }
    let(:mobile_link_template) { 'test_mobile_link_template123' }
    let(:pension_mobile_link_template) { 'test_pension_mobile_link_template123' }

    before do
      # Default: templates are valid and universal link is enabled
      stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
        .and_return(true)
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_controller_visibility)
        .and_return(false)
    end

    context 'when original_template is blank' do
      let(:original_template) { nil }

      it 'returns the blank value without swapping' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to be_nil
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank template message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: original_template is blank')

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when TEMPLATES_VALID is false' do
      before do
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', false)
        allow(described_class).to receive(:missing_required_templates).and_return(['mobile_link_template'])
      end

      it 'returns the original template without swapping' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(original_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_validation_visibility)
            .and_return(true)
        end

        it 'logs invalid templates message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: templates are invalid')
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController: missing required templates',
              { missing_templates: ['mobile_link_template'] }
            )

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when universal_link feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(false)
      end

      it 'returns the original template without swapping' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(original_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs universal link disabled message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: universal_link feature flag is disabled')

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when participant_id is blank' do
      let(:original_template) { 'test_template123' }

      before do
        allow(controller).to receive(:participant_id).and_return(nil)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'returns the original template without swapping' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(original_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank participant_id message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated')
            .ordered
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: universal_link feature flag is disabled')
            .ordered

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when template matches default_template' do
      let(:original_template) { 'test_template123' }

      it 'swaps to mobile_link_template' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(mobile_link_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs default template matched and swap messages' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: matched default email template')
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController using universal link template',
              { swapped_template: mobile_link_template }
            )

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when template matches pension_claims_template' do
      let(:original_template) { 'test_pension_template123' }

      it 'swaps to pension_mobile_link_template' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(pension_mobile_link_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs pension template matched and swap messages' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: matched pension email template')
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController using pension mobile link template',
              { swapped_template: pension_mobile_link_template }
            )

          controller.send(:select_email_template, original_template)
        end
      end
    end

    context 'when template does not match any case' do
      let(:original_template) { 'some_other_template' }

      it 'returns the original template' do
        result = controller.send(:select_email_template, original_template)
        expect(result).to eq(original_template)
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs no template matched message' do
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController: no template case matched',
              { template_id: original_template }
            )

          controller.send(:select_email_template, original_template)
        end
      end
    end
  end

  describe '#match_and_swap_template' do
    let(:default_template) { 'test_template123' }
    let(:pension_template) { 'test_pension_template123' }
    let(:mobile_link_template) { 'test_mobile_link_template123' }
    let(:pension_mobile_link_template) { 'test_pension_mobile_link_template123' }

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_controller_visibility)
        .and_return(false)
    end

    context 'when template matches default_template' do
      it 'returns mobile_link_template' do
        result = controller.send(:match_and_swap_template, default_template)
        expect(result).to eq(mobile_link_template)
      end
    end

    context 'when template matches pension_claims_template' do
      it 'returns pension_mobile_link_template' do
        result = controller.send(:match_and_swap_template, pension_template)
        expect(result).to eq(pension_mobile_link_template)
      end
    end

    context 'when template does not match any case' do
      let(:other_template) { 'unmatched_template' }

      it 'returns the original template' do
        result = controller.send(:match_and_swap_template, other_template)
        expect(result).to eq(other_template)
      end
    end
  end

  describe '#swap_to_mobile_template' do
    let(:mobile_link_template) { 'test_mobile_link_template123' }

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_controller_visibility)
        .and_return(false)
    end

    it 'returns the swapped template id' do
      result = controller.send(:swap_to_mobile_template, 'mobile_link_template', 'universal link')
      expect(result).to eq(mobile_link_template)
    end

    context 'with logging visibility enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(true)
      end

      it 'logs template swap information' do
        expect(Rails.logger).to receive(:info)
          .with(
            'EventBusGatewayController using universal link template',
            { swapped_template: mobile_link_template }
          )

        controller.send(:swap_to_mobile_template, 'mobile_link_template', 'universal link')
      end
    end
  end

  describe '#universal_link_enabled?' do
    it 'checks Flipper with correct feature flag and participant actor' do
      actor_matcher = satisfy do |actor|
        actor.is_a?(Flipper::Actor) && actor.flipper_id == participant_id
      end

      expect(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_letter_ready_email_universal_link, actor_matcher)
        .and_return(true)

      result = controller.send(:universal_link_enabled?)
      expect(result).to be true
    end

    context 'when feature is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(false)
      end

      it 'returns false' do
        result = controller.send(:universal_link_enabled?)
        expect(result).to be false
      end
    end

    context 'when participant_id is blank' do
      before do
        allow(controller).to receive(:participant_id).and_return(nil)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'returns false without checking Flipper' do
        expect(Flipper).not_to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)

        result = controller.send(:universal_link_enabled?)
        expect(result).to be false
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank participant_id message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated')

          controller.send(:universal_link_enabled?)
        end
      end

      context 'with logging visibility disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:universal_link_enabled?)
        end
      end
    end
  end

  describe 'logging methods' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_controller_visibility)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:event_bus_gateway_controller_validation_visibility)
        .and_return(false)
    end

    describe '#log_blank_template' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_blank_template)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank template message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: original_template is blank')

          controller.send(:log_blank_template)
        end
      end
    end

    describe '#log_universal_link_disabled' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_universal_link_disabled)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs universal link disabled message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: universal_link feature flag is disabled')

          controller.send(:log_universal_link_disabled)
        end
      end
    end

    describe '#log_blank_participant_id' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_blank_participant_id)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank participant_id message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated')

          controller.send(:log_blank_participant_id)
        end
      end
    end

    describe '#log_invalid_templates' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_invalid_templates)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs invalid templates message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: templates are invalid')

          controller.send(:log_invalid_templates)
        end
      end
    end

    describe '#log_default_template_matched' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_default_template_matched)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs default template matched message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: matched default email template')

          controller.send(:log_default_template_matched)
        end
      end
    end

    describe '#log_pension_template_matched' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_pension_template_matched)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs pension template matched message' do
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: matched pension email template')

          controller.send(:log_pension_template_matched)
        end
      end
    end

    describe '#log_no_template_matched' do
      let(:template_id) { 'some_template' }

      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_no_template_matched, template_id)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs no template matched message with template_id' do
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController: no template case matched',
              { template_id: }
            )

          controller.send(:log_no_template_matched, template_id)
        end
      end
    end

    describe '#log_template_swap' do
      let(:description) { 'universal link' }
      let(:swapped_template) { 'test_mobile_link_template123' }

      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_template_swap, description, swapped_template)
        end
      end

      context 'when visibility flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs template swap with description and swapped template' do
          expect(Rails.logger).to receive(:info)
            .with(
              "EventBusGatewayController using #{description} template",
              { swapped_template: }
            )

          controller.send(:log_template_swap, description, swapped_template)
        end
      end
    end

    describe '#log_required_templates' do
      context 'when visibility flag is disabled' do
        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_required_templates)
        end
      end

      context 'when validation visibility flag is enabled and templates are missing' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_validation_visibility)
            .and_return(true)
          allow(described_class).to receive(:missing_required_templates)
            .and_return(%w[mobile_link_template pension_mobile_link_template])
        end

        it 'logs missing required templates' do
          expect(Rails.logger).to receive(:info)
            .with(
              'EventBusGatewayController: missing required templates',
              { missing_templates: %w[mobile_link_template pension_mobile_link_template] }
            )

          controller.send(:log_required_templates)
        end
      end

      context 'when validation visibility flag is enabled but no templates are missing' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_validation_visibility)
            .and_return(true)
          allow(described_class).to receive(:missing_required_templates).and_return([])
        end

        it 'does not log' do
          expect(Rails.logger).not_to receive(:info)
          controller.send(:log_required_templates)
        end
      end
    end
  end

  describe 'integration with send_email' do
    let(:original_template) { 'test_template123' }
    let(:swapped_template) { 'test_mobile_link_template123' }
    let(:params) { { template_id: original_template } }

    context 'when universal link is enabled and template matches' do
      before do
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'enqueues job with swapped template' do
        expect(EventBusGateway::LetterReadyEmailJob)
          .to receive(:perform_async)
          .with(participant_id, swapped_template)

        post :send_email, params:
      end
    end

    context 'when universal link is disabled' do
      before do
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(false)
      end

      it 'enqueues job with original template' do
        expect(EventBusGateway::LetterReadyEmailJob)
          .to receive(:perform_async)
          .with(participant_id, original_template)

        post :send_email, params:
      end
    end

    context 'when participant_id is blank' do
      let(:service_account_access_token) do
        instance_double(
          SignIn::ServiceAccountAccessToken,
          user_attributes: {}
        )
      end

      before do
        controller.instance_variable_set(:@service_account_access_token, service_account_access_token)
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'enqueues job with original template without swapping' do
        expect(EventBusGateway::LetterReadyEmailJob)
          .to receive(:perform_async)
          .with(nil, original_template)

        post :send_email, params:
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank participant_id message' do
          allow(EventBusGateway::LetterReadyEmailJob).to receive(:perform_async)

          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated')
            .ordered
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: universal_link feature flag is disabled')
            .ordered

          post :send_email, params:
        end
      end
    end
  end

  describe 'integration with send_notifications' do
    let(:email_template) { 'test_template123' }
    let(:swapped_template) { 'test_mobile_link_template123' }
    let(:push_template) { 'push_123' }
    let(:params) do
      {
        email_template_id: email_template,
        push_template_id: push_template
      }
    end

    context 'when universal link is enabled and email template matches' do
      before do
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'enqueues job with swapped email template and original push template' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => swapped_template, 'push' => push_template, 'sms' => nil })

        post :send_notifications, params:
      end
    end

    context 'when universal link is disabled' do
      before do
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_letter_ready_email_universal_link, anything)
          .and_return(false)
      end

      it 'enqueues job with original templates' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(participant_id, { 'email' => email_template, 'push' => push_template, 'sms' => nil })

        post :send_notifications, params:
      end
    end

    context 'when participant_id is blank' do
      let(:service_account_access_token) do
        instance_double(
          SignIn::ServiceAccountAccessToken,
          user_attributes: {}
        )
      end

      before do
        controller.instance_variable_set(:@service_account_access_token, service_account_access_token)
        stub_const('V0::EventBusGatewayController::TEMPLATES_VALID', true)
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_controller_visibility)
          .and_return(false)
      end

      it 'enqueues job with original email template without swapping' do
        expect(EventBusGateway::LetterReadyNotificationJob)
          .to receive(:perform_async)
          .with(nil, { 'email' => email_template, 'push' => push_template, 'sms' => nil })

        post :send_notifications, params:
      end

      context 'with logging visibility enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:event_bus_gateway_controller_visibility)
            .and_return(true)
        end

        it 'logs blank participant_id message' do
          allow(EventBusGateway::LetterReadyNotificationJob).to receive(:perform_async)

          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated')
            .ordered
          expect(Rails.logger).to receive(:info)
            .with('EventBusGatewayController: universal_link feature flag is disabled')
            .ordered

          post :send_notifications, params:
        end
      end
    end
  end
end
