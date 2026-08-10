# frozen_string_literal: true

require 'rails_helper'
require 'data_migrations/evss_claims_sequence_reset'

RSpec.describe DataMigrations::EVSSClaimsSequenceReset do
  let(:threshold) { described_class::REQUIRED_CLEARANCE }
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }

  # run makes three select_value calls in order: min(id), last_value (before the
  # reset), then last_value again (after it).
  def stub_connection(min_id:, previous_value: 2_031_834_429, new_value: 1)
    allow(described_class).to receive(:connection).and_return(connection)
    allow(connection).to receive(:select_value).with(/min\(id\)/).and_return(min_id)
    allow(connection).to receive(:select_value).with(/last_value/).and_return(previous_value, new_value)
    allow(connection).to receive(:execute)
  end

  describe 'the clearance guard' do
    context 'when the table is empty' do
      before { stub_connection(min_id: nil) }

      it 'refuses to reset' do
        expect { described_class.run }.to raise_error(/Refusing to reset/)
      end

      it 'does not touch the sequence' do
        expect(connection).not_to receive(:execute)
        suppress(RuntimeError) { described_class.run }
      end
    end

    context 'when the lowest live id is below the threshold' do
      before { stub_connection(min_id: threshold - 1) }

      it 'refuses to reset' do
        expect { described_class.run }.to raise_error(/Refusing to reset/)
      end
    end

    context 'when the lowest live id is exactly at the threshold' do
      before { stub_connection(min_id: threshold) }

      # The guard is a strict `>`, so the threshold itself is not enough clearance.
      it 'refuses to reset' do
        expect { described_class.run }.to raise_error(/Refusing to reset/)
      end
    end

    context 'when the lowest live id is one above the threshold' do
      before { stub_connection(min_id: threshold + 1) }

      it 'resets the sequence' do
        expect(connection).to receive(:execute).with(/ALTER SEQUENCE evss_claims_id_seq RESTART WITH 1/)
        described_class.run
      end
    end

    context 'with a production-like id range' do
      before { stub_connection(min_id: 1_590_858_608) }

      it 'resets the sequence' do
        expect(connection).to receive(:execute).with(/ALTER SEQUENCE evss_claims_id_seq RESTART WITH 1/)
        described_class.run
      end

      it 'returns the before and after values' do
        expect(described_class.run).to eq(
          previous_value: 2_031_834_429, new_value: 1, min_id: 1_590_858_608
        )
      end

      it 'logs the reset' do
        expect(Rails.logger).to receive(:info).with(
          'Reset evss_claims id sequence',
          hash_including(sequence: 'evss_claims_id_seq', previous_value: 2_031_834_429)
        )
        described_class.run
      end
    end
  end

  describe 'against the real database' do
    let!(:claim) { create(:evss_claim, id: 1_500_000_001) }

    let(:original_value) do
      ActiveRecord::Base.connection.select_value('SELECT last_value FROM evss_claims_id_seq')
    end

    before { original_value }

    after do
      ActiveRecord::Base.connection.execute(
        "ALTER SEQUENCE evss_claims_id_seq RESTART WITH #{original_value}"
      )
    end

    it 'issues SQL Postgres accepts and actually moves the sequence' do
      result = described_class.run

      expect(result[:min_id]).to eq(claim.id)
      expect(result[:new_value]).to eq(1)
      expect(
        ActiveRecord::Base.connection.select_value('SELECT last_value FROM evss_claims_id_seq')
      ).to eq(1)
    end
  end
end
