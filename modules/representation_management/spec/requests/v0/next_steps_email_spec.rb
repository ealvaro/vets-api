# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NextStepsEmailController', type: :request do
  describe 'POST #create' do
    let(:base_path) { '/representation_management/v0/next_steps_email' }
    let(:accredited_individual) do
      create(:accredited_individual, individual_type: 'attorney', first_name: 'Bob', last_name: 'Law',
                                     address_line1: '123 Fake St', address_line2: 'Bldg 2', address_line3: 'Suite 3',
                                     city: 'Portland', state_code: 'OR', zip_code: '97214', country_code_iso3: 'USA')
    end
    let(:params) do
      {
        next_steps_email: {
          email_address: 'email@example.com',
          first_name: 'First',
          form_name: 'Form Name',
          form_number: '21-22',
          entity_type: 'individual',
          entity_id: accredited_individual.registration_number
        }
      }
    end

    context 'When submitting all fields with valid data' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_next_steps_email).and_return(false)
      end

      it 'responds with a ok status' do
        post(base_path, params:)
        expect(response).to have_http_status(:ok)
      end

      it 'responds with the expected body' do
        post(base_path, params:)
        expect(response.body).to eq({ message: 'Email enqueued' }.to_json)
      end

      it 'enqueues the email' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)

        post(base_path, params:)

        expect(VANotify::EmailJob).to have_received(:perform_async).with(
          params[:next_steps_email][:email_address],
          'appoint_a_representative_confirmation_email_template_id', # This is the actual value from the settings file
          {
            # The first_name is the only key here that has an underscore.
            # That is intentional.  All the keys here match the keys in the
            # template.
            'first_name' => 'First',
            'form name' => 'Form Name',
            'form number' => '21-22',
            'representative type' => 'attorney',
            'representative name' => 'Bob Law',
            'representative address' => '123 Fake St Bldg 2 Suite 3 Portland, OR 97214 USA'
          },
          'fake_secret',
          { callback_klass: 'AccreditedRepresentativePortal::EmailDeliveryStatusCallback',
            callback_metadata: {
              form_number: '21-22',
              statsd_tags: {
                service: 'representation-management',
                function: 'appoint_a_representative_confirmation_email'
              }
            } }
        )
      end

      context 'when va_notify_v2_next_steps_email is disabled' do
        before do
          allow(VANotify::EmailJob).to receive(:perform_async)
        end

        it 'sends email via V1 EmailJob' do
          post(base_path, params:)

          expect(VANotify::EmailJob).to have_received(:perform_async).with(
            params[:next_steps_email][:email_address],
            'appoint_a_representative_confirmation_email_template_id',
            {
              'first_name' => 'First',
              'form name' => 'Form Name',
              'form number' => '21-22',
              'representative type' => 'attorney',
              'representative name' => 'Bob Law',
              'representative address' => '123 Fake St Bldg 2 Suite 3 Portland, OR 97214 USA'
            },
            'fake_secret',
            { callback_klass: 'AccreditedRepresentativePortal::EmailDeliveryStatusCallback',
              callback_metadata: {
                form_number: '21-22',
                statsd_tags: {
                  service: 'representation-management',
                  function: 'appoint_a_representative_confirmation_email'
                }
              } }
          )
        end
      end

      context 'when va_notify_v2_next_steps_email is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_notify_v2_next_steps_email).and_return(true)
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
          allow(VANotify::EmailJob).to receive(:perform_async)
        end

        it 'sends email via V2 QueueEmailJob' do
          post(base_path, params:)

          expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
            params[:next_steps_email][:email_address],
            'appoint_a_representative_confirmation_email_template_id',
            {
              'first_name' => 'First',
              'form name' => 'Form Name',
              'form number' => '21-22',
              'representative type' => 'attorney',
              'representative name' => 'Bob Law',
              'representative address' => '123 Fake St Bldg 2 Suite 3 Portland, OR 97214 USA'
            },
            'Settings.vanotify.services.va_gov.api_key',
            { callback_klass: 'AccreditedRepresentativePortal::EmailDeliveryStatusCallback',
              callback_metadata: {
                form_number: '21-22',
                statsd_tags: {
                  service: 'representation-management',
                  function: 'appoint_a_representative_confirmation_email'
                }
              } }
          )
          expect(VANotify::EmailJob).not_to have_received(:perform_async)
        end
      end
    end

    context 'when triggering validation errors' do
      context 'when submitting without the single required attribute for a single validation error' do
        before do
          params[:next_steps_email][:email_address] = nil
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with a generic error body that does not leak field details' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end

      context 'when submitting without multiple required attributes' do
        before do
          params[:next_steps_email][:email_address] = nil
          params[:next_steps_email][:first_name] = nil
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with the same generic error body regardless of how many fields are invalid' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end

      context 'when submitting an invalid email format' do
        before do
          params[:next_steps_email][:email_address] = 'not-an-email'
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with a generic error body' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end

      context 'when submitting an invalid form_number' do
        before do
          params[:next_steps_email][:form_number] = 'not-a-valid-form'
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with a generic error body' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end

      context 'when submitting an invalid entity_type' do
        before do
          params[:next_steps_email][:entity_type] = 'bogus'
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with a generic error body' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end

      context 'when entity_id does not resolve to an existing entity' do
        before do
          params[:next_steps_email][:entity_id] = 0
          post(base_path, params:)
        end

        it 'responds with an unprocessable entity status' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'responds with the same generic error body as other failures — no oracle signal' do
          expect(response.body).to eq({ errors: ['Invalid request parameters'] }.to_json)
        end
      end
    end

    context "when the feature flag 'appoint_a_representative_enable_confirmation_email' is disabled" do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:appoint_a_representative_enable_confirmation_email).and_return(false)
      end

      it 'returns a 404' do
        post(base_path, params:)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
