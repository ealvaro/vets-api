# frozen_string_literal: true

require 'csv'
require 'rails_helper'
require 'share_point/service'

RSpec.describe Mobile::V0::UploadSurveyResponseJob, type: :job do
  let(:service) { instance_double(SharePoint::Service) }

  describe '.sidekiq_retries_exhausted_block' do
    it 'logs retries exhausted with job and error details' do
      block = described_class.sidekiq_retries_exhausted_block
      msg = {
        'class' => described_class.name,
        'jid' => 'test-jid-123',
        'error_class' => 'RuntimeError',
        'error_message' => 'boom'
      }

      expect(StatsD).to receive(:increment).with('worker.mobile.v0.upload_survey_response.retries_exhausted')

      expect(Rails.logger).to receive(:error).with(
        'Mobile survey response upload retries exhausted',
        hash_including(
          job_class: described_class.name,
          jid: 'test-jid-123',
          error_class: 'RuntimeError',
          error_message: 'boom'
        )
      )

      block.call(msg, RuntimeError.new('boom'))
    end
  end

  describe '#perform' do
    context 'when no matching responses exist' do
      it 'does not call SharePoint and returns' do
        expect(SharePoint::Service).not_to receive(:new)

        subject.perform
      end
    end

    context 'when upload succeeds with single question' do
      it 'uploads CSV for the survey type and deletes only uploaded rows' do
        uuid1 = SecureRandom.uuid
        uuid2 = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid1,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Great'
            }
          },
          metadata: { 'os' => 'iOS' }
        )
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid2,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Okay'
            }
          },
          metadata: { 'os' => 'Android' }
        )
        Mobile::SurveyResponse.create!(
          survey_type: 'intercept',
          user_uuid: SecureRandom.uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'Question',
              'value' => 'Other survey type'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil
        captured_path = nil
        captured_filename = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, path, filename|
          captured_csv = csv_data
          captured_path = path
          captured_filename = filename
          response
        end

        subject.perform

        # Verify CSV structure
        rows = CSV.parse(captured_csv)
        expect(rows[0]).to eq(['uuid', '(q01) How was your experience?', 'os', 'submitted_at'])

        # Verify first data row contains flattened values
        expect(rows[1][0]).to eq(uuid1)
        expect(rows[1][1]).to eq('Great')
        expect(rows[1][2]).to eq('iOS')
        expect(captured_path).to eq('DEV ONLY/test/Survey Responses/give_feedback')
        expect(captured_filename).to match(/\Agive_feedback_\d{8}_\d{9}\.csv\z/)

        # Verify only giveFeedback rows were deleted
        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(0)
        expect(Mobile::SurveyResponse.where(survey_type: 'intercept').count).to eq(1)
      end
    end

    context 'when upload returns non-success' do
      it 'raises UploadError and does not delete rows' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Bad'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: false, status: 500, body: 'error')

        allow(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        allow(service).to receive(:upload_csv).and_return(response)

        expect { subject.perform }
          .to raise_error(Mobile::V0::UploadSurveyResponseJob::UploadError, /SharePoint upload failed with status: 500/)

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
      end
    end

    context 'when SharePoint authentication fails' do
      it 're-raises the authentication error and does not delete rows' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Bad'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        allow(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        allow(service).to receive(:upload_csv)
          .and_raise(SharePoint::AuthenticationError, 'auth failed')

        expect { subject.perform }
          .to raise_error(SharePoint::AuthenticationError, /auth failed/)

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
      end
    end

    context 'when survey has multiple questions' do
      it 'includes all question value columns and metadata columns' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'multiple_choice',
              'label' => 'Question 1',
              'value' => 'Yes'
            },
            'q02' => {
              'type' => 'free_response',
              'label' => 'Question 2',
              'value' => 'Some answer'
            }
          },
          metadata: { 'os' => 'iOS', 'app_version' => '1.0.0' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, _path, _filename|
          captured_csv = csv_data
          response
        end

        subject.perform

        rows = CSV.parse(captured_csv)

        # Verify headers include all question value columns in insertion order.
        expect(rows[0]).to eq(['uuid', '(q01) Question 1', '(q02) Question 2',
                               'os', 'app_version', 'submitted_at'])

        # Verify data row has correct values
        expect(rows[1][0]).to eq(uuid)
        expect(rows[1][1]).to eq('Yes')
        expect(rows[1][2]).to eq('Some answer')
        expect(rows[1][3]).to eq('iOS')
        expect(rows[1][4]).to eq('1.0.0')
      end
    end

    context 'when questions include additional dynamic fields' do
      it 'includes only question value columns for each question' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'multiple_choice',
              'label' => 'Question 1',
              'value' => 'Yes',
              'answer_code' => 'A1'
            },
            'q02' => {
              'type' => 'rating',
              'label' => 'Question 2',
              'value' => '5',
              'min' => '1',
              'max' => '5'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, _path, _filename|
          captured_csv = csv_data
          response
        end

        subject.perform

        rows = CSV.parse(captured_csv)

        expect(rows[0]).to eq(['uuid', '(q01) Question 1', '(q02) Question 2',
                               'os', 'submitted_at'])

        expect(rows[1][0]).to eq(uuid)
        expect(rows[1][1]).to eq('Yes')
        expect(rows[1][2]).to eq('5')
        expect(rows[1][3]).to eq('iOS')
      end
    end

    context 'when text values contain mojibake characters' do
      it 'repairs common UTF-8/Windows-1252 mojibake in CSV output' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'What was wrong?',
              'value' => 'I donâ€™t use the app'
            }
          },
          metadata: { 'os' => 'iOS â€” beta' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, _path, _filename|
          captured_csv = csv_data
          response
        end

        subject.perform

        rows = CSV.parse(captured_csv)
        expect(rows[1][1]).to eq('I don’t use the app')
        expect(rows[1][2]).to eq('iOS — beta')
      end
    end

    context 'when a question contains alt_values' do
      it 'creates an additional alt_value column for that question' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'multiple_choice',
              'label' => 'Overall satisfaction',
              'value' => 'Satisfied',
              'alt_value' => '4'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, _path, _filename|
          captured_csv = csv_data
          response
        end

        subject.perform

        rows = CSV.parse(captured_csv)

        expect(rows[0]).to eq(['uuid', '(q01) Overall satisfaction', '(q01) Alt Value', 'os', 'submitted_at'])
        expect(rows[1][0]).to eq(uuid)
        expect(rows[1][1]).to eq('Satisfied')
        expect(rows[1][2]).to eq('4')
        expect(rows[1][3]).to eq('iOS')
      end
    end

    context 'with preserve_data: true' do
      it 'does not delete rows after successful upload when called with symbol keys (Ruby invocation)' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Great'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv).and_return(response)

        subject.perform(preserve_data: true)

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
      end

      it 'does not delete rows after successful upload when called with string keys (Sidekiq cron invocation)' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Great'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv).and_return(response)

        subject.perform('preserve_data' => true)

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
      end
    end

    context 'with survey_types parameter' do
      it 'processes only the specified survey type when called with symbol keys (Ruby invocation)' do
        uuid_give_feedback = SecureRandom.uuid
        uuid_intercept = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid_give_feedback,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'feedback' } },
          metadata: { 'os' => 'iOS' }
        )
        Mobile::SurveyResponse.create!(
          survey_type: 'intercept',
          user_uuid: uuid_intercept,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'intercept' } },
          metadata: { 'os' => 'Android' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv).once.and_return(response)

        subject.perform(survey_types: 'intercept')

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
        expect(Mobile::SurveyResponse.where(survey_type: 'intercept').count).to eq(0)
      end

      it 'processes only the specified survey type when called with string keys (Sidekiq cron invocation)' do
        uuid_give_feedback = SecureRandom.uuid
        uuid_intercept = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid_give_feedback,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'feedback' } },
          metadata: { 'os' => 'iOS' }
        )
        Mobile::SurveyResponse.create!(
          survey_type: 'intercept',
          user_uuid: uuid_intercept,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'intercept' } },
          metadata: { 'os' => 'Android' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv).once.and_return(response)

        subject.perform('survey_types' => 'intercept')

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
        expect(Mobile::SurveyResponse.where(survey_type: 'intercept').count).to eq(0)
      end

      it 'processes multiple survey types when passed as an array' do
        uuid_feedback = SecureRandom.uuid
        uuid_intercept = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid_feedback,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'feedback' } },
          metadata: { 'os' => 'iOS' }
        )
        Mobile::SurveyResponse.create!(
          survey_type: 'intercept',
          user_uuid: uuid_intercept,
          survey_data: { 'q01' => { 'type' => 'text', 'label' => 'Question', 'value' => 'intercept' } },
          metadata: { 'os' => 'Android' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .twice
          .and_return(service)
        expect(service).to receive(:upload_csv).twice.and_return(response)

        subject.perform('survey_types' => %w[giveFeedback intercept])

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(0)
        expect(Mobile::SurveyResponse.where(survey_type: 'intercept').count).to eq(0)
      end
    end

    context 'when exporting submitted_at timestamp' do
      it 'formats submitted_at in Eastern Time' do
        uuid = SecureRandom.uuid
        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: uuid,
          created_at: Time.utc(2026, 1, 15, 16, 30, 0),
          survey_data: {
            'q01' => {
              'type' => 'free_response',
              'label' => 'How was your experience?',
              'value' => 'Great'
            }
          },
          metadata: { 'os' => 'iOS' }
        )

        response = instance_double(Faraday::Response, success?: true, status: 201)
        captured_csv = nil

        expect(SharePoint::Service).to receive(:new)
          .with(sharepoint_feature: :mobile_survey_storage)
          .and_return(service)
        expect(service).to receive(:upload_csv) do |csv_data, _path, _filename|
          captured_csv = csv_data
          response
        end

        subject.perform

        rows = CSV.parse(captured_csv)
        expect(rows[1][3]).to eq('2026-01-15T11:30:00-05:00')
      end
    end
  end
end
