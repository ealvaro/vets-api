# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::Form21aPilotGate do
  include ActiveSupport::Testing::TimeHelpers

  subject(:gate) { described_class }

  let(:user) { create(:representative_user) }
  let(:monthly_limit) { 2 }

  before { stub_const("#{described_class}::MONTHLY_LIMIT", monthly_limit) }

  def admission_count
    AccreditedRepresentativePortal::Form21aPilotAdmission.count
  end

  describe '.status' do
    it 'reports an open slot count without writing anything' do
      expect { @result = gate.status(user) }.not_to(change { admission_count })

      expect(@result).to eq(
        state: 'open',
        admissions_this_month: 0,
        monthly_limit: 2,
        remaining: 2
      )
    end

    context 'when this month is at capacity' do
      before { monthly_limit.times { create(:form21a_pilot_admission) } }

      it 'reports closed with no remaining slots for a new user' do
        expect(gate.status(user)).to eq(
          state: 'closed',
          admissions_this_month: 2,
          monthly_limit: 2,
          remaining: 0
        )
      end

      it 'still reports open for an already-admitted user' do
        create(:form21a_pilot_admission, user_account: user.user_account)

        result = gate.status(user)
        expect(result[:state]).to eq('open')
      end
    end
  end

  describe '.admit!' do
    it 'creates an admission and returns :open when a slot is available' do
      expect { @result = gate.admit!(user) }.to change { admission_count }.by(1)
      expect(@result).to eq(:open)
    end

    it 'is idempotent for an already-admitted user' do
      create(:form21a_pilot_admission, user_account: user.user_account)

      expect { @result = gate.admit!(user) }.not_to(change { admission_count })
      expect(@result).to eq(:open)
    end

    it 'returns :closed without writing when the month is at capacity' do
      monthly_limit.times { create(:form21a_pilot_admission) }

      expect { @result = gate.admit!(user) }.not_to(change { admission_count })
      expect(@result).to eq(:closed)
    end

    it 'admits an already-admitted user even when the month is at capacity' do
      create(:form21a_pilot_admission, user_account: user.user_account)
      (monthly_limit - 1).times { create(:form21a_pilot_admission) }

      expect { @result = gate.admit!(user) }.not_to(change { admission_count })
      expect(@result).to eq(:open)
    end

    describe 'StatsD metrics' do
      before { allow(StatsD).to receive(:increment) }

      it 'emits the admission counter tagged outcome:open on a new admission' do
        gate.admit!(user)

        expect(StatsD).to have_received(:increment)
          .with('api.form21a.pilot.admission', tags: ['outcome:open'])
      end

      it 'does not emit outcome:open when the surrounding transaction rolls back' do
        # outcome:open is deferred to after_commit, so a caller rollback (e.g. the
        # in-progress-form save failing after the slot is consumed) must not over-count it.
        ActiveRecord::Base.transaction do
          gate.admit!(user)
          raise ActiveRecord::Rollback
        end

        expect(StatsD).not_to have_received(:increment)
          .with('api.form21a.pilot.admission', any_args)
      end

      it 'emits the admission counter tagged outcome:closed when at capacity' do
        monthly_limit.times { create(:form21a_pilot_admission) }

        gate.admit!(user)

        expect(StatsD).to have_received(:increment)
          .with('api.form21a.pilot.admission', tags: ['outcome:closed'])
      end

      it 'emits nothing for an idempotent already-admitted user' do
        create(:form21a_pilot_admission, user_account: user.user_account)

        gate.admit!(user)

        expect(StatsD).not_to have_received(:increment)
          .with('api.form21a.pilot.admission', any_args)
      end
    end
  end

  describe '.admitted?' do
    it 'is true only after the user has an admission' do
      expect(gate.admitted?(user)).to be(false)
      create(:form21a_pilot_admission, user_account: user.user_account)
      expect(gate.admitted?(user)).to be(true)
    end
  end

  describe 'monthly window in the configured timezone' do
    it 'counts admissions by Eastern calendar month, not UTC' do
      # 2024-01-01 02:00 UTC is still 2023-12-31 21:00 Eastern, so this admission
      # belongs to the December bucket, not January.
      travel_to(Time.utc(2024, 1, 1, 2, 0, 0)) do
        create(:form21a_pilot_admission, created_at: Time.current)
      end

      # 2024-01-01 12:00 UTC is 2024-01-01 07:00 Eastern -> the January bucket is empty.
      travel_to(Time.utc(2024, 1, 1, 12, 0, 0)) do
        expect(gate.status(user)[:admissions_this_month]).to eq(0)
      end

      # Back inside December Eastern -> the bucket holds the one admission.
      travel_to(Time.utc(2023, 12, 15, 12, 0, 0)) do
        create(:form21a_pilot_admission, created_at: Time.current)
        expect(gate.status(user)[:admissions_this_month]).to eq(2)
      end
    end
  end
end
