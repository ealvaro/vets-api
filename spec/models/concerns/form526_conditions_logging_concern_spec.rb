# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form526ConditionsLoggingConcern do
  subject(:submission) { create(:form526_submission) }

  describe '#log_conditions_date_metrics' do
    let!(:in_progress_form) { create(:in_progress_526_form, user_uuid: submission.user_uuid) }
    let(:raw_form) do
      {
        'newPrimaryDisabilities' => [
          { 'condition' => 'acne', 'conditionDate' => '2022-04-01' },       # full
          { 'condition' => 'bronchitis', 'conditionDate' => '2024-02-XX' }, # partial (month + year)
          { 'condition' => 'no date condition' }                            # blank (no date key)
        ],
        'ratedDisabilities' => [
          { 'name' => 'tinnitus', 'approximateDate' => '2021-01-01', 'disabilityActionType' => 'INCREASE' }, # full
          { 'name' => 'asthma', 'disabilityActionType' => 'INCREASE' }, # blank (no date key)
          { 'name' => 'existing rating', 'disabilityActionType' => 'NONE' } # excluded
        ]
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(submission.saved_claim).to receive(:parsed_form).and_return(raw_form)
    end

    it 'logs the aggregate date-completion counts with submission identifiers' do
      submission.log_conditions_date_metrics

      expect(Rails.logger).to have_received(:info).with(
        'Form526 conditions date metrics',
        submission_id: submission.id,
        user_uuid: submission.user_uuid,
        in_progress_form_id: in_progress_form.id,
        full_count: 2,
        partial_count: 1,
        blank_count: 2,
        total_conditions: 5
      )
    end

    context 'when a condition array is absent' do
      # A submission only contains the arrays relevant to it, and the arrays that
      # are present may still contribute no counted conditions (e.g. a
      # ratedDisabilities key with no entries claimed for an increase).
      let(:raw_form) do
        { 'newPrimaryDisabilities' => [{ 'conditionDate' => '2022-04-01' }] }
      end

      it 'counts only the conditions that are present' do
        submission.log_conditions_date_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions date metrics',
          hash_including(full_count: 1, partial_count: 0, blank_count: 0, total_conditions: 1)
        )
      end
    end

    context 'when rated disabilities are not being claimed for an increase' do
      # Only rated disabilities with disabilityActionType "INCREASE" are claimed;
      # existing ratings (e.g. "NONE") should not be counted in the total.
      let(:raw_form) do
        {
          'ratedDisabilities' => [
            { 'name' => 'tinnitus', 'approximateDate' => '2021-01-01', 'disabilityActionType' => 'INCREASE' },
            { 'name' => 'asthma', 'disabilityActionType' => 'NONE' },
            { 'name' => 'bronchitis', 'approximateDate' => '2021-XX-XX', 'disabilityActionType' => 'INCREASE' }
          ]
        }
      end

      it 'counts only the rated disabilities being claimed for an increase' do
        submission.log_conditions_date_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions date metrics',
          hash_including(full_count: 1, partial_count: 1, blank_count: 0, total_conditions: 2)
        )
      end
    end

    it 'rescues errors and does not raise' do
      # Ensures a logging failure never blocks submission.
      allow(submission.saved_claim).to receive(:parsed_form).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)

      expect { submission.log_conditions_date_metrics }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(
        "Form526ClaimsFastTrackingConcern #{submission.id} encountered an error",
        submission_id: submission.id,
        error_message: 'boom'
      )
    end
  end

  describe '#log_conditions_evidence_metrics' do
    let!(:in_progress_form) { create(:in_progress_526_form, user_uuid: submission.user_uuid) }
    let(:raw_form) do
      {
        'newPrimaryDisabilities' => [
          { 'condition' => 'acne' },
          { 'condition' => 'bronchitis' }
        ],
        'ratedDisabilities' => [
          { 'name' => 'tinnitus', 'disabilityActionType' => 'INCREASE' },
          { 'name' => 'existing rating', 'disabilityActionType' => 'NONE' }
        ],
        'vaTreatmentFacilities' => [{ 'treatmentCenterName' => 'VA Medical Center' }],
        'form4142' => { 'providerFacility' => [{ 'name' => 'Private Provider A' },
                                               { 'name' => 'Private Provider B' }] },
        'attachments' => [{ 'name' => 'post_surgery_report.pdf' }],
        'toxicExposure' => {
          'otherExposures' => { 'asbestos' => true }
        }
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(submission.saved_claim).to receive(:parsed_form).and_return(raw_form)
    end

    it 'logs the evidence metrics with submission identifiers' do
      submission.log_conditions_evidence_metrics

      expect(Rails.logger).to have_received(:info).with(
        'Form526 conditions evidence metrics',
        submission_id: submission.id,
        user_uuid: submission.user_uuid,
        in_progress_form_id: in_progress_form.id,
        toxic_exposure: true,
        evidence_va: 1,
        evidence_private: 2,
        evidence_uploads: 1,
        evidence_any: true,
        total_conditions: 3
      )
    end

    context 'when no toxic exposure questions are answered affirmatively' do
      let(:raw_form) do
        {
          'toxicExposure' => {
            'gulfWar1990' => { 'afghanistan' => false },
            'gulfWar2001' => { 'yemen' => false }
          }
        }
      end

      it 'sets toxic_exposure to false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: false)
        )
      end
    end

    context 'when only "notsure" or "none" toxic exposure answers are present' do
      # "notsure" and "none" should not count as toxic exposure being reported.
      let(:raw_form) do
        {
          'toxicExposure' => {
            'gulfWar1990' => { 'notsure' => true },
            'herbicide' => { 'none' => true },
            'otherExposures' => { 'none' => true }
          }
        }
      end

      it 'sets toxic_exposure to false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: false)
        )
      end
    end

    context 'when otherHerbicideLocations has a description' do
      # a description for otherHerbicideLocations should count as toxic exposure being reported.
      let(:raw_form) do
        {
          'toxicExposure' => {
            'otherHerbicideLocations' => { 'description' => 'A location not in the list' }
          }
        }
      end

      it 'sets toxic_exposure to true' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: true)
        )
      end
    end

    context 'when specifyOtherExposures has a description' do
      # a description for specifyOtherExposures should count as toxic exposure being reported.
      let(:raw_form) do
        {
          'toxicExposure' => {
            'specifyOtherExposures' => { 'description' => 'Some other substance' }
          }
        }
      end

      it 'sets toxic_exposure to true' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: true)
        )
      end
    end

    context 'when otherHerbicideLocations and specifyOtherExposures have blank descriptions' do
      let(:raw_form) do
        {
          'toxicExposure' => {
            'otherHerbicideLocations' => { 'description' => '' },
            'specifyOtherExposures' => { 'description' => nil }
          }
        }
      end

      it 'sets toxic_exposure to false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: false)
        )
      end
    end

    context 'when toxicExposure is absent' do
      let(:raw_form) { {} }

      it 'sets toxic_exposure to false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(toxic_exposure: false)
        )
      end
    end

    context 'when no evidence is present' do
      let(:raw_form) { {} }

      it 'sets all evidence counts to zero and evidence_any to false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(evidence_va: 0, evidence_private: 0, evidence_uploads: 0, evidence_any: false)
        )
      end
    end

    context 'when disabilityCompConditionsEvidenceMessagingTest is true' do
      let(:raw_form) { { 'disabilityCompConditionsEvidenceMessagingTest' => true } }

      it 'includes the flag value in the payload when the value is true' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(disability_comp_conditions_evidence_messaging_test: true)
        )
      end
    end

    context 'when disabilityCompConditionsEvidenceMessagingTest is false' do
      let(:raw_form) { { 'disabilityCompConditionsEvidenceMessagingTest' => false } }

      it 'includes the flag value in the payload when the value is false' do
        submission.log_conditions_evidence_metrics

        expect(Rails.logger).to have_received(:info).with(
          'Form526 conditions evidence metrics',
          hash_including(disability_comp_conditions_evidence_messaging_test: false)
        )
      end
    end

    it 'rescues errors and does not raise' do
      # Ensures a logging failure never blocks submission.
      allow(submission.saved_claim).to receive(:parsed_form).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)

      expect { submission.log_conditions_evidence_metrics }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(
        "Form526ClaimsFastTrackingConcern #{submission.id} encountered an error",
        submission_id: submission.id,
        error_message: 'boom'
      )
    end
  end
end
