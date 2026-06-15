# frozen_string_literal: true

require 'rails_helper'
require 'forms/submission_statuses/dataset'
require 'forms/submission_statuses/formatters/hca1010_ez_formatter'

describe Forms::SubmissionStatuses::Formatters::Hca1010EzFormatter,
         feature: :form_submission,
         team_owner: :health_apps_backend do
  subject { described_class.new }

  describe '#format_data without statuses' do
    let(:current_user) { create(:user_account) }
    let(:dataset) { instance_double(Forms::SubmissionStatuses::Dataset) }
    let(:statuses_data) { [] }

    before do
      allow(dataset).to receive_messages(
        submissions?: true,
        submissions: [current_user],
        intake_statuses?: true,
        intake_statuses: statuses_data
      )
    end

    it 'returns an empty hash' do
      result = subject.format_data(dataset)

      expect(result).to eq([])
    end
  end

  describe '#format_data with statuses' do
    let(:current_user) { create(:user_account) }
    let(:dataset) { instance_double(Forms::SubmissionStatuses::Dataset) }
    let(:statuses_data) do
      [
        {
          id: current_user.id,
          status: 'received',
          created_at: '2018-12-27T00:00:00.000-06:00',
          updated_at: '2018-12-27T17:15:39.000-06:00'
        }
      ]
    end

    before do
      allow(dataset).to receive_messages(
        submissions?: true,
        submissions: [current_user],
        intake_statuses?: true,
        intake_statuses: statuses_data
      )
    end

    it 'merges submissions with statuses correctly' do
      result = subject.format_data(dataset)

      expect(result.size).to eq(1)
      record = result.first

      expect(record.id).to eq(current_user.id)
      expect(record.form_type).to eq('10-10EZ')
      expect(record.status).to eq('received')
      expect(record.created_at).to be_a(Time)
      expect(record.updated_at).to be_a(Time)
    end
  end
end
