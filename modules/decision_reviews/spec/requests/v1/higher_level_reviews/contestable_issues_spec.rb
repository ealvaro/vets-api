# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require './modules/decision_reviews/spec/support/vcr_helper'
require 'decision_reviews/util/response_comparison'
require 'decision_reviews/v1/appealable_issues/service'
require 'decision_reviews/v1/appealable_issues/configuration'

RSpec.describe 'DecisionReviews::V1::HigherLevelReviews::ContestableIssues', type: :request do
  # ICN must match the ICN in VCR cassette URLs since it's part of the query parameters
  let(:user) { build(:user, :loa3, icn: '1012832025V743496') }
  let(:success_log_args) do
    {
      message: 'Get contestable issues success!',
      user_uuid: user.uuid,
      action: 'Get contestable issues',
      form_id: '996',
      upstream_system: 'Lighthouse',
      downstream_system: nil,
      is_success: true,
      http: {
        status_code: 200,
        body: '[Redacted]'
      }
    }
  end
  let(:error_log_args) do
    {
      message: 'Get contestable issues failure!',
      user_uuid: user.uuid,
      action: 'Get contestable issues',
      form_id: '996',
      upstream_system: 'Lighthouse',
      downstream_system: nil,
      is_success: false,
      http: {
        status_code: 404,
        body: anything
      }
    }
  end
  let(:appealable_issues_service_success_log_args) do
    {
      message: 'Get contestable issues success!',
      user_uuid: user.uuid,
      action: 'Get contestable issues',
      form_id: '996',
      upstream_system: 'Lighthouse (New Appealable Issues API)',
      downstream_system: nil,
      is_success: true,
      http: {
        status_code: 200,
        body: '[Redacted]'
      }
    }
  end

  let(:comparison_message) { 'Appealable issues comparison' }
  let(:comparison_statsd_key) { 'api.decision_reviews.appealable_issues_comparison' }

  before { sign_in_as(user) }

  describe '#index' do
    subject { get '/decision_reviews/v1/higher_level_reviews/contestable_issues/compensation' }

    around do |example|
      Timecop.freeze(Time.zone.parse('2026-01-23')) do
        example.run
      end
    end

    def personal_information_logs
      PersonalInformationLog.where 'error_class like ?',
                                   'DecisionReviews::V1::HigherLevelReviews::ContestableIssuesController#index exception % (HLR_V1)' # rubocop:disable Layout/LineLength
    end

    context 'with feature flag disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_use_new_appealable_issues_service,
                                                  instance_of(User)).and_return(false)
      end

      it 'does not call the appealable issues service and does not log a comparison' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
            expect_any_instance_of(DecisionReviews::V1::AppealableIssues::Service)
              .not_to receive(:get_higher_level_review_issues)
            allow(Rails.logger).to receive(:info)
            expect(Rails.logger).not_to receive(:info).with(hash_including(message: comparison_message))
            subject
            expect(response).to be_successful
          end
        end
      end

      it 'fetches issues that the Veteran could contest via a higher-level review' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
            allow(Rails.logger).to receive(:info)
            expect(Rails.logger).to receive(:info).with(success_log_args)
            subject
            expect(response).to be_successful
            expect(JSON.parse(response.body)['data']).to be_an Array
            expect(JSON.parse(response.body)['data'].length).to be 4
          end
        end
      end

      it 'fetches issues that the Veteran could contest via a higher-level review, but empty Legacy Appeals' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200-EMPTY_V1') do
            subject
            expect(response).to be_successful
            expect(JSON.parse(response.body)['data']).to be_an Array
            expect(JSON.parse(response.body)['data'].length).to be 4
          end
        end
      end

      it 'adds to the PersonalInformationLog when an exception is thrown' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-404_V1') do
          expect(personal_information_logs.count).to be 0
          allow(Rails.logger).to receive(:error)
          expect(Rails.logger).to receive(:error).with(error_log_args)
          subject
          expect(personal_information_logs.count).to be 1
          pil = personal_information_logs.first
          expect(pil.data['user']).to be_truthy
          expect(pil.data['error']).to be_truthy
        end
      end
    end

    context 'with feature flag enabled' do
      # These expectations describe the cassettes, not the APIs: the two schemas define the same
      # attributes, but the HLR fixtures were hand-written from different data and the appealable
      # issues one only fills in seven of the sixteen attributes.
      let(:cassette_comparison_log_args) do
        {
          message: 'Appealable issues comparison',
          form_id: '996',
          result: 'mismatch',
          comparison: {
            decision_review_issue_count: 4,
            appealable_issues_issue_count: 4,
            differing_attribute_names: %w[isRating rampClaimId ratingIssueDiagnosticCode ratingIssueProfileDate
                                          ratingIssueReferenceId sourceReviewType timely titleOfActiveReview],
            ordering_differs: false
          }
        }
      end
      let(:no_issues_comparison_log_args) do
        {
          message: 'Appealable issues comparison',
          form_id: '996',
          result: 'match',
          comparison: {
            decision_review_issue_count: 0,
            appealable_issues_issue_count: 0,
            differing_attribute_names: [],
            ordering_differs: false
          }
        }
      end
      let(:error_comparison_log_args) do
        {
          message: 'Appealable issues comparison failed',
          form_id: '996',
          result: 'error',
          error_class: anything
        }
      end
      # Two empty responses trivially match, so the appealable issues response is the one rendered.
      let(:empty_issues_body) { { 'data' => [] } }

      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_use_new_appealable_issues_service,
                                                  instance_of(User)).and_return(true)
        # Stub access_token directly to avoid OAuth setup
        allow_any_instance_of(DecisionReviews::V1::AppealableIssues::Configuration)
          .to receive(:access_token).and_return('fake-token-12345')
      end

      it 'calls both services and logs the comparison' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              allow(Rails.logger).to receive(:info)
              expect(Rails.logger).to receive(:info).with(success_log_args)
              expect(Rails.logger).to receive(:info).with(appealable_issues_service_success_log_args)
              expect(Rails.logger).to receive(:info).with(cassette_comparison_log_args)
              subject
              expect(response).to be_successful
            end
          end
        end
      end

      it 'renders the decision review response when the two do not match' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              subject
              expect(response).to be_successful
              issues = JSON.parse(response.body)['data']
              expect(issues.length).to be 4
              expect(issues.map { |issue| issue['type'] }.uniq).to eq ['contestableIssue']
              expect(issues.first['attributes']).to have_key 'ratingIssueReferenceId'
            end
          end
        end
      end

      it 'increments a StatsD counter tagged by form type and result' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              expect { subject }.to trigger_statsd_increment(comparison_statsd_key,
                                                             tags: ['form_id:996', 'result:mismatch'])
            end
          end
        end
      end

      it 'logs a match and renders the appealable issues response when neither API returns issues' do
        allow_any_instance_of(DecisionReviews::V1::Service)
          .to receive(:get_higher_level_review_contestable_issues).and_return(double(body: empty_issues_body))
        allow_any_instance_of(DecisionReviews::V1::AppealableIssues::Service)
          .to receive(:get_higher_level_review_issues).and_return(double(body: empty_issues_body))

        VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
          allow(Rails.logger).to receive(:info)
          expect(Rails.logger).to receive(:info).with(no_issues_comparison_log_args)
          expect { subject }.to trigger_statsd_increment(comparison_statsd_key,
                                                         tags: ['form_id:996', 'result:match'])
          expect(response).to be_successful
          expect(JSON.parse(response.body)['data']).to eq []
        end
      end

      it 'renders the decision review response when the appealable issues service fails' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-404') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              # Override ICN to simulate veteran not found scenario in the new API only; the existing
              # API identifies the Veteran by a header, so its cassette still matches.
              allow_any_instance_of(User).to receive(:icn).and_return('0000000000V000000')
              allow(Rails.logger).to receive(:error)
              expect(Rails.logger).to receive(:error).with(error_comparison_log_args)
              subject
              expect(response).to be_successful
              expect(JSON.parse(response.body)['data'].length).to be 4
              expect(personal_information_logs.count).to be 0
            end
          end
        end
      end

      it 'renders the decision review response when the comparison itself fails' do
        allow(DecisionReviews::Util::ResponseComparison)
          .to receive(:new).and_raise(StandardError, 'comparison exploded')

        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              allow(Rails.logger).to receive(:error)
              expect(Rails.logger).to receive(:error).with(error_comparison_log_args)
              subject
              expect(response).to be_successful
              expect(JSON.parse(response.body)['data'].length).to be 4
            end
          end
        end
      end

      it 'still adds to the PersonalInformationLog and raises when the decision review service fails' do
        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-404_V1') do
          expect(personal_information_logs.count).to be 0
          subject
          expect(response).not_to be_successful
          expect(personal_information_logs.count).to be 1
        end
      end

      it 'does not log the user uuid or any value from either response body' do
        logged = []
        allow(Rails.logger).to receive(:info) { |payload| logged << payload.to_s }
        allow(Rails.logger).to receive(:error) { |payload| logged << payload.to_s }

        VCR.use_cassette('decision_review/HLR-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/HLR-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/HLR-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              subject
              comparison_logs = logged.select { |entry| entry.include?(comparison_message) }
              expect(comparison_logs).not_to be_empty
              comparison_logs.each { |entry| expect(entry).not_to include user.uuid }
              JSON.parse(response.body)['data'].each do |issue|
                issue['attributes'].each_value do |value|
                  # Booleans and short numeric strings collide with the counts and booleans the
                  # comparison log legitimately contains.
                  next unless value.is_a?(String) && value.length >= 4

                  comparison_logs.each { |entry| expect(entry).not_to include value }
                end
              end
            end
          end
        end
      end
    end
  end
end
