# frozen_string_literal: true

require 'rails_helper'
require 'caseflow/service'

RSpec.describe Caseflow::Service do
  subject { described_class.new }

  let(:user) { build(:user, :loa3, ssn: '796127160') }
  let(:appeal_with_null_issue_description) do
    {
      'id' => 'HLR7970',
      'type' => 'higherLevelReview',
      'attributes' => {
        'appealIds' => ['HLR7970'],
        'updated' => '2025-08-20T12:51:51-04:00',
        'incompleteHistory' => false,
        'active' => true,
        'description' => 'Service connection for Tinnitus is granted with an evaluation of ' \
                         '10 percent effective August 1, 2012. and 3 others',
        'location' => 'aoj',
        'aoj' => 'vba',
        'programArea' => 'compensation',
        'status' => { 'type' => 'hlr_received', 'details' => {} },
        'alerts' => [],
        'issues' => [
          {
            'active' => true,
            'lastAction' => nil,
            'date' => nil,
            'description' => nil,
            'diagnosticCode' => nil
          },
          {
            'active' => true,
            'lastAction' => nil,
            'date' => nil,
            'description' => 'Service connection for Tinnitus is granted with an evaluation of ' \
                             '10 percent effective August 1, 2012.',
            'diagnosticCode' => '6260'
          }
        ],
        'events' => [{ 'type' => 'hlr_request', 'date' => '2024-10-04' }],
        'evidence' => []
      }
    }
  end
  let(:expected_appeals_log_data) do
    [appeal_with_null_issue_description]
  end

  describe '#get_appeals' do
    context 'when Caseflow returns a 404' do
      let(:user) { build(:user, :loa3, ssn: '120495723') }
      let(:original_body) do
        {
          'errors' => [{
            'status' => '404',
            'title' => 'Veteran not found',
            'detail' => 'A veteran with that SSN was not found in our systems.'
          }]
        }
      end

      it 'remaps an unmapped 404 BackendServiceException to CASEFLOWSTATUS404' do
        response_values = {
          status: 404,
          detail: 'Veteran not found',
          code: 'VA900',
          source: original_body.dig('errors', 0, 'detail')
        }
        unmapped_error = Common::Exceptions::BackendServiceException.new(
          'VA900',
          response_values,
          404,
          original_body
        )
        unmapped_error.set_backtrace(%w[caseflow/service.rb:1 caseflow/service.rb:2])
        allow_any_instance_of(described_class).to receive(:perform).and_raise(unmapped_error)

        expect { subject.get_appeals(user) }
          .to raise_error(Common::Exceptions::BackendServiceException) do |error|
            expect(error.key).to eq('CASEFLOWSTATUS404')
            expect(error.errors.first[:code]).to eq('CASEFLOWSTATUS404')
            expect(error.errors.first[:status].to_i).to eq(404)
            expect(error.original_status).to eq(404)
            expect(error.backtrace).to eq(unmapped_error.backtrace)
          end
      end

      it 'raises CASEFLOWSTATUS404 when the not_found cassette is used',
         run_at: 'Wed, 08 Jan 2018 14:44:00 GMT' do
        VCR.use_cassette('caseflow/not_found', { match_requests_on: %i[method uri] }) do
          expect { subject.get_appeals(user) }
            .to raise_error(Common::Exceptions::BackendServiceException) do |error|
              expect(error.key).to eq('CASEFLOWSTATUS404')
              expect(error.errors.first[:code]).to eq('CASEFLOWSTATUS404')
              expect(error.errors.first[:status].to_i).to eq(404)
            end
        end
      end
    end

    context 'when one or more appeals have null issue descriptions' do
      before do
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:warn)
      end

      it 'increments a statsd metric, logs a warning, creates a PersonalInformationLog, ' \
         'and does NOT raise a JSON schema error',
         run_at: 'Wed, 20 Aug 2025 21:59:18 GMT' do
        VCR.use_cassette(
          'caseflow/appeal_with_null_issue_description',
          { match_requests_on: %i[method uri body] }
        ) do
          expect(StatsD).to receive(:increment).with(
            'api.appeals.appeals_with_null_issue_descriptions'
          )
          expect(Rails.logger).to receive(:warn).with(
            'Caseflow returned at least one appeal with at least one null issue description'
          )
          expect(PersonalInformationLog).to receive(:create!).with(
            data: { user:, appeals: expected_appeals_log_data },
            error_class: 'Caseflow AppealsWithNullIssueDescriptions'
          )

          result = subject.get_appeals(user)
          expect(result.status).to eq(200)
        end
      end
    end

    context 'when tracking incomplete appeal history' do
      let(:appeals) do
        [
          { 'id' => 'A1', 'attributes' => { 'incompleteHistory' => true } },
          { 'id' => 'A2', 'attributes' => { 'incompleteHistory' => false } },
          { 'id' => 'A3', 'attributes' => {} }
        ]
      end

      before { allow(StatsD).to receive(:increment) }

      it 'increments the appeals_fetched denominator once per appeal' do
        expect(StatsD).to receive(:increment).with('api.appeals.appeals_fetched').exactly(3).times

        subject.send(:track_appeals_with_incomplete_history, appeals)
      end

      it 'increments appeals_with_incomplete_history only for appeals flagged incompleteHistory' do
        expect(StatsD).to receive(:increment).with('api.appeals.appeals_with_incomplete_history').once

        subject.send(:track_appeals_with_incomplete_history, appeals)
      end
    end

    context 'when an exception is raised while monitoring appeals data quality' do
      let(:user) { build(:user, :loa3, ssn: '120495723') }

      before do
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(
          Caseflow::Service
        ).to receive(
          :handle_appeals_with_null_issue_descriptions
        ).and_raise(StandardError, 'test error')
      end

      it 'logs the error',
         run_at: 'Fri, 19 Jan 2018 17:26:32 GMT' do
        VCR.use_cassette(
          'caseflow/appeals_no_alert_details_due_date',
          { match_requests_on: %i[method uri body] }
        ) do
          expect(Rails.logger).to receive(:error).with(
            'Monitoring appeals data quality failed: test error'
          )

          subject.get_appeals(user)
        end
      end
    end
  end
end
