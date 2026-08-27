# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::VSOReloader, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
    allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack)
  end

  describe 'importer' do
    it 'reloads data from pulldown' do
      VCR.use_cassette('veteran/ogc_poa_data') do
        ClaimsApi::VSOReloader.new.perform
        expect(ClaimsApi::Representative.count).to eq 435
        expect(ClaimsApi::Organization.count).to eq 3
        expect(ClaimsApi::Representative.attorneys.count).to eq 241
        expect(ClaimsApi::Representative.veteran_service_officers.count).to eq 152
        expect(ClaimsApi::Representative.claim_agents.count).to eq 42
        expect(ClaimsApi::Representative.where(representative_id: '').count).to eq 0
        expect(ClaimsApi::OrganizationRepresentative.count).to be_positive
      end
    end

    it 'loads attorneys with the poa codes loaded' do
      VCR.use_cassette('veteran/ogc_attorney_data') do
        ClaimsApi::VSOReloader.new.reload_attorneys
        expect(ClaimsApi::Representative.last.poa_codes).to include('9GB')
        expect(ClaimsApi::Representative.where(representative_id: '').count).to eq 0
      end
    end

    it 'loads a claim agent with the poa code' do
      VCR.use_cassette('veteran/ogc_claim_agent_data') do
        ClaimsApi::VSOReloader.new.reload_claim_agents
        expect(ClaimsApi::Representative.last.poa_codes).to include('FDN')
        expect(ClaimsApi::Representative.where(representative_id: '').count).to eq 0
      end
    end

    it 'loads a vso rep with the poa code and creates join records' do
      VCR.use_cassette('veteran/ogc_vso_rep_data') do
        ClaimsApi::VSOReloader.new.reload_vso_reps

        rep = ClaimsApi::Representative.find_by!(first_name: 'Edgar', last_name: 'Anderson')

        expect(rep.poa_codes).to include('091')
        expect(
          ClaimsApi::OrganizationRepresentative
        ).to exist(
          representative_id: rep.representative_id,
          organization_poa: '091'
        )
        expect(ClaimsApi::Representative.where(representative_id: '').count).to eq 0
      end
    end

    context 'existing organizations' do
      let(:org) do
        create(:claims_api_organization, poa: '091', name: 'Testing', phone: '222-555-5555', state: 'ZZ',
                                         city: 'New York')
      end

      it 'only updates name, phone, and state' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          expect(org.name).to eq('Testing')
          expect(org.phone).to eq('222-555-5555')
          expect(org.state).to eq('ZZ')
          expect(org.city).to eq('New York')

          ClaimsApi::VSOReloader.new.reload_vso_reps
          org.reload

          expect(org.name).to eq('African American PTSD Association')
          expect(org.phone).to eq('253-589-0766')
          expect(org.state).to eq('WA')
          expect(org.city).to eq('New York')
        end
      end
    end

    context 'join table acceptance_mode (status quo)' do
      it 'seeds acceptance_mode to no_acceptance for freshly imported orgs with default' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          ClaimsApi::OrganizationRepresentative.where(organization_poa: '091').delete_all
          ClaimsApi::Organization.where(poa: '091').delete_all
          expect(ClaimsApi::Organization.find_by(poa: '091')).to be_nil

          ClaimsApi::VSOReloader.new.reload_vso_reps

          org = ClaimsApi::Organization.find_by!(poa: '091')
          expect(org.can_accept_digital_poa_requests).to be(false)

          join = ClaimsApi::OrganizationRepresentative.find_by!(organization_poa: '091')
          expect(join.acceptance_mode).to eq('no_acceptance')
        end
      end

      it 'seeds acceptance_mode to any_request when org default_new_rep_acceptance_mode is any_request' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          create(:claims_api_organization, poa: '095', default_new_rep_acceptance_mode: 'any_request')

          ClaimsApi::VSOReloader.new.reload_vso_reps

          org_rep = ClaimsApi::OrganizationRepresentative.find_by!(organization_poa: '095')
          expect(org_rep.acceptance_mode).to eq('any_request')
        end
      end

      it 'seeds acceptance_mode but does not overwrite join rows or create duplicates' do
        VCR.use_cassette('veteran/ogc_vso_rep_data', allow_playback_repeats: true) do
          create(:claims_api_organization, poa: '095', default_new_rep_acceptance_mode: 'no_acceptance')

          ClaimsApi::VSOReloader.new.reload_vso_reps
          org_rep = ClaimsApi::OrganizationRepresentative.find_by!(organization_poa: '095')
          expect(org_rep.acceptance_mode).to eq('no_acceptance')

          # Capture the natural key so we can assert no duplicates on rerun
          rep_id = org_rep.representative_id
          expect(
            ClaimsApi::OrganizationRepresentative.where(
              organization_poa: '095',
              representative_id: rep_id
            ).count
          ).to eq(1)

          # Simulate a later change that should be preserved
          org_rep.update!(acceptance_mode: 'self_only')

          # Even if org-wide default changes later, ingestion should NOT clobber the join row
          ClaimsApi::Organization.find_by!(poa: '095')
                                 .update!(default_new_rep_acceptance_mode: 'any_request')

          ClaimsApi::VSOReloader.new.reload_vso_reps

          # Still not overwritten
          expect(org_rep.reload.acceptance_mode).to eq('self_only')

          # Still no duplicates for that same (org, rep)
          expect(
            ClaimsApi::OrganizationRepresentative.where(
              organization_poa: '095',
              representative_id: rep_id
            ).count
          ).to eq(1)
        end
      end
    end

    context 'join table acceptance_mode with default_new_rep_acceptance_mode column' do
      it 'seeds acceptance_mode from default_new_rep_acceptance_mode when set on the org' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          create(:claims_api_organization, poa: '095', default_new_rep_acceptance_mode: 'self_only')

          ClaimsApi::VSOReloader.new.reload_vso_reps

          org_rep = ClaimsApi::OrganizationRepresentative.find_by!(organization_poa: '095')
          expect(org_rep.acceptance_mode).to eq('self_only')
        end
      end

      it 'ignores can_accept_digital_poa_requests and uses default_new_rep_acceptance_mode' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          create(
            :claims_api_organization,
            poa: '095',
            can_accept_digital_poa_requests: true,
            default_new_rep_acceptance_mode: 'no_acceptance'
          )

          ClaimsApi::VSOReloader.new.reload_vso_reps

          org_rep = ClaimsApi::OrganizationRepresentative.find_by!(organization_poa: '095')
          expect(org_rep.acceptance_mode).to eq('no_acceptance')
        end
      end
    end

    context 'join table active/deactivated lifecycle' do
      it 'deactivates stale rep<->org joins for orgs present in the latest feed run' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          # Ensure org is present (it will be imported/updated during reload)
          create(:claims_api_organization, poa: '091')

          # Create a join that should NOT be in the feed
          stale_rep = create(
            :claims_api_representative,
            representative_id: 'STALE001',
            first_name: 'Stale',
            last_name: 'Rep',
            user_types: [ClaimsApi::VSOReloader::USER_TYPE_VSO],
            poa_codes: ['091']
          )

          stale_join = ClaimsApi::OrganizationRepresentative.create!(
            representative_id: stale_rep.representative_id,
            organization_poa: '091',
            acceptance_mode: 'no_acceptance',
            deactivated_at: nil
          )

          ClaimsApi::VSOReloader.new.reload_vso_reps

          expect(stale_join.reload.deactivated_at).to be_present
        end
      end

      it 'reactivates a previously-deactivated join when the pair reappears in the feed' do
        VCR.use_cassette('veteran/ogc_vso_rep_data', allow_playback_repeats: true) do
          # First run creates the join from the feed
          ClaimsApi::VSOReloader.new.reload_vso_reps

          rep = ClaimsApi::Representative.find_by!(first_name: 'Edgar', last_name: 'Anderson')
          join = ClaimsApi::OrganizationRepresentative.find_by!(
            representative_id: rep.representative_id,
            organization_poa: '091'
          )

          # Simulate it being deactivated previously
          join.update!(deactivated_at: 2.days.ago)
          expect(join.reload.deactivated_at).to be_present

          # Second run should reactivate it
          ClaimsApi::VSOReloader.new.reload_vso_reps
          expect(join.reload.deactivated_at).to be_nil
        end
      end

      it 'does not deactivate joins when VSO validation fails (processing is skipped)' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          create(:claims_api_organization, poa: '091')

          rep = create(
            :claims_api_representative,
            representative_id: 'STAYS001',
            first_name: 'Should',
            last_name: 'StayActive',
            user_types: [ClaimsApi::VSOReloader::USER_TYPE_VSO],
            poa_codes: ['091']
          )

          join = ClaimsApi::OrganizationRepresentative.create!(
            representative_id: rep.representative_id,
            organization_poa: '091',
            acceptance_mode: 'no_acceptance',
            deactivated_at: nil
          )

          # Force VSO rep/org validation failure by mocking high initial counts
          allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:fetch_initial_counts).and_return(
            attorneys: 100, claims_agents: 50, vso_representatives: 10_000, vso_organizations: 10_000
          )

          ClaimsApi::VSOReloader.new.reload_vso_reps
          expect(join.reload.deactivated_at).to be_nil
        end
      end
    end

    context 'stale organization removal' do
      it 'deactivates joins for organizations whose POA is not in the vso_data' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          # Create a stale org that won't be in the fixture feed
          create(:claims_api_organization, poa: 'XXX', name: 'Stale Organization')

          # Create an ACTIVE join against that org
          rep = create(
            :claims_api_representative,
            representative_id: 'STALEREP1',
            first_name: 'Stale',
            last_name: 'Join',
            user_types: [ClaimsApi::VSOReloader::USER_TYPE_VSO],
            poa_codes: ['XXX']
          )

          join = ClaimsApi::OrganizationRepresentative.create!(
            representative_id: rep.representative_id,
            organization_poa: 'XXX',
            acceptance_mode: 'no_acceptance',
            deactivated_at: nil
          )

          ClaimsApi::VSOReloader.new.reload_vso_reps

          # org still exists
          expect(ClaimsApi::Organization.find_by(poa: 'XXX')).to be_present
          # but its join is deactivated
          expect(join.reload.deactivated_at).to be_present
        end
      end

      it 'preserves organizations whose POA is still in the vso_data' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          # Create an organization with a POA that IS in the fixture data
          create(:claims_api_organization, poa: '091', name: 'Old Name')

          ClaimsApi::VSOReloader.new.reload_vso_reps

          # Organization should still exist (and be updated)
          expect(ClaimsApi::Organization.find_by(poa: '091')).to be_present
          expect(ClaimsApi::Organization.find_by(poa: '091').name).to eq('African American PTSD Association')
        end
      end

      it 'does not remove stale organizations when validation fails' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          # Create a stale organization
          stale_org = create(:claims_api_organization, poa: 'XXX', name: 'Stale Organization')

          # Force validation failure by mocking high initial counts
          allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:fetch_initial_counts).and_return(
            attorneys: 100, claims_agents: 50, vso_representatives: 10_000, vso_organizations: 10_000
          )

          reloader = ClaimsApi::VSOReloader.new
          reloader.reload_vso_reps

          # Stale organization should NOT be removed because validation failed
          expect(ClaimsApi::Organization.find_by(poa: 'XXX')).to eq(stale_org)
        end
      end
    end

    describe "storing a VSO's middle initial" do
      it 'stores the middle initial if it exists' do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          ClaimsApi::VSOReloader.new.reload_vso_reps

          veteran_rep = ClaimsApi::Representative.find_by!(first_name: 'Edgar', last_name: 'Anderson')
          expect(veteran_rep.middle_initial).to eq('B')
        end
      end

      it 'does not break if a middle initial does not exist' do
        VCR.use_cassette('veteran/ogc_vso_rep_data_no_middle_initial') do
          ClaimsApi::VSOReloader.new.reload_vso_reps

          veteran_rep = ClaimsApi::Representative.find_by!(first_name: 'Edgar', last_name: 'Anderson')
          expect(veteran_rep.middle_initial).to eq('')
        end
      end
    end

    context 'leaving test users alone' do
      before do
        ClaimsApi::Representative.create(
          representative_id: '98765',
          first_name: 'Tamara',
          last_name: 'Ellis',
          poa_codes: %w[067 A1Q 095 074 083 1NY]
        )

        ClaimsApi::Representative.create(
          representative_id: '12345',
          first_name: 'John',
          last_name: 'Doe',
          poa_codes: %w[072 A1H 095 074 083 1NY]
        )
      end

      it 'does not destroy test users' do
        VCR.use_cassette('veteran/ogc_poa_data') do
          ClaimsApi::VSOReloader.new.perform
          expect(ClaimsApi::Representative.where(first_name: 'Tamara', last_name: 'Ellis').count).to eq 1
          expect(ClaimsApi::Representative.where(first_name: 'John', last_name: 'Doe').count).to eq 1
        end
      end
    end

    context 'with a failed connection' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_raise(Faraday::ConnectionFailed,
                                                                               'some message')
      end

      it 'notifies slack' do
        allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack)
        expect_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack)
        ClaimsApi::VSOReloader.new.perform
      end
    end

    context 'with a client error' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_raise(Common::Client::Errors::ClientError)
      end

      it 'notifies slack' do
        allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack)
        expect_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack)
        ClaimsApi::VSOReloader.new.perform
      end
    end

    context 'handling names' do
      before do
        VCR.use_cassette('veteran/ogc_vso_rep_data') do
          ClaimsApi::VSOReloader.new.reload_vso_reps
        end
      end

      context 'with multiple first names' do
        it 'handles it correctly' do
          veteran_rep = ClaimsApi::Representative.find_by!(representative_id: '82390')
          expect(veteran_rep.first_name).to eq('Anna Mae')
          expect(veteran_rep.middle_initial).to eq('B')
        end
      end

      context 'invalid name' do
        it 'handles it correctly' do
          veteran_rep = ClaimsApi::Representative.find_by(representative_id: '82391')
          expect(veteran_rep).to be_nil
        end

        it 'does not delete an existing VSO rep when the feed contains the rep_id but the name is malformed' do
          existing = create(
            :claims_api_representative,
            representative_id: '82391',
            first_name: 'Should',
            last_name: 'Stay',
            user_types: [ClaimsApi::VSOReloader::USER_TYPE_VSO]
          )

          VCR.use_cassette('veteran/ogc_vso_rep_data') do
            ClaimsApi::VSOReloader.new.reload_vso_reps
          end

          rep = ClaimsApi::Representative.find_by(representative_id: '82391')
          expect(rep).to be_present
          expect(rep.id).to eq(existing.id)
        end
      end

      context 'when the last_name has trailing white space' do
        it 'removes the trailing white space' do
          veteran_rep = ClaimsApi::Representative.find_by(representative_id: '8240')
          expect(veteran_rep.last_name).to eq('Good')
        end
      end
    end
  end

  describe '#reload_vso_reps rescue path' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    it 'marks VSO entities failed and re-raises on unexpected error' do
      reloader.send(:ensure_initial_counts)
      allow(reloader).to receive(:fetch_data).and_raise(StandardError, 'OGC blew up')

      expect { reloader.reload_vso_reps }.to raise_error(StandardError, 'OGC blew up')

      log = reloader.instance_variable_get(:@ingestion_log)
      expect(log[:vso_representatives][:status]).to eq(:failed)
      expect(log[:vso_organizations][:status]).to eq(:failed)
      expect(log[:vso_representatives][:error]).to eq('OGC blew up')
    end
  end

  describe '#log_to_slack' do
    let(:reloader) { ClaimsApi::VSOReloader.new }
    let(:slack_client) { instance_double(ClaimsApi::Slack::Client) }

    before do
      allow_any_instance_of(ClaimsApi::VSOReloader).to receive(:log_to_slack).and_call_original
      allow(ClaimsApi::Slack::Client).to receive(:new).and_return(slack_client)
    end

    it 'sends message via ClaimsApi::Slack::Client when webhook is configured' do
      allow(Settings.claims_api.slack).to receive(:webhook_url).and_return('https://hooks.example.com')

      expect(slack_client).to receive(:notify).with('test message')
      reloader.send(:log_to_slack, 'test message')
    end

    it 'does nothing when webhook_url is blank' do
      allow(Settings.claims_api.slack).to receive(:webhook_url).and_return('')

      expect(ClaimsApi::Slack::Client).not_to receive(:new)
      reloader.send(:log_to_slack, 'test message')
    end
  end

  describe '#calculate_vso_counts' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    it 'counts orgs using normalized POA codes' do
      data = [
        { 'Representative' => 'X, Y', 'Registration Num' => '1', 'POA' => '091' },
        { 'Representative' => 'X, Y', 'Registration Num' => '2', 'POA' => '091 ' },
        { 'Representative' => 'X, Y', 'Registration Num' => '3', 'POA' => '091-' },
        { 'Representative' => 'X, Y', 'Registration Num' => '4', 'POA' => nil }
      ]

      counts = reloader.send(:calculate_vso_counts, data)
      expect(counts[:orgs]).to eq(1)
    end
  end

  describe 'dedup by representative_id (attorney)' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    it 'does not create a duplicate when names vary' do
      ClaimsApi::Representative.create!(
        representative_id: 'A123',
        first_name: 'Sarah',
        last_name: 'Whitman',
        user_types: ['attorney'],
        poa_codes: ['XYZ']
      )

      payload = {
        'Registration Num' => 'A123',
        'First Name' => 'Sara',
        'Last Name' => 'Whittman',
        'Phone' => '202-555-0101',
        'POA Code' => '9GB'
      }

      expect do
        reloader.send(:find_or_create_attorneys, payload)
      end.not_to change(ClaimsApi::Representative, :count)

      rep = ClaimsApi::Representative.find_by(representative_id: 'A123')
      expect(rep.first_name).to eq('Sarah')
      expect(rep.last_name).to  eq('Whitman')
      expect(rep.user_types).to include('attorney')
      expect(rep.poa_codes).to include('9GB')
    end
  end

  describe 'initial attribute population for new reps' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    it 'fills names/contacts for a NEW attorney record' do
      payload = {
        'Registration Num' => 'A999',
        'First Name' => 'June',
        'Last Name' => 'Park',
        'Phone' => '202-555-0123',
        'POA Code' => 'ABC'
      }

      expect do
        reloader.send(:find_or_create_attorneys, payload)
      end.to change(ClaimsApi::Representative, :count).by(1)

      rep = ClaimsApi::Representative.find_by!(representative_id: 'A999')
      expect(rep.first_name).to eq('June')
      expect(rep.last_name).to  eq('Park')
      expect(rep.phone).to      eq('202-555-0123')
      expect(rep.user_types).to include('attorney')
      expect(rep.poa_codes).to  include('ABC')
    end

    it 'fills names/contacts for a NEW claim agent record' do
      payload = {
        'Registration Num' => 'C321',
        'First Name' => 'Leo',
        'Last Name' => 'Ng',
        'Phone' => '202-555-0144',
        'POA Code' => 'FDN'
      }

      expect do
        reloader.send(:find_or_create_claim_agents, payload)
      end.to change(ClaimsApi::Representative, :count).by(1)

      rep = ClaimsApi::Representative.find_by!(representative_id: 'C321')
      expect(rep.first_name).to eq('Leo')
      expect(rep.last_name).to  eq('Ng')
      expect(rep.phone).to      eq('202-555-0144')
      expect(rep.user_types).to include('claim_agents')
      expect(rep.poa_codes).to  include('FDN')
    end
  end

  describe 'set semantics for array attributes' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    it 'does not duplicate user_types or poa_codes when reprocessing' do
      rep = ClaimsApi::Representative.create!(
        representative_id: 'S111',
        first_name: 'Sam',
        last_name: 'Hill',
        user_types: ['attorney'],
        poa_codes: ['XYZ']
      )

      payload = {
        'Registration Num' => 'S111',
        'First Name' => 'Samuel',
        'Last Name' => 'Hill',
        'Phone' => '202-555-0000',
        'POA Code' => 'XYZ'
      }

      expect do
        reloader.send(:find_or_create_attorneys, payload)
      end.not_to change(ClaimsApi::Representative, :count)

      rep.reload
      expect(rep.user_types.count { |t| t == 'attorney' }).to eq 1
      expect(rep.poa_codes.count  { |p| p == 'XYZ' }).to eq 1
    end
  end

  describe 'validation logic' do
    let(:reloader) { ClaimsApi::VSOReloader.new }

    before do
      # Create existing representatives and organizations with unique IDs
      100.times { |i| create(:claims_api_representative, representative_id: "ATT#{i}", user_types: ['attorney']) }
      50.times { |i| create(:claims_api_representative, representative_id: "CA#{i}", user_types: ['claim_agents']) }
      75.times do |i|
        create(:claims_api_representative, representative_id: "VSO#{i}", user_types: ['veteran_service_officer'])
      end
      create_list(:claims_api_organization, 20)
    end

    describe '#valid_count?' do
      before do
        reloader.send(:ensure_initial_counts)
        allow(reloader).to receive(:log_to_slack)
      end

      it 'allows updates when count increases' do
        expect(reloader.send(:valid_count?, :attorneys, 110)).to be true
      end

      it 'allows updates when count stays the same' do
        expect(reloader.send(:valid_count?, :attorneys, 100)).to be true
      end

      it 'blocks updates when decrease exceeds threshold' do
        # 75 attorneys is a 25% decrease, which exceeds 20% threshold
        expect(reloader.send(:valid_count?, :attorneys, 75)).to be false
      end

      it 'notifies slack when the decrease exceeds threshold' do
        allow(reloader).to receive(:notify_threshold_exceeded)
        expect(reloader).to receive(:notify_threshold_exceeded).with(
          :attorneys, 100, 75, anything, anything
        )
        reloader.send(:valid_count?, :attorneys, 75)
      end

      it 'allows updates when decrease is within threshold' do
        # 85 attorneys is a 15% decrease, which is within 20% threshold
        expect(reloader.send(:valid_count?, :attorneys, 85)).to be true
      end

      context 'with no previous count' do
        it 'allows any count when no history exists' do
          # Create a fresh reloader instance with mocked initial counts
          fresh_reloader = ClaimsApi::VSOReloader.new
          allow(fresh_reloader).to receive(:fetch_initial_counts).and_return({
                                                                               attorneys: 0,
                                                                               claims_agents: 0,
                                                                               vso_representatives: 0,
                                                                               vso_organizations: 0
                                                                             })
          fresh_reloader.send(:ensure_initial_counts)

          expect(fresh_reloader.send(:valid_count?, :attorneys, 50)).to be true
        end
      end
    end

    describe '#notify_threshold_exceeded' do
      before do
        reloader.send(:ensure_initial_counts)
        allow(reloader).to receive(:log_to_slack)
      end

      it 'sends a notification to Slack' do
        allow(reloader).to receive(:log_to_slack)

        expect(reloader).to receive(:log_to_slack).with(
          include('Attorneys count decreased beyond threshold!')
        )

        reloader.send(:notify_threshold_exceeded, :attorneys, 100, 70, 0.30, 0.20)
      end

      it 'logs warning' do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'vso_reloader',
          hash_including(level: :warn, previous_count: 100, new_count: 70, decrease_percentage: 0.30)
        )
        reloader.send(:notify_threshold_exceeded, :attorneys, 100, 70, 0.30, 0.20)
      end
    end

    describe '#complete_ingestion_log' do
      before do
        reloader.send(:setup_ingestion)
      end

      it 'sends a Slack summary with per-entity status' do
        reloader.instance_variable_get(:@ingestion_log)[:attorneys].merge!(status: :success, after: 241)
        reloader.instance_variable_get(:@ingestion_log)[:claims_agents].merge!(status: :success, after: 42)
        reloader.instance_variable_get(:@ingestion_log)[:vso_representatives].merge!(status: :skipped,
                                                                                     reason: 'threshold exceeded')
        reloader.instance_variable_get(:@ingestion_log)[:vso_organizations].merge!(status: :skipped,
                                                                                   reason: 'threshold exceeded')

        expect(reloader).to receive(:log_to_slack).with(
          include('completed', 'Attorneys: 241', 'SKIPPED')
        )
        reloader.send(:complete_ingestion_log)
      end

      it 'reports FAILED when any entity failed' do
        reloader.instance_variable_get(:@ingestion_log)[:attorneys].merge!(status: :failed, error: 'boom')

        expect(reloader).to receive(:log_to_slack).with(include('FAILED'))
        reloader.send(:complete_ingestion_log)
      end
    end

    describe 'full perform cycle with validation' do
      context 'when all counts pass validation' do
        it 'updates all representative types and sends summary' do
          # Clear seeded data so initial counts don't trigger threshold failures against VCR data
          ClaimsApi::Representative.delete_all
          ClaimsApi::Organization.delete_all

          VCR.use_cassette('veteran/ogc_poa_data') do
            allow(reloader).to receive(:log_to_slack)

            reloader.perform

            expect(ClaimsApi::Representative.attorneys.count).to be_positive
            expect(ClaimsApi::Representative.claim_agents.count).to be_positive
            expect(ClaimsApi::Representative.veteran_service_officers.count).to be_positive

            run_status = reloader.instance_variable_get(:@ingestion_log)
            expect(run_status[:attorneys][:status]).to eq(:success)
            expect(run_status[:claims_agents][:status]).to eq(:success)
            expect(run_status[:vso_representatives][:status]).to eq(:success)
            expect(run_status[:vso_organizations][:status]).to eq(:success)
          end
        end
      end

      context 'when some counts fail validation' do
        it 'marks skipped types in run_status' do
          VCR.use_cassette('veteran/ogc_poa_data') do
            allow(reloader).to receive(:log_to_slack)
            # Force attorneys to fail threshold check
            allow(reloader).to receive(:fetch_initial_counts).and_return(
              attorneys: 10_000, claims_agents: 50, vso_representatives: 75, vso_organizations: 20
            )
            reloader.send(:ensure_initial_counts)

            reloader.perform

            run_status = reloader.instance_variable_get(:@ingestion_log)
            expect(run_status[:attorneys][:status]).to eq(:skipped)
            expect(run_status[:claims_agents][:status]).to eq(:success)
          end
        end
      end

      context 'when VSO representative or organization count fails validation' do
        it 'skips processing both VSO reps and orgs to maintain data integrity' do
          VCR.use_cassette('veteran/ogc_poa_data') do
            allow(reloader).to receive(:log_to_slack)
            # Force VSO counts to fail threshold check
            allow(reloader).to receive(:fetch_initial_counts).and_return(
              attorneys: 100, claims_agents: 50, vso_representatives: 10_000, vso_organizations: 10_000
            )
            reloader.send(:ensure_initial_counts)

            initial_vso_rep_count = ClaimsApi::Representative
                                    .where("'#{ClaimsApi::VSOReloader::USER_TYPE_VSO}' = ANY(user_types)")
                                    .count
            initial_org_count = ClaimsApi::Organization.count

            reloader.perform

            # Both VSO reps and orgs should remain unchanged
            expect(ClaimsApi::Representative
                     .where("'#{ClaimsApi::VSOReloader::USER_TYPE_VSO}' = ANY(user_types)")
                     .count).to eq initial_vso_rep_count
            expect(ClaimsApi::Organization.count).to eq initial_org_count

            run_status = reloader.instance_variable_get(:@ingestion_log)
            expect(run_status[:vso_representatives][:status]).to eq(:skipped)
            expect(run_status[:vso_organizations][:status]).to eq(:skipped)
          end
        end
      end
    end
  end
end
