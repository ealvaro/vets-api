# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::ProviderSearchService do
  let(:user) { build(:user, :vaos) }
  let(:residential_address) do
    double('Address', latitude: 28.08, longitude: -80.60)
  end
  let(:vet360_contact_info) { double('Vet360ContactInfo', residential_address:) }
  let(:service) { described_class.new(user) }

  let(:referral) do
    double('Referral',
           category_of_care: 'UROLOGY',
           provider_npi: '91560381x')
  end

  let(:lighthouse_facility) do
    double(
      'Facility',
      id: 'vha_983',
      unique_id: '983',
      name: 'Cheyenne VA Medical Center',
      address: {
        'physical' => {
          'address1' => '2360 E Pershing Blvd', 'city' => 'Cheyenne',
          'state' => 'WY', 'zip' => '82001'
        }
      },
      phone: { 'main' => '307-778-7550', 'healthConnect' => '307-778-7550' },
      lat: 28.10,
      long: -80.62,
      facility_type: 'va_health_facility',
      services: { 'health' => [{ 'serviceId' => 'urology' }] }
    )
  end

  let(:eps_provider_hash) do
    {
      id: '9mN718pH',
      name: 'Dr. Bones @ Melbourne Medical',
      individual_providers: [{ name: 'Dr. Bones', npi: '91560381x' }],
      location: {
        address: '1105 Palmetto Ave, Melbourne, FL, 32901, US',
        latitude: 28.08061,
        longitude: -80.60322
      },
      network_ids: ['network-1'],
      specialties: [{ id: '208800000X', name: 'Urology' }],
      features: { is_digital: true, direct_booking: { is_enabled: true } }
    }
  end

  let(:urology_clinic) do
    OpenStruct.new(
      id: '455',
      station_id: '983',
      service_name: 'CHY UROLOGY',
      physical_location: nil
    )
  end

  let(:systems_service) { instance_double(VAOS::V2::SystemsService) }
  let(:eligibility_service) { instance_double(VAOS::V2::Unified::EligibilityService) }

  # RSpec verifying doubles reject +unique_id=+ unless stubbed; real Lighthouse
  # facility objects accept assignment. Mirror that so staging translation specs
  # mutate IDs like production.
  def lighthouse_facility_double(unique_id:, id:, **attrs)
    state = { unique_id: }
    double('Facility', **attrs).tap do |f|
      allow(f).to receive(:unique_id) { state[:unique_id] }
      allow(f).to receive(:unique_id=) { |v| state[:unique_id] = v }
      allow(f).to receive(:id).and_return(id)
    end
  end

  before do
    allow(user).to receive(:vet360_contact_info).and_return(vet360_contact_info)
  end

  describe '#search' do
    let(:lighthouse_client) { instance_double(FacilitiesApi::V2::Lighthouse::Client) }
    let(:eps_provider_service) { instance_double(Eps::ProviderService) }

    before do
      allow(FacilitiesApi::V2::Lighthouse::Client).to receive(:new).and_return(lighthouse_client)
      allow(Eps::ProviderService).to receive(:new).and_return(eps_provider_service)
      allow(VAOS::V2::SystemsService).to receive(:new).with(user).and_return(systems_service)
      allow(VAOS::V2::Unified::EligibilityService).to receive(:new).with(user).and_return(eligibility_service)
      allow(eligibility_service).to receive(:check_eligibility).and_return({ direct_eligible: true })

      allow(lighthouse_client).to receive(:get_facilities).and_return([lighthouse_facility])
      allow(eps_provider_service).to receive(:search_by_location).and_return([eps_provider_hash])
      allow(systems_service).to receive(:get_facility_clinics).and_return([urology_clinic])

      # Default the regex post-filter OFF for the structural tests that aren't
      # exercising it (otherwise PC default patterns drop the UROLOGY EPS
      # provider). Tests under the +operational toggles+ describe block stub
      # this explicitly to true.
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_name_filter, user).and_return(false)
      # Default the pilot kill-switch OFF (== PC-only) to match the production
      # default. Tests that want CCRA_TO_TARGETS entries to win override this.
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_non_primary_care, user).and_return(false)
    end

    it 'returns a combined list of VA clinics and EPS providers' do
      results = service.search(referral:)

      expect(results.size).to eq(2)
      provider_types = results.map(&:provider_type)
      expect(provider_types).to include('va', 'eps')
      va = results.find { |p| p.provider_type == 'va' }
      expect(va.id).to eq('455')
      expect(va.location_id).to eq('983')
    end

    it 'pins the referral matched provider at the top' do
      results = service.search(referral:)

      first = results.first
      expect(first.provider_type).to eq('eps')
      expect(first.npi).to eq('91560381x')
    end

    it 'computes distance for VA providers using haversine formula' do
      results = service.search(referral:)
      va_provider = results.find { |p| p.provider_type == 'va' }

      expect(va_provider.distance_from_user).to be_a(Float)
      expect(va_provider.distance_from_user).to be_positive
    end

    it 'sorts remaining providers by distance' do
      other_eps = eps_provider_hash.merge(
        id: 'other123',
        individual_providers: [{ name: 'Other', npi: '9999999' }],
        location: {
          address: '500 Far Ave, Orlando, FL, 32801, US',
          latitude: 28.5383,
          longitude: -81.3792
        }
      )
      allow(eps_provider_service).to receive(:search_by_location).and_return([eps_provider_hash, other_eps])

      results = service.search(referral:)

      expect(results.first.npi).to eq('91560381x')
      remaining = results.drop(1)
      distances = remaining.map(&:distance_from_user)
      expect(distances).to eq(distances.sort)
      expect(remaining.map(&:provider_type)).to eq(%w[va eps])
    end

    it 'calls Lighthouse with correct parameters' do
      service.search(referral:, radius: 30)

      expect(lighthouse_client).to have_received(:get_facilities).with(
        hash_including(lat: 28.08, long: -80.60, radius: 30, type: 'health')
      )
    end

    it 'calls EPS with PRIMARY CARE NUCC IDs when pilot kill-switch overrides a non-PC category' do
      # UROLOGY *is* in CcraCategoryMapper now (with NUCC 208800000X), but the
      # +va_online_scheduling_unified_non_primary_care+ pilot kill-switch is
      # OFF by default, so the mapper overrides UROLOGY back to PC NUCC IDs.
      service.search(referral:, radius: 30)

      expect(eps_provider_service).to have_received(:search_by_location).with(
        latitude: 28.08,
        longitude: -80.60,
        radius: 30,
        specialty_ids: %w[207Q00000X 207R00000X 208D00000X]
      )
    end

    it 'calls EPS with NUCC specialty IDs for mapped CCRA categories (PRIMARY CARE)' do
      primary_care_referral = double(
        'Referral',
        category_of_care: 'PRIMARY CARE',
        provider_npi: '91560381x'
      )

      service.search(referral: primary_care_referral, radius: 30)

      expect(eps_provider_service).to have_received(:search_by_location).with(
        latitude: 28.08,
        longitude: -80.60,
        radius: 30,
        specialty_ids: %w[207Q00000X 207R00000X 208D00000X]
      )
    end

    it 'fetches VAOS clinics with PC clinical_service when pilot kill-switch is off' do
      service.search(referral:)

      # Pilot flag default-off -> UROLOGY's mapped vaos_service_type is
      # overridden to 'primaryCare'. (Even without the pilot flag, UROLOGY is
      # not in VAOS::SCHEDULABLE_SERVICE_TYPES so this entry intentionally
      # leaves vaos_service_type unset and inherits PC.)
      expect(systems_service).to have_received(:get_facility_clinics).with(
        location_id: '983',
        clinical_service: 'primaryCare'
      )
    end

    it 'passes mapped clinical service when category_of_care maps to a VAOS type' do
      primary_care_referral = double(
        'Referral',
        category_of_care: 'PRIMARY CARE',
        provider_npi: '91560381x'
      )

      service.search(referral: primary_care_referral)

      expect(systems_service).to have_received(:get_facility_clinics).with(
        location_id: '983',
        clinical_service: 'primaryCare'
      )
    end

    it 'raises error when user has no residential address' do
      allow(vet360_contact_info).to receive(:residential_address).and_return(nil)

      expect { service.search(referral:) }.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'raises error when user address has no coordinates' do
      allow(residential_address).to receive(:latitude).and_return(nil)

      expect { service.search(referral:) }.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'returns only EPS providers when Lighthouse fails' do
      allow(lighthouse_client).to receive(:get_facilities).and_raise(StandardError.new('timeout'))

      results = service.search(referral:)

      expect(results.size).to eq(1)
      expect(results.first.provider_type).to eq('eps')
    end

    it 'returns only VA providers when EPS fails' do
      allow(eps_provider_service).to receive(:search_by_location).and_raise(StandardError.new('timeout'))

      results = service.search(referral:)

      expect(results.size).to eq(1)
      expect(results.first.provider_type).to eq('va')
    end

    it 'still runs PC eligibility filtering when pilot kill-switch overrides a non-PC category' do
      # UROLOGY referral + pilot flag default-off -> mapper returns PC defaults,
      # so eligibility filtering runs against the PC service type rather than
      # being skipped entirely.
      non_matching_facility = double(
        'Facility',
        id: 'vha_984', unique_id: '984', name: 'Other VA',
        address: nil, phone: nil, lat: 28.12, long: -80.65,
        facility_type: 'va_health_facility',
        services: { 'health' => [{ 'serviceId' => 'podiatry' }] }
      )
      allow(lighthouse_client).to receive(:get_facilities).and_return(
        [lighthouse_facility, non_matching_facility]
      )

      service.search(referral:)

      expect(eligibility_service).to have_received(:check_eligibility).twice.with(
        hash_including(vaos_service_type: 'primaryCare')
      )
    end

    it 'excludes VA facilities that fail direct-scheduling eligibility when category maps to VAOS' do
      non_matching_facility = double(
        'Facility',
        id: 'vha_984', unique_id: '984', name: 'Other VA',
        address: nil, phone: nil, lat: 28.12, long: -80.65,
        facility_type: 'va_health_facility',
        services: { 'health' => [{ 'serviceId' => 'primaryCare' }] }
      )
      allow(lighthouse_client).to receive(:get_facilities).and_return(
        [lighthouse_facility, non_matching_facility]
      )
      primary_care_referral = double(
        'Referral',
        category_of_care: 'PRIMARY CARE',
        provider_npi: '91560381x'
      )

      allow(eligibility_service).to receive(:check_eligibility) do |facility_id:, vaos_service_type:|
        # ProviderSearchService passes the already-mapped VAOS service type
        # directly under the +vaos_service_type:+ keyword (not a Lighthouse
        # +category_of_care+) so the eligibility service can hand it straight
        # to PatientsService without a second mapping step.
        expect(vaos_service_type).to eq('primaryCare')
        {
          facility_id:,
          vaos_service_type:,
          direct_eligible: facility_id == '983'
        }
      end

      results = service.search(referral: primary_care_referral)

      va_providers = results.select { |p| p.provider_type == 'va' }
      expect(va_providers.map(&:location_id)).to eq(['983'])
      expect(systems_service).to have_received(:get_facility_clinics).once
    end

    it 'returns no VA providers when get_facility_clinics returns no clinics' do
      allow(systems_service).to receive(:get_facility_clinics).and_return([])

      results = service.search(referral:)

      expect(results.map(&:provider_type)).to eq(['eps'])
    end

    it 'uses the default 25-mile radius' do
      service.search(referral:)

      expect(lighthouse_client).to have_received(:get_facilities).with(
        hash_including(radius: 25)
      )
    end

    describe 'staging facility-id translation' do
      # Lighthouse hands back real-world station IDs (442 = Cheyenne, 552 =
      # Dayton). Downstream VAOS staging calls need the staging vocabulary
      # (983, 984) to find the patient's panel in lower envs. The translator
      # is gated on +Settings.vsp_environment == 'production'+ so production
      # is a pure passthrough. Translation happens exactly once per facility,
      # at the Lighthouse boundary -- these tests assert that every VAOS-side
      # consumer (eligibility, clinics, VAProvider.location_id) sees the same
      # translated ID, not independently re-translated copies.
      let(:real_cheyenne_facility) do
        lighthouse_facility_double(
          unique_id: '442',
          id: 'vha_442',
          name: 'Cheyenne VA Medical Center',
          address: { 'physical' => { 'address1' => '2360 E Pershing Blvd',
                                     'city' => 'Cheyenne', 'state' => 'WY', 'zip' => '82001' } },
          phone: { 'main' => '307-778-7550', 'healthConnect' => '307-778-7550' },
          lat: 41.1456, long: -104.7892,
          facility_type: 'va_health_facility',
          services: { 'health' => [{ 'serviceId' => 'primaryCare' }] }
        )
      end

      let(:real_substation_facility) do
        lighthouse_facility_double(
          unique_id: '442GC',
          id: 'vha_442GC',
          name: 'Fort Collins VA Clinic',
          address: nil, phone: nil, lat: 40.5853, long: -105.0844,
          facility_type: 'va_health_facility',
          services: { 'health' => [{ 'serviceId' => 'primaryCare' }] }
        )
      end

      let(:unmapped_facility) do
        lighthouse_facility_double(
          unique_id: '668',
          id: 'vha_668',
          name: 'Spokane VA Medical Center',
          address: nil, phone: nil, lat: 47.6588, long: -117.4260,
          facility_type: 'va_health_facility',
          services: { 'health' => [{ 'serviceId' => 'primaryCare' }] }
        )
      end

      let(:primary_care_referral) do
        double('Referral', category_of_care: 'PRIMARY CARE', provider_npi: '91560381x')
      end

      before do
        allow(eligibility_service).to receive(:check_eligibility)
          .and_return({ direct_eligible: true })
      end

      context 'in non-production environments' do
        before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

        it 'sends the staging-translated id to eligibility for the parent station' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([real_cheyenne_facility])

          service.search(referral: primary_care_referral)

          expect(eligibility_service).to have_received(:check_eligibility)
            .with(facility_id: '983', vaos_service_type: 'primaryCare')
        end

        it 'sends the staging-translated id to clinic fetch for the parent station' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([real_cheyenne_facility])

          service.search(referral: primary_care_referral)

          expect(systems_service).to have_received(:get_facility_clinics)
            .with(location_id: '983', clinical_service: 'primaryCare')
        end

        it 'stamps the staging id on the resulting VAProvider' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([real_cheyenne_facility])

          results = service.search(referral: primary_care_referral)
          va = results.find { |p| p.provider_type == 'va' }

          expect(va.location_id).to eq('983')
        end

        it 'preserves sub-station suffixes when translating (442GC -> 983GC)' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([real_substation_facility])

          service.search(referral: primary_care_referral)

          expect(eligibility_service).to have_received(:check_eligibility)
            .with(facility_id: '983GC', vaos_service_type: 'primaryCare')
          expect(systems_service).to have_received(:get_facility_clinics)
            .with(location_id: '983GC', clinical_service: 'primaryCare')
        end

        it 'leaves unmapped Lighthouse station IDs unchanged' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([unmapped_facility])

          service.search(referral: primary_care_referral)

          expect(eligibility_service).to have_received(:check_eligibility)
            .with(facility_id: '668', vaos_service_type: 'primaryCare')
          expect(systems_service).to have_received(:get_facility_clinics)
            .with(location_id: '668', clinical_service: 'primaryCare')
        end

        it 'translates each Lighthouse facility exactly once at the boundary' do
          # Locks in the "translate once at the edge" design: for N Lighthouse
          # facilities we expect N calls to +to_staging+ in this service,
          # regardless of how many downstream VAOS consumers (eligibility,
          # clinic fetch, VAProvider stamp) read the translated id.
          allow(lighthouse_client).to receive(:get_facilities)
            .and_return([real_cheyenne_facility, real_substation_facility])
          allow(VAOS::V2::Unified::FacilityIdTranslator).to receive(:to_staging).and_call_original

          service.search(referral: primary_care_referral)

          expect(VAOS::V2::Unified::FacilityIdTranslator).to have_received(:to_staging)
            .with('442').once
          expect(VAOS::V2::Unified::FacilityIdTranslator).to have_received(:to_staging)
            .with('442GC').once
        end
      end

      context 'in production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('production') }

        it 'is a pure no-op: real ids flow straight through to VAOS calls' do
          allow(lighthouse_client).to receive(:get_facilities).and_return([real_cheyenne_facility])

          results = service.search(referral: primary_care_referral)
          va = results.find { |p| p.provider_type == 'va' }

          expect(eligibility_service).to have_received(:check_eligibility)
            .with(facility_id: '442', vaos_service_type: 'primaryCare')
          expect(systems_service).to have_received(:get_facility_clinics)
            .with(location_id: '442', clinical_service: 'primaryCare')
          expect(va.location_id).to eq('442')
        end
      end
    end

    describe 'operational toggles' do
      let(:primary_care_referral) do
        double('Referral', category_of_care: 'PRIMARY CARE', provider_npi: '91560381x')
      end

      let(:matching_eps_provider) do
        {
          id: 'match-1',
          name: 'Dr. Jones @ FHA Primary Care Clinic',
          individual_providers: [{ name: 'Dr. Jones', npi: '99999999' }],
          location: { name: 'FHA Primary Care Clinic', address: '1 Main St',
                      latitude: 28.08, longitude: -80.60 },
          network_ids: ['network-1'],
          specialties: [{ id: '207Q00000X', name: 'Family Medicine' }],
          features: { is_digital: true, direct_booking: { is_enabled: true } }
        }
      end

      let(:non_matching_eps_provider) do
        {
          id: 'nomatch-1',
          name: 'Dr. Bones @ Orthopaedic Center',
          individual_providers: [{ name: 'Dr. Bones', npi: '77777777' }],
          location: { name: 'Orthopaedic Center', address: '2 Main St',
                      latitude: 28.08, longitude: -80.60 },
          network_ids: ['network-1'],
          specialties: [{ id: '207XX0004X', name: 'Orthopaedic Surgery' }],
          features: { is_digital: true, direct_booking: { is_enabled: true } }
        }
      end

      before do
        allow(eps_provider_service).to receive(:search_by_location)
          .and_return([matching_eps_provider, non_matching_eps_provider])
      end

      context 'when unified_name_filter is disabled (regex post-filter kill switch)' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(false)
        end

        it 'still calls EPS with NUCC specialty IDs (server-side category filter always on)' do
          service.search(referral: primary_care_referral)

          expect(eps_provider_service).to have_received(:search_by_location).with(
            hash_including(specialty_ids: %w[207Q00000X 207R00000X 208D00000X])
          )
        end

        it 'keeps providers Wellhive returned even when their name does not match patterns' do
          results = service.search(referral: primary_care_referral)

          eps_results = results.select { |p| p.provider_type == 'eps' }
          expect(eps_results.map(&:id)).to contain_exactly('match-1', 'nomatch-1')
        end

        it 'still runs VA facility eligibility filtering (server-side category filter is no longer gated)' do
          service.search(referral: primary_care_referral)

          expect(eligibility_service).to have_received(:check_eligibility).with(
            hash_including(vaos_service_type: 'primaryCare')
          )
        end
      end

      context 'when unified_name_filter is enabled (default)' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(true)
        end

        it 'sends NUCC IDs to Wellhive AND drops providers that fail the name regex post-filter' do
          results = service.search(referral: primary_care_referral)

          expect(eps_provider_service).to have_received(:search_by_location).with(
            hash_including(specialty_ids: %w[207Q00000X 207R00000X 208D00000X])
          )
          eps_results = results.select { |p| p.provider_type == 'eps' }
          expect(eps_results.map(&:id)).to eq(['match-1'])
        end
      end

      context 'when CCRA category is mapped to non-PC and pilot kill-switch is OFF (default)' do
        let(:cardiology_referral) do
          double('Referral', category_of_care: 'CARDIOLOGY', provider_npi: '91560381x')
        end

        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_non_primary_care, user).and_return(false)
        end

        it 'force-overrides CARDIOLOGY to PC NUCC + regex and logs pc_override' do
          allow(Rails.logger).to receive(:warn)
          allow(StatsD).to receive(:increment)

          results = service.search(referral: cardiology_referral)

          expect(eps_provider_service).to have_received(:search_by_location).with(
            hash_including(specialty_ids: %w[207Q00000X 207R00000X 208D00000X])
          )
          eps_results = results.select { |p| p.provider_type == 'eps' }
          expect(eps_results.map(&:id)).to eq(['match-1'])

          expect(Rails.logger).to have_received(:warn).with(
            'CcraCategoryMapper: pilot is PC-only, overriding mapped category to primaryCare',
            hash_including(
              category_of_care: 'CARDIOLOGY',
              suppressed_vaos_service_type: 'primaryCare',
              suppressed_eps_nucc_specialty_ids: %w[207RC0000X]
            )
          )
          expect(StatsD).to have_received(:increment).with(
            'api.vaos.ccra_category_mapper.pc_override',
            tags: ['category_of_care:CARDIOLOGY']
          )
        end
      end

      context 'when CCRA category is mapped to non-PC and pilot kill-switch is ON' do
        let(:cardiology_referral) do
          double('Referral', category_of_care: 'CARDIOLOGY', provider_npi: '91560381x')
        end

        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(false)
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_non_primary_care, user).and_return(true)
        end

        it "uses CARDIOLOGY's mapped NUCC ids when pilot is expanded beyond PC" do
          service.search(referral: cardiology_referral)

          expect(eps_provider_service).to have_received(:search_by_location).with(
            hash_including(specialty_ids: %w[207RC0000X])
          )
        end

        it 'does not log a pc_override' do
          allow(Rails.logger).to receive(:warn)

          service.search(referral: cardiology_referral)

          expect(Rails.logger).not_to have_received(:warn).with(
            /pilot is PC-only/, anything
          )
        end
      end

      context 'when CCRA category is truly unmapped (not in CCRA_TO_TARGETS)' do
        let(:gastro_referral) do
          double('Referral', category_of_care: 'GASTROENTEROLOGY', provider_npi: '91560381x')
        end

        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_non_primary_care, user).and_return(true)
        end

        it 'still falls back to PC and logs unmapped (independent of pilot kill-switch)' do
          allow(Rails.logger).to receive(:warn)
          allow(StatsD).to receive(:increment)

          service.search(referral: gastro_referral)

          expect(eps_provider_service).to have_received(:search_by_location).with(
            hash_including(specialty_ids: %w[207Q00000X 207R00000X 208D00000X])
          )
          expect(Rails.logger).to have_received(:warn).with(
            'CcraCategoryMapper: unmapped category_of_care, defaulting to primaryCare',
            category_of_care: 'GASTROENTEROLOGY'
          )
          expect(StatsD).to have_received(:increment).with(
            'api.vaos.ccra_category_mapper.unmapped',
            tags: ['category_of_care:GASTROENTEROLOGY']
          )
        end
      end

      # Edge cases around the provider-hash shapes we feed into
      # #provider_matches_patterns? (tested via the public #search interface).
      context 'name-match edge cases (name filter enabled)' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_unified_name_filter, user).and_return(true)
        end

        shared_context 'single EPS provider' do |provider_hash|
          before { allow(eps_provider_service).to receive(:search_by_location).and_return([provider_hash]) }
        end

        context 'matches via top-level provider name' do
          include_context 'single EPS provider', {
            id: 'via-name',
            name: 'Dr. Smith @ Primary Care Associates',
            location: { name: 'Unrelated Building', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: 'X', name: 'Unrelated' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'keeps the provider' do
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('via-name')
          end
        end

        context 'matches via specialty name only' do
          include_context 'single EPS provider', {
            id: 'via-specialty',
            name: 'Dr. Noname',
            location: { name: 'Generic Clinic', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: '207Q00000X', name: 'Family Medicine' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'keeps the provider' do
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('via-specialty')
          end
        end

        context 'matches via location/facility name only' do
          include_context 'single EPS provider', {
            id: 'via-location',
            name: 'Dr. Bland',
            location: { name: 'Acme Primary Care Associates', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: 'X', name: 'Unrelated' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'keeps the provider' do
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('via-location')
          end
        end

        context 'case-insensitive matching' do
          include_context 'single EPS provider', {
            id: 'case-shouty',
            name: 'DR. LOUD @ PRIMARY CARE CLINIC',
            location: { name: 'noisy', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: 'X', name: 'FAMILY MEDICINE' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'matches regardless of provider name casing' do
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('case-shouty')
          end
        end

        context 'multi-pattern any-match semantics' do
          include_context 'single EPS provider', {
            id: 'only-general-practice',
            name: 'Dr. Bland',
            location: { name: 'Generic Building', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: '208D00000X', name: 'General Practice' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'keeps a provider that matches only ONE of the configured patterns' do
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('only-general-practice')
          end
        end

        context 'nil-safety: provider hash missing name' do
          include_context 'single EPS provider', {
            id: 'no-name',
            location: { name: 'Primary Care Spot', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: 'X', name: 'Unrelated' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'does not crash and still matches via location name' do
            expect { service.search(referral: primary_care_referral) }.not_to raise_error
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('no-name')
          end
        end

        context 'nil-safety: provider hash missing location' do
          include_context 'single EPS provider', {
            id: 'no-location',
            name: 'Dr. Smith @ Primary Care Associates',
            specialties: [{ id: '207Q00000X', name: 'Family Medicine' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } },
            # location intentionally omitted; distance lookups are nil-safe via coerce_float
            individual_providers: [{ name: 'Dr. Smith', npi: '1' }]
          }

          it 'does not crash and still matches via name' do
            expect { service.search(referral: primary_care_referral) }.not_to raise_error
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('no-location')
          end
        end

        context 'nil-safety: provider hash missing specialties' do
          include_context 'single EPS provider', {
            id: 'no-specialties',
            name: 'Dr. Smith @ Primary Care Associates',
            location: { name: 'x', latitude: 28.08, longitude: -80.60 },
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'does not crash and still matches via name' do
            expect { service.search(referral: primary_care_referral) }.not_to raise_error
            results = service.search(referral: primary_care_referral)
            expect(results.map(&:id)).to include('no-specialties')
          end
        end

        context 'provider with zero name-like fields matching any pattern' do
          include_context 'single EPS provider', {
            id: 'no-match',
            name: 'Dr. Unrelated @ Unrelated Center',
            location: { name: 'Unrelated Building', latitude: 28.08, longitude: -80.60 },
            specialties: [{ id: 'X', name: 'Dermatology' }],
            features: { is_digital: true, direct_booking: { is_enabled: true } }
          }

          it 'is dropped from results' do
            results = service.search(referral: primary_care_referral)
            eps_results = results.select { |p| p.provider_type == 'eps' }
            expect(eps_results.map(&:id)).not_to include('no-match')
          end
        end
      end
    end
  end

  describe '.default_radius_miles' do
    it 'returns the Settings value when set' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(100)
      expect(described_class.default_radius_miles).to eq(100)
    end

    it 'coerces numeric strings (AWS env vars are strings)' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return('75')
      expect(described_class.default_radius_miles).to eq(75)
    end

    it 'falls back to 25 when Settings value is nil' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(nil)
      expect(described_class.default_radius_miles).to eq(25)
    end

    it 'falls back to 25 when Settings value is blank' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return('')
      expect(described_class.default_radius_miles).to eq(25)
    end

    it 'falls back to 25 when Settings value is zero' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(0)
      expect(described_class.default_radius_miles).to eq(25)
    end

    it 'falls back to 25 when Settings value is negative (ops misconfiguration guard)' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(-5)
      expect(described_class.default_radius_miles).to eq(25)
    end

    it 'falls back to 25 when Settings value is a negative numeric string' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return('-10')
      expect(described_class.default_radius_miles).to eq(25)
    end

    it 'falls back to 25 when Settings value is unparseable' do
      allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return('not-a-number')
      expect(described_class.default_radius_miles).to eq(25)
    end

    context 'when the Settings value is unparseable' do
      before do
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'emits a warn log + StatsD counter so the silent fallback is visible' do
        allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return('not-a-number')

        expect(described_class.default_radius_miles).to eq(25)

        expect(Rails.logger).to have_received(:warn).with(
          'api.vaos.unified_provider_search.default_radius_miles.invalid_setting',
          hash_including(fallback: 25, error_class: 'ArgumentError')
        )
        expect(StatsD).to have_received(:increment).with(
          'api.vaos.unified_provider_search.default_radius_miles.invalid_setting',
          tags: ['error_class:ArgumentError']
        )
      end

      it 'logs when the Settings value is an unexpected type (TypeError path)' do
        allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return([25])

        expect(described_class.default_radius_miles).to eq(25)

        expect(Rails.logger).to have_received(:warn).with(
          'api.vaos.unified_provider_search.default_radius_miles.invalid_setting',
          hash_including(fallback: 25, error_class: 'TypeError', configured_class: 'Array')
        )
      end

      it 'does not log when the Settings value is a valid integer' do
        allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(50)

        described_class.default_radius_miles

        expect(Rails.logger).not_to have_received(:warn)
        expect(StatsD).not_to have_received(:increment)
      end

      it 'also logs when the Settings value is nil (Integer(nil) -> TypeError ' \
         'surfaces as a missing-config alert)' do
        allow(Settings.vaos.unified_scheduling).to receive(:default_radius_miles).and_return(nil)

        expect(described_class.default_radius_miles).to eq(25)
        expect(Rails.logger).to have_received(:warn).with(
          'api.vaos.unified_provider_search.default_radius_miles.invalid_setting',
          hash_including(fallback: 25, error_class: 'TypeError')
        )
      end
    end
  end
end
