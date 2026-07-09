# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/sidekiq/event_bus_gateway/constants'

RSpec.describe EventBusGateway::LetterReadyClaimLetterRecheckJob, type: :job do
  subject { described_class }

  let(:participant_id) { '1234' }
  let(:interval_label) { '1h' }
  let(:original_sent_at) { 1.hour.ago.utc.iso8601 }

  let(:bgs_profile) do
    {
      first_nm: 'Joe',
      last_nm: 'Smith',
      brthdy_dt: 30.years.ago,
      ssn_nbr: '123456789'
    }
  end

  let(:mpi_profile) { build(:mpi_profile) }
  let(:mpi_profile_response) { create(:find_profile_response, profile: mpi_profile) }
  let!(:user_account) { create(:user_account, icn: mpi_profile_response.profile.icn) }

  # Send-time snapshot as it would arrive over the Sidekiq queue (string keys):
  # one decision letter present when the notification fired.
  let(:snapshot) do
    {
      'letter_count' => 2,
      'decision_letter_count' => 1,
      'decision_letter_document_ids' => ['doc-old'],
      'most_recent_decision_received_at' => (Time.zone.today - 30).iso8601,
      'most_recent_decision_document_id' => 'doc-old'
    }
  end

  # Same single decision letter as the snapshot, stamped outside the recency
  # window: both signals read negative (delta: no set change, recency: too old).
  let(:letters) do
    [
      { doc_type: '184', document_id: 'doc-old', type_description: 'Decision Letter',
        received_at: 30.days.ago, upload_date: 30.days.ago },
      { doc_type: '702', document_id: 'doc-other', type_description: 'Other',
        received_at: 30.days.ago, upload_date: 30.days.ago }
    ]
  end
  let(:provider) { instance_double(LighthouseClaimLettersProvider, get_letters: letters) }

  before do
    allow_any_instance_of(MPI::Service).to receive(:find_profile_by_attributes)
      .and_return(mpi_profile_response)
    allow_any_instance_of(BGS::PersonWebService)
      .to receive(:find_person_by_ptcpnt_id)
      .and_return(bgs_profile)
    allow(StatsD).to receive(:increment)
    allow(StatsD).to receive(:measure)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Flipper).to receive(:enabled?)
      .with(:event_bus_gateway_claim_letter_recheck, instance_of(Flipper::Actor))
      .and_return(true)
    allow_any_instance_of(described_class).to receive(:claim_letters_service).and_return(provider)
  end

  describe '#perform' do
    context 'when no new decision letter has appeared since the snapshot' do
      it 'logs both signals as negative' do
        expect(Rails.logger).to receive(:info).with(
          'LetterReadyClaimLetterRecheckJob claim letter recheck',
          hash_including(
            message_type: 'ebg.letter_ready.claim_letter_recheck',
            interval_label:,
            new_decision_letter_since_snapshot: false,
            recent_decision_letter_present: false,
            recency_window_days: 7,
            decision_letter_present: true,
            decision_letter_count: 1,
            snapshot_decision_letter_count: 1
          )
        )

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end

      it 'increments the result metric tagged delta:not_found recency:absent' do
        expect(StatsD).to receive(:increment).with(
          'event_bus_gateway.letter_ready_claim_letter_recheck.result',
          tags: EventBusGateway::Constants::DD_TAGS + ['interval:1h', 'delta:not_found', 'recency:absent']
        )

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end

      it 'measures time_since_original tagged by interval and both signals' do
        expect(StatsD).to receive(:measure).with(
          'event_bus_gateway.letter_ready_claim_letter_recheck.time_since_original',
          kind_of(Integer),
          tags: EventBusGateway::Constants::DD_TAGS + ['interval:1h', 'delta:not_found', 'recency:absent']
        )

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end
    end

    context 'when a new (backdated) decision letter has appeared since the snapshot' do
      # A new letter by document-id, but stamped 30 days ago: the delta catches
      # it, the recency window misses it — the exact divergence we want to measure.
      let(:letters) do
        [
          { doc_type: '184', document_id: 'doc-old', type_description: 'Decision Letter',
            received_at: 30.days.ago, upload_date: 30.days.ago },
          { doc_type: '184', document_id: 'doc-new', type_description: 'Decision Letter',
            received_at: 30.days.ago, upload_date: 30.days.ago }
        ]
      end

      it 'logs delta found but recency absent, and tags the metric accordingly' do
        expect(Rails.logger).to receive(:info).with(
          'LetterReadyClaimLetterRecheckJob claim letter recheck',
          hash_including(
            new_decision_letter_since_snapshot: true,
            recent_decision_letter_present: false,
            decision_letter_count: 2
          )
        )
        expect(StatsD).to receive(:increment).with(
          'event_bus_gateway.letter_ready_claim_letter_recheck.result',
          tags: EventBusGateway::Constants::DD_TAGS + ['interval:1h', 'delta:found', 'recency:absent']
        )

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end
    end

    context 'when the same letter is freshly stamped within the recency window' do
      # No set change (delta not_found) but received_at is recent: recency present.
      # Demonstrates the two definitions disagreeing in the other direction.
      let(:letters) do
        [
          { doc_type: '184', document_id: 'doc-old', type_description: 'Decision Letter',
            received_at: 2.days.ago, upload_date: 2.days.ago }
        ]
      end

      it 'logs delta not_found but recency present, and tags the metric accordingly' do
        expect(Rails.logger).to receive(:info).with(
          'LetterReadyClaimLetterRecheckJob claim letter recheck',
          hash_including(
            new_decision_letter_since_snapshot: false,
            recent_decision_letter_present: true
          )
        )
        expect(StatsD).to receive(:increment).with(
          'event_bus_gateway.letter_ready_claim_letter_recheck.result',
          tags: EventBusGateway::Constants::DD_TAGS + ['interval:1h', 'delta:not_found', 'recency:present']
        )

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:event_bus_gateway_claim_letter_recheck, instance_of(Flipper::Actor))
          .and_return(false)
      end

      it 'does not query BD or log anything' do
        expect(provider).not_to receive(:get_letters)
        expect(Rails.logger).not_to receive(:info)
          .with('LetterReadyClaimLetterRecheckJob claim letter recheck', anything)

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end
    end

    context 'when ICN cannot be resolved' do
      let(:mpi_profile) { build(:mpi_profile, icn: nil) }

      it 'returns without querying BD' do
        expect(provider).not_to receive(:get_letters)

        subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
      end
    end

    context 'when the re-check raises' do
      before { allow(provider).to receive(:get_letters).and_raise(StandardError.new('boom')) }

      it 'swallows the error, logs a warning, and increments a failure metric' do
        expect(Rails.logger).to receive(:warn).with(
          'LetterReadyClaimLetterRecheckJob failed to recheck claim letter',
          hash_including(interval_label:, error_class: 'StandardError', error_message: 'boom')
        )
        expect(StatsD).to receive(:increment).with(
          'event_bus_gateway.letter_ready_claim_letter_recheck.failure',
          tags: EventBusGateway::Constants::DD_TAGS + ['interval:1h', 'error:StandardError']
        )

        expect do
          subject.new.perform(participant_id, original_sent_at, interval_label, snapshot)
        end.not_to raise_error
      end
    end

    it 'does not retry (measurement only)' do
      expect(described_class.get_sidekiq_options['retry']).to be(false)
    end
  end
end
