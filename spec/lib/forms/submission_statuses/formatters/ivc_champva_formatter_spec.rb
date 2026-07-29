# frozen_string_literal: true

require 'rails_helper'
require 'forms/submission_statuses/formatters/ivc_champva_formatter'

describe Forms::SubmissionStatuses::Formatters::IvcChampvaFormatter,
         feature: :form_submission,
         team_owner: :health_apps_backend do
  subject(:formatter) { described_class.new }

  describe '#format_data' do
    it 'maps PEGA Processed status to vbms (received)' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-7959a',
        pega_status: 'Processed'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.length).to eq(1)
      expect(result.first.form_type).to eq('10-7959A')
      expect(result.first.status).to eq('vbms')
      expect(result.first.pdf_support).to be(false)
    end

    it 'normalizes 10-10D-EXTENDED form type to 10-10D for card display' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D-EXTENDED',
        pega_status: 'Processed'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.form_type).to eq('10-10D')
    end

    it 'excludes 10-10D-EXTENDED-EXISTING from card display' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D-EXTENDED-EXISTING',
        pega_status: 'Submitted'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result).to be_empty
    end

    it 'maps PEGA Not Processed status to error (action needed)' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: 'Not Processed'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('error')
    end

    it 'maps PEGA Received status to claimReceived' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: 'Received'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('claimReceived')
    end

    it 'maps additional documentation requested to claimReceived' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: 'additional documentation requested'
      )
      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )
      result = formatter.format_data(dataset)
      expect(result.first.status).to eq('claimReceived')
    end

    it 'returns complete when all applicants have eligibility resolved' do
      transaction_uuid = SecureRandom.uuid
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        transaction_uuid:
      )
      create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: true)

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('complete')
    end

    it 'does not return complete based on PEGA status alone' do
      [
        'eligiblity denied/additional information needed',
        'eligibility denied/additional information needed',
        'Eligible - issued a card'
      ].each do |status|
        submission = create(
          :ivc_champva_form,
          form_uuid: SecureRandom.uuid,
          form_number: '10-10D',
          pega_status: status
        )
        dataset = double(
          'Dataset',
          submissions?: true,
          submissions: [submission],
          intake_statuses?: false,
          intake_statuses: nil
        )
        result = formatter.format_data(dataset)
        expect(result.first.status).not_to eq('complete'),
                                           "expected '#{status}' not to map to complete via PEGA status alone"
      end
    end

    it 'uses PEGA status precedence over VES and S3 statuses' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: 'Processed',
        ves_status: 'ok',
        s3_status: 'failed'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('vbms')
    end

    it 'maps VES internal_server_error to error when PEGA status is missing' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: nil,
        ves_status: 'internal_server_error',
        s3_status: 'Submitted'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('error')
    end

    it 'returns pending when all statuses are blank' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        ves_status: nil,
        pega_status: nil,
        s3_status: nil
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('pending')
    end

    it 'returns error and logs a warning when pega_status is unrecognized' do
      submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D',
        pega_status: 'd',
        ves_status: nil,
        s3_status: nil
      )

      allow(Rails.logger).to receive(:warn)

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.first.status).to eq('error')
      expect(Rails.logger).to have_received(:warn).with(
        '[Forms::SubmissionStatuses::Formatters::IvcChampvaFormatter] Unrecognized status received',
        hash_including(
          form_uuid: submission.form_uuid,
          source: :pega_status,
          raw_status: 'd'
        )
      )
    end

    it 'excludes docs-only supporting-document submissions from application cards' do
      docs_only_submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D-EXTENDED-EXISTING',
        pega_status: 'Submitted'
      )
      real_application_submission = create(
        :ivc_champva_form,
        form_uuid: SecureRandom.uuid,
        form_number: '10-10D-EXTENDED',
        pega_status: 'Submitted'
      )

      dataset = double(
        'Dataset',
        submissions?: true,
        submissions: [docs_only_submission, real_application_submission],
        intake_statuses?: false,
        intake_statuses: nil
      )

      result = formatter.format_data(dataset)

      expect(result.map(&:id)).to contain_exactly(real_application_submission.form_uuid.to_s)
    end
  end
end
