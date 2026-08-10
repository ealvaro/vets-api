# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require './modules/decision_reviews/spec/support/vcr_helper'
require 'decision_reviews/util/response_comparison'
require 'decision_reviews/v1/appealable_issues/service'
require 'decision_reviews/v1/appealable_issues/configuration'

RSpec.describe 'DecisionReviews::V1::SupplementalClaims::ContestableIssues', type: :request do
  # ICN must match the ICN in VCR cassette URLs since it's part of the query parameters
  let(:user) { build(:user, :loa3, icn: '1012832025V743496') }
  let(:success_log_args) do
    {
      message: 'Get contestable issues success!',
      user_uuid: user.uuid,
      action: 'Get contestable issues',
      form_id: '995',
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
      form_id: '995',
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
      form_id: '995',
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
    subject { get '/decision_reviews/v1/supplemental_claims/contestable_issues/compensation' }

    around do |example|
      Timecop.freeze(Time.zone.parse('2026-01-23')) do
        example.run
      end
    end

    def personal_information_logs
      PersonalInformationLog.where 'error_class like ?',
                                   'DecisionReviews::V1::SupplementalClaims::ContestableIssuesController#index exception % (SC_V1)' # rubocop:disable Layout/LineLength
    end

    context 'with feature flag disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_use_new_appealable_issues_service,
                                                  instance_of(User)).and_return(false)
      end

      it 'does not call the appealable issues service and does not log a comparison' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
            expect_any_instance_of(DecisionReviews::V1::AppealableIssues::Service)
              .not_to receive(:get_supplemental_claim_issues)
            allow(Rails.logger).to receive(:info)
            expect(Rails.logger).not_to receive(:info).with(hash_including(message: comparison_message))
            subject
            expect(response).to be_successful
          end
        end
      end

      it 'uses contestable issues service and returns issues successfully' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
            allow(Rails.logger).to receive(:info)
            expect(Rails.logger).to receive(:info).with(success_log_args)
            subject
            expect(response).to be_successful
            expect(JSON.parse(response.body)['data']).to be_an Array
          end
        end
      end

      it 'fetches issues that the Veteran could contest via a supplemental claim, but empty Legacy Appeals' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200-EMPTY_V1') do
            subject
            expect(response).to be_successful
            expect(JSON.parse(response.body)['data']).to be_an Array
          end
        end
      end

      it 'logs errors to PersonalInformationLog when an exception is thrown' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-404_V1') do
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
      # The SC fixtures are the realistic pair: the same seven issues, same attributes, same order
      # on both sides, differing only in the `type` label. So the comparison matches and the
      # appealable issues response is the one rendered -- the only observable difference being that
      # each issue comes back typed "appealableIssue" instead of "contestableIssue".
      let(:cassette_comparison_log_args) do
        {
          message: 'Appealable issues comparison',
          form_id: '995',
          result: 'match',
          comparison: {
            decision_review_issue_count: 7,
            appealable_issues_issue_count: 7,
            differing_attribute_names: [],
            ordering_differs: false
          }
        }
      end
      let(:no_issues_comparison_log_args) do
        {
          message: 'Appealable issues comparison',
          form_id: '995',
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
          form_id: '995',
          result: 'error',
          error_class: anything
        }
      end
      # Two empty responses trivially match, so the appealable issues response is the one rendered.
      let(:empty_issues_body) { { 'data' => [] } }

      def sc_issue(type, subject_text)
        { 'id' => nil, 'type' => type,
          'attributes' => { 'ratingIssueSubjectText' => subject_text, 'approxDecisionDate' => '2020-02-01' } }
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:decision_review_use_new_appealable_issues_service,
                                                  instance_of(User)).and_return(true)
        # Stub access_token directly to avoid OAuth setup
        allow_any_instance_of(DecisionReviews::V1::AppealableIssues::Configuration)
          .to receive(:access_token).and_return('fake-token-12345')
      end

      it 'calls both services and logs the comparison' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
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

      it 'renders the appealable issues response, differing only in the type label' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              subject
              expect(response).to be_successful
              issues = JSON.parse(response.body)['data']
              expect(issues.length).to be 7
              expect(issues.map { |issue| issue['type'] }.uniq).to eq ['appealableIssue']
            end
          end
        end
      end

      # These two cassettes list their issues in the same order, so stripping the type label makes
      # the two responses identical. The gate also tolerates reordering (see the spec below), in
      # which case the guarantee is the weaker "same issues", not "same sequence".
      it 'renders issues identical to the decision review response once the type label is removed' do
        appealable = nil
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              subject
              appealable = JSON.parse(response.body)['data']
            end
          end
        end

        allow(Flipper).to receive(:enabled?).with(:decision_review_use_new_appealable_issues_service,
                                                  instance_of(User)).and_return(false)
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
            get '/decision_reviews/v1/supplemental_claims/contestable_issues/compensation'
            contestable = JSON.parse(response.body)['data']
            strip_type = ->(issues) { issues.map { |issue| issue.except('type') } }
            expect(strip_type.call(appealable)).to eq strip_type.call(contestable)
          end
        end
      end

      it 'increments a StatsD counter tagged by form type and result' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              expect { subject }.to trigger_statsd_increment(comparison_statsd_key,
                                                             tags: ['form_id:995', 'result:match'])
            end
          end
        end
      end

      # Ordering is disregarded because no consumer observes it: vets-website re-sorts every list by
      # decision date before display. The Veteran therefore receives the new API's sequence, which
      # the frontend normalizes away -- and `ordering_differs` records that it happened.
      it 'renders the appealable issues response, in its own order, when only the order differs' do
        allow_any_instance_of(DecisionReviews::V1::Service)
          .to receive(:get_supplemental_claim_contestable_issues)
          .and_return(double(body: { 'data' => [sc_issue('contestableIssue', 'Migraine'),
                                                sc_issue('contestableIssue', 'PTSD')] }))
        allow_any_instance_of(DecisionReviews::V1::AppealableIssues::Service)
          .to receive(:get_supplemental_claim_issues)
          .and_return(double(body: { 'data' => [sc_issue('appealableIssue', 'PTSD'),
                                                sc_issue('appealableIssue', 'Migraine')] }))

        VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
          allow(Rails.logger).to receive(:info)
          expect(Rails.logger).to receive(:info).with(
            hash_including(result: 'match', comparison: hash_including(ordering_differs: true))
          )
          expect { subject }.to trigger_statsd_increment(comparison_statsd_key,
                                                         tags: ['form_id:995', 'result:match'])
          expect(response).to be_successful
          issues = JSON.parse(response.body)['data']
          expect(issues.map { |issue| issue['type'] }.uniq).to eq ['appealableIssue']
          expect(issues.map { |issue| issue['attributes']['ratingIssueSubjectText'] }).to eq %w[PTSD Migraine]
        end
      end

      it 'logs a match and renders the appealable issues response when neither API returns issues' do
        allow_any_instance_of(DecisionReviews::V1::Service)
          .to receive(:get_supplemental_claim_contestable_issues).and_return(double(body: empty_issues_body))
        allow_any_instance_of(DecisionReviews::V1::AppealableIssues::Service)
          .to receive(:get_supplemental_claim_issues).and_return(double(body: empty_issues_body))

        VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
          allow(Rails.logger).to receive(:info)
          expect(Rails.logger).to receive(:info).with(no_issues_comparison_log_args)
          expect { subject }.to trigger_statsd_increment(comparison_statsd_key,
                                                         tags: ['form_id:995', 'result:match'])
          expect(response).to be_successful
          expect(JSON.parse(response.body)['data']).to eq []
        end
      end

      it 'renders the decision review response when the appealable issues service fails' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-404') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              # Override ICN to simulate veteran not found scenario in the new API only; the existing
              # API identifies the Veteran by a header, so its cassette still matches.
              allow_any_instance_of(User).to receive(:icn).and_return('0000000000V000000')
              allow(Rails.logger).to receive(:error)
              expect(Rails.logger).to receive(:error).with(error_comparison_log_args)
              subject
              expect(response).to be_successful
              expect(JSON.parse(response.body)['data'].length).to be 7
              expect(personal_information_logs.count).to be 0
            end
          end
        end
      end

      it 'renders the decision review response when the comparison itself fails' do
        allow(DecisionReviews::Util::ResponseComparison)
          .to receive(:new).and_raise(StandardError, 'comparison exploded')

        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
              allow(Rails.logger).to receive(:error)
              expect(Rails.logger).to receive(:error).with(error_comparison_log_args)
              subject
              expect(response).to be_successful
              expect(JSON.parse(response.body)['data'].length).to be 7
            end
          end
        end
      end

      it 'still adds to the PersonalInformationLog and raises when the decision review service fails' do
        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-404_V1') do
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

        VCR.use_cassette('decision_review/SC-GET-CONTESTABLE-ISSUES-RESPONSE-200_V1') do
          VCR.use_cassette('decision_review/appealable_issues/SC-GET-APPEALABLE-ISSUES-RESPONSE-200') do
            VCR.use_cassette('decision_review/SC-GET-LEGACY_APPEALS-RESPONSE-200_V1') do
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
