# frozen_string_literal: true

require 'rails_helper'
require 'caseflow/responses/caseflow'

RSpec.describe Caseflow::Responses::Caseflow do
  let(:monitor) { instance_double(Logging::Monitor) }

  let(:valid_body) do
    {
      'data' => [
        {
          'id' => '123',
          'type' => 'appeal',
          'attributes' => {
            'appealIds' => ['123'],
            'updated' => '2024-01-01T00:00:00-04:00',
            'active' => true,
            'incompleteHistory' => false,
            'aoj' => 'vba',
            'programArea' => 'compensation',
            'description' => 'Test appeal',
            'location' => 'bva',
            'status' => { 'type' => 'on_docket', 'details' => {} },
            'issues' => [
              { 'active' => true, 'description' => 'Issue one', 'diagnosticCode' => '1234', 'date' => nil,
                'lastAction' => nil }
            ],
            'alerts' => [],
            'events' => []
          }
        }
      ]
    }
  end

  before do
    allow(Logging::Monitor).to receive(:new).with('appeals').and_return(monitor)
  end

  describe '#initialize' do
    context 'with a valid response body' do
      it 'sets the body and status' do
        response = described_class.new(valid_body, 200)

        expect(response.body).to eq(valid_body)
        expect(response.status).to eq(200)
      end
    end

    context 'with null issue descriptions' do
      let(:body_with_null_description) do
        body = valid_body.deep_dup
        body['data'][0]['attributes']['issues'][0]['description'] = nil
        body
      end

      it 'sets the body without raising an error' do
        response = described_class.new(body_with_null_description, 200)

        expect(response.body).to eq(body_with_null_description)
        expect(response.status).to eq(200)
      end
    end

    context 'with a schema validation failure' do
      let(:invalid_body) do
        { 'data' => 'not_an_array' }
      end

      it 'logs the validation error via monitor and still sets the body' do
        expect(monitor).to receive(:track_request).with(
          :warn,
          'Caseflow appeals response failed schema validation',
          'api.appeals.schema_validation_failure',
          call_location: an_instance_of(Thread::Backtrace::Location),
          validation_errors: an_instance_of(Array)
        )

        response = described_class.new(invalid_body, 200)

        expect(response.body).to eq(invalid_body)
        expect(response.status).to eq(200)
      end

      it 'increments the StatsD metric' do
        allow(monitor).to receive(:track_request)

        expect { described_class.new(invalid_body, 200) }
          .not_to raise_error
      end
    end

    context 'with a completely valid body' do
      it 'does not log any validation warnings' do
        expect(monitor).not_to receive(:track_request)

        described_class.new(valid_body, 200)
      end
    end
  end
end
