# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::OhMigrationsHelper do
  include ActiveSupport::Testing::TimeHelpers

  # Freeze time in Eastern Time so the spec and helper always share the same "today"
  around do |example|
    Time.use_zone('Eastern Time (US & Canada)') do
      freeze_time do
        example.run
      end
    end
  end

  let(:today) { Date.current }

  it 'returns empty hash for nil' do
    Settings.mhv.oh_facility_checks.oh_migrations_list = nil
    expect(VAOS::OhMigrationsHelper.get_migrations).to eq({})
  end

  it 'calculates future migration dates' do
    go_live_date = today + 7.days
    Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"

    migrations = VAOS::OhMigrationsHelper.get_migrations

    expect(migrations.size).to eq(1)
    expect(migrations).to have_key('123')
    expect(migrations['123'][:migration_days]).to eq(-7)
    expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
    expect(migrations['123'][:migration_date]).to eq(go_live_date)
    expect(migrations['123'][:disable_eligibility]).to be(true)
  end

  it 'calculates past migration dates' do
    go_live_date = today - 60.days
    Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
    migrations = VAOS::OhMigrationsHelper.get_migrations

    expect(migrations.size).to eq(1)
    expect(migrations).to have_key('123')
    expect(migrations['123'][:migration_days]).to eq(60)
    expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
    expect(migrations['123'][:migration_date]).to eq(go_live_date)
    expect(migrations['123'][:disable_eligibility]).to be(false)
  end

  it 'handles multiple migrations' do
    go_live_date1 = today + 7.days
    go_live_date2 = today - 60.days

    oh_migrations_list = "#{go_live_date1}:[123,Test 1],[456,Test 2];#{go_live_date2}:[518,Cleveland VA]"
    Settings.mhv.oh_facility_checks.oh_migrations_list = oh_migrations_list

    migrations = VAOS::OhMigrationsHelper.get_migrations

    expect(migrations.size).to eq(3)
    expect(migrations).to have_key('123')
    expect(migrations['123'][:migration_days]).to eq(-7)
    expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
    expect(migrations['123'][:migration_date]).to eq(go_live_date1)
    expect(migrations['123'][:disable_eligibility]).to be(true)
    expect(migrations).to have_key('456')
    expect(migrations['456'][:migration_days]).to eq(-7)
    expect(migrations['456'][:migration_date]).to be_an_instance_of(Date)
    expect(migrations['456'][:migration_date]).to eq(go_live_date1)
    expect(migrations['456'][:disable_eligibility]).to be(true)
    expect(migrations).to have_key('518')
    expect(migrations['518'][:migration_days]).to eq(60)
    expect(migrations['518'][:migration_date]).to be_an_instance_of(Date)
    expect(migrations['518'][:migration_date]).to eq(go_live_date2)
    expect(migrations['518'][:disable_eligibility]).to be(false)
  end

  context 'disable_eligibility' do
    it 'is false 31 days before migration date' do
      go_live_date = today + 31.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(-31)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:disable_eligibility]).to be(false)
    end

    it 'is true 30 days before migration date' do
      go_live_date = today + 30.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(-30)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:disable_eligibility]).to be(true)
    end

    it 'is true 46 days after migration date' do
      go_live_date = today - 46.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(46)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:disable_eligibility]).to be(true)
    end

    it 'is false 47 days after migration date' do
      go_live_date = today - 47.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(47)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:disable_eligibility]).to be(false)
    end
  end

  context 'cancellation_disabled' do
    it 'is false 11 days before migration date' do
      go_live_date = today + 11.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(-11)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:cancellation_disabled]).to be(false)
    end

    it 'is true 10 days before migration date' do
      go_live_date = today + 10.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(-10)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:cancellation_disabled]).to be(true)
    end

    it 'is true 9 days after migration date' do
      go_live_date = today - 9.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(9)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:cancellation_disabled]).to be(true)
    end

    it 'is false 10 days after migration date' do
      go_live_date = today - 10.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      migrations = VAOS::OhMigrationsHelper.get_migrations

      expect(migrations.size).to eq(1)
      expect(migrations).to have_key('123')
      expect(migrations['123'][:migration_days]).to eq(10)
      expect(migrations['123'][:migration_date]).to be_an_instance_of(Date)
      expect(migrations['123'][:migration_date]).to eq(go_live_date)
      expect(migrations['123'][:cancellation_disabled]).to be(false)
    end
  end

  context 'when mhv_oh_migration_trusted_user_bypass is enabled' do
    let(:user) { build(:user, :loa3) }

    before do
      go_live_date = today + 7.days
      Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass, user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_dark_deploy_appointments, nil).and_return(false)
    end

    it 'returns an empty hash without consulting the migrations list' do
      migrations = VAOS::OhMigrationsHelper.get_migrations(user:)
      expect(migrations).to be_empty
    end

    it 'does not affect calls without a user' do
      migrations = VAOS::OhMigrationsHelper.get_migrations
      expect(migrations).not_to be_empty
    end
  end

  context 'dark deploy (mhv_oh_migration_dark_deploy_appointments)' do
    let(:user) { build(:user, :loa3) }

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass, user).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_dark_deploy_appointments, user).and_return(true)
    end

    context 'disable_eligibility' do
      it 'is true 44 days after migration (within shifted window)' do
        go_live_date = today - 44.days
        Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
        migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

        expect(migrations['123'][:disable_eligibility]).to be(true)
      end

      it 'is false 45 days after migration (shifted cutoff reached)' do
        go_live_date = today - 45.days
        Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
        migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

        expect(migrations['123'][:disable_eligibility]).to be(false)
      end
    end

    context 'cancellation_disabled' do
      it 'is true 4 days after migration (within shifted window)' do
        go_live_date = today - 4.days
        Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
        migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

        expect(migrations['123'][:cancellation_disabled]).to be(true)
      end

      it 'is false 5 days after migration (shifted cutoff reached)' do
        go_live_date = today - 5.days
        Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
        migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

        expect(migrations['123'][:cancellation_disabled]).to be(false)
      end
    end

    context 'when flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_dark_deploy_appointments,
                                                  user).and_return(false)
      end

      context 'cancellation_disabled' do
        it 'uses normal T+10 cutoff (9 days after still disabled)' do
          go_live_date = today - 9.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

          expect(migrations['123'][:cancellation_disabled]).to be(true)
        end

        it 'uses normal T+10 cutoff (10 days after re-enabled)' do
          go_live_date = today - 10.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

          expect(migrations['123'][:cancellation_disabled]).to be(false)
        end
      end

      context 'disable_eligibility' do
        it 'uses normal T+47 cutoff (46 days after still disabled)' do
          go_live_date = today - 46.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

          expect(migrations['123'][:disable_eligibility]).to be(true)
        end

        it 'uses normal T+47 cutoff (47 days after re-enabled)' do
          go_live_date = today - 47.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations(user:)

          expect(migrations['123'][:disable_eligibility]).to be(false)
        end
      end
    end

    context 'when no user is provided' do
      context 'cancellation_disabled' do
        it 'uses normal T+7 cutoff' do
          go_live_date = today - 6.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations

          expect(migrations['123'][:cancellation_disabled]).to be(true)
        end
      end

      context 'disable_eligibility' do
        it 'uses normal T+47 cutoff' do
          go_live_date = today - 46.days
          Settings.mhv.oh_facility_checks.oh_migrations_list = "#{go_live_date}:[123,Test 1]"
          migrations = VAOS::OhMigrationsHelper.get_migrations

          expect(migrations['123'][:disable_eligibility]).to be(true)
        end
      end
    end
  end
end
