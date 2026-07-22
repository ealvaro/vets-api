# frozen_string_literal: true

require 'csv'
require 'rails_helper'
require 'share_point/service'

RSpec.describe Mobile::V0::UploadSurveyResponseJob, type: :job do
  let(:service) { instance_double(SharePoint::Service) }

  before do
    allow(Flipper).to receive(:enabled?)
      .with(Mobile::V0::UploadSurveyResponseJob::DELETE_AFTER_UPLOAD_FEATURE)
      .and_return(true)
  end

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
      it 'uploads flattened CSV for the survey type and deletes only uploaded rows' do
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
          survey_type: 'RxIntercept',
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
        expect(rows[0]).to eq(%w[uuid q01_type q01_label q01_value os submitted_at])

        # Verify first data row contains flattened values
        expect(rows[1][0]).to eq(uuid1)
        expect(rows[1][1]).to eq('free_response')
        expect(rows[1][2]).to eq('How was your experience?')
        expect(rows[1][3]).to eq('Great')
        expect(rows[1][4]).to eq('iOS')
        expect(captured_path).to eq('Survey Responses/give_feedback')
        expect(captured_filename).to match(/\Agive_feedback_\d{8}_\d{9}\.csv\z/)

        # Verify only giveFeedback rows were deleted
        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(0)
        expect(Mobile::SurveyResponse.where(survey_type: 'RxIntercept').count).to eq(1)
      end
    end

    context 'when delete after upload feature is disabled' do
      it 'uploads flattened CSV and does not delete rows' do
        allow(Flipper).to receive(:enabled?)
          .with(Mobile::V0::UploadSurveyResponseJob::DELETE_AFTER_UPLOAD_FEATURE)
          .and_return(false)

        Mobile::SurveyResponse.create!(
          survey_type: 'giveFeedback',
          user_uuid: SecureRandom.uuid,
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

        subject.perform

        expect(Mobile::SurveyResponse.where(survey_type: 'giveFeedback').count).to eq(1)
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
      it 'flattens all questions and metadata into columns' do
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

        # Verify headers include all flattened columns in insertion order
        expect(rows[0]).to eq(%w[uuid q01_type q01_label q01_value
                                 q02_type q02_label q02_value
                                 os app_version submitted_at])

        # Verify data row has correct values
        expect(rows[1][0]).to eq(uuid)
        expect(rows[1][1]).to eq('multiple_choice')
        expect(rows[1][2]).to eq('Question 1')
        expect(rows[1][3]).to eq('Yes')
        expect(rows[1][4]).to eq('free_response')
        expect(rows[1][5]).to eq('Question 2')
        expect(rows[1][6]).to eq('Some answer')
        expect(rows[1][7]).to eq('iOS')
        expect(rows[1][8]).to eq('1.0.0')
      end
    end

    context 'when questions include additional dynamic fields' do
      it 'includes required and extra columns for each question' do
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

        expect(rows[0]).to eq(%w[uuid q01_type q01_label q01_value q01_answer_code
                                 q02_type q02_label q02_value q02_min q02_max
                                 os submitted_at])

        expect(rows[1][0]).to eq(uuid)
        expect(rows[1][1]).to eq('multiple_choice')
        expect(rows[1][2]).to eq('Question 1')
        expect(rows[1][3]).to eq('Yes')
        expect(rows[1][4]).to eq('A1')
        expect(rows[1][5]).to eq('rating')
        expect(rows[1][6]).to eq('Question 2')
        expect(rows[1][7]).to eq('5')
        expect(rows[1][8]).to eq('1')
        expect(rows[1][9]).to eq('5')
        expect(rows[1][10]).to eq('iOS')
      end
    end
  end
end
