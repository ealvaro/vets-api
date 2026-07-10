# frozen_string_literal: true

require_relative '../../../../support/helpers/rails_helper'
require_relative '../../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::User::AuthorizedServices', type: :request do
  include CommitteeHelper

  let!(:user) { sis_user(vha_facility_ids: [402, 555], mhv_account_creation: { sm_account_created: nil }) }
  let(:attributes) { response.parsed_body.dig('data', 'attributes') }
  let(:meta) { response.parsed_body['meta'] }

  describe 'GET /mobile/v0/user/authorized-services' do
    before do
      allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_schedules,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                instance_of(User)).and_return(false)
    end

    it 'includes a hash with all available services and a boolean value of if the user has access' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => false,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => false,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => false,
          'medicationsOracleHealthEnabled' => false }
      )
    end

    it 'includes properly set meta flags for user not at pretransitioned oh facility' do
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357',
        facilities_ready_for_info_alert: '456, 789',
        oh_migrations_list: ''
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)
      expect(meta).to eq({ 'isUserAtPretransitionedOhFacility' => false,
                           'isUserFacilityReadyForInfoAlert' => false,
                           'migratingFacilitiesList' => [],
                           'emergencyCutoverLock' => [] })
    end

    it 'includes properly set meta flags for user at pretransitioned oh facility but not ready for info alert' do
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357, 555',
        facilities_ready_for_info_alert: '456, 789',
        oh_migrations_list: ''
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(meta).to eq({
                           'isUserAtPretransitionedOhFacility' => true,
                           'isUserFacilityReadyForInfoAlert' => false,
                           'migratingFacilitiesList' => [],
                           'emergencyCutoverLock' => []
                         })
    end

    it 'includes properly set meta flags for user at pretransitioned oh facility and ready for info alert' do
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357, 555',
        facilities_ready_for_info_alert: '555',
        oh_migrations_list: ''
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(meta).to eq({
                           'isUserAtPretransitionedOhFacility' => true,
                           'isUserFacilityReadyForInfoAlert' => true,
                           'migratingFacilitiesList' => [],
                           'emergencyCutoverLock' => []
                         })
    end

    it 'includes properly set meta flags for actively migrating facility' do
      migrations_list = '2026-10-01:[555,Facility A],[612,Facility B]'
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357',
        facilities_ready_for_info_alert: '612',
        oh_migrations_list: migrations_list
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(meta).to eq({
                           'isUserAtPretransitionedOhFacility' => false,
                           'isUserFacilityReadyForInfoAlert' => false,
                           'migratingFacilitiesList' => [],
                           'emergencyCutoverLock' => []
                         })
    end
  end

  describe 'when event_bus_gateway_letter_ready_push_notifications flag is enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                instance_of(User)).and_return(false)
    end

    it 'includes benefitsPushNotification when user has ICN' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']['benefitsPushNotification']).to be true
    end

    context 'when user has no ICN' do
      let!(:user) { sis_user(vha_facility_ids: [402, 555], icn: nil) }

      it 'excludes benefitsPushNotification' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['benefitsPushNotification']).to be false
      end
    end
  end

  describe 'cst_letters_content_updates flag' do
    context 'when cst_letters_content_updates is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                  instance_of(User)).and_return(false)
      end

      it 'returns true for cstLettersContentUpdates when App-Version meets the requirement' do
        get '/mobile/v0/user/authorized-services',
            headers: sis_headers({ 'App-Version' => '2.78.0' }),
            params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersContentUpdates']).to be true
      end

      it 'returns false for cstLettersContentUpdates when App-Version is below the requirement' do
        get '/mobile/v0/user/authorized-services',
            headers: sis_headers({ 'App-Version' => '2.77.0' }),
            params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersContentUpdates']).to be false
      end

      it 'returns false for cstLettersContentUpdates when App-Version is missing' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersContentUpdates']).to be false
      end
    end
  end

  describe 'cst_letters_description_content_format flag' do
    context 'when cst_letters_description_content_format is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_cerner_pilot, instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_allergies_enabled,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                  instance_of(User)).and_return(false)
      end

      it 'returns true for cstLettersDescriptionContentFormat when App-Version meets the requirement' do
        get '/mobile/v0/user/authorized-services',
            headers: sis_headers({ 'App-Version' => '2.80.0' }),
            params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersDescriptionContentFormat']).to be true
      end

      it 'returns false for cstLettersDescriptionContentFormat when App-Version is below the requirement' do
        get '/mobile/v0/user/authorized-services',
            headers: sis_headers({ 'App-Version' => '2.79.0' }),
            params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersDescriptionContentFormat']).to be false
      end

      it 'returns false for cstLettersDescriptionContentFormat when App-Version is missing' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstLettersDescriptionContentFormat']).to be false
      end
    end
  end

  describe 'when cst_multi_claim_provider_mobile flag is enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                instance_of(User)).and_return(false)
    end

    it 'includes cstMultiClaimProvider when user has ICN' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']['cstMultiClaimProvider']).to be true
    end

    context 'when user has no ICN' do
      let!(:user) { sis_user(vha_facility_ids: [402, 555], icn: nil) }

      it 'returns false for cstMultiClaimProvider' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(attributes['authorizedServices']['cstMultiClaimProvider']).to be false
      end
    end
  end

  describe 'when OH flippers are enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot,
                                                instance_of(User)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                instance_of(User)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_schedules,
                                                instance_of(User)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr, instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                instance_of(User)).and_return(false)
    end

    it 'includes a hash with only some OH services enabled if app version matches' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers({ 'App-Version' => '2.99.99' }),
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => false,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => false,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => true,
          'medicationsOracleHealthEnabled' => true }
      )
    end

    it 'includes a hash with all OH services enabled if app version is high enough' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers({ 'App-Version' => '3.0.0' }),
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => true,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => true,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => true,
          'medicationsOracleHealthEnabled' => true }
      )
    end

    it 'includes a hash with all OH services disabled if Big Red Button(TM) is disabled' do
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(false)
      get '/mobile/v0/user/authorized-services', headers: sis_headers({ 'App-Version' => '3.0.0' }),
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => false,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => false,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => true,
          'medicationsOracleHealthEnabled' => false }
      )
    end

    it 'includes a hash with all OH services disabled if app version is not high enough' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers({ 'App-Version' => '2.0.0' }),
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => false,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => false,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => true,
          'medicationsOracleHealthEnabled' => false }
      )
    end

    it 'includes a hash with all OH services disabled if app version not in headers' do
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(attributes['authorizedServices']).to eq(
        { 'allergiesOracleHealthEnabled' => false,
          'appeals' => true,
          'appointments' => true,
          'benefitsPushNotification' => false,
          'claims' => true,
          'cstLettersContentUpdates' => false,
          'cstLettersDescriptionContentFormat' => false,
          'cstMultiClaimProvider' => false,
          'decisionLetters' => true,
          'directDepositBenefits' => true,
          'directDepositBenefitsUpdate' => true,
          'disabilityRating' => true,
          'genderIdentity' => true,
          'labsAndTestsEnabled' => false,
          'lettersAndDocuments' => true,
          'militaryServiceHistory' => true,
          'paymentHistory' => true,
          'preferredName' => true,
          'prescriptions' => true,
          'scheduleAppointments' => true,
          'secureMessaging' => false,
          'userProfileUpdate' => true,
          'secureMessagingOracleHealthEnabled' => true,
          'medicationsOracleHealthEnabled' => false }
      )
    end

    it 'includes properly sets migratingFacilitiesList when user does not have a migrating facility' do
      migrations_list = '2026-10-01:[999,Facility A],[888,Facility B]'
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357',
        facilities_ready_for_info_alert: '612',
        oh_migrations_list: migrations_list
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(meta['migratingFacilitiesList']).to eq([])
    end

    it 'includes properly sets migratingFacilitiesList when user does have a migrating facility' do
      migrations_list = '2026-10-01:[555,Facility A],[555,Facility B]'
      allow(Settings.mhv.oh_facility_checks).to receive_messages(
        pretransitioned_oh_facilities: '612, 357',
        facilities_ready_for_info_alert: '612',
        oh_migrations_list: migrations_list
      )
      get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                 params: { 'appointmentIEN' => '123', 'locationId' => '123' }
      assert_schema_conform(200)

      expect(meta['migratingFacilitiesList'].length).to eq(1)
      expect(meta.dig('migratingFacilitiesList', 0, 'migrationDate')).to eq('October 1, 2026')
      expect(meta.dig('migratingFacilitiesList', 0, 'facilities').length).to eq(2)
    end

    context 'when mhv_oh_migration_trusted_user_bypass is enabled for the user' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                  instance_of(User)).and_return(true)
        allow(Settings.mhv.oh_facility_checks).to receive_messages(
          pretransitioned_oh_facilities: '402, 555',
          facilities_ready_for_info_alert: '402',
          oh_migrations_list: '2026-10-01:[555,Facility A],[402,Facility B]'
        )
      end

      it 'neutralizes all OH migration meta flags' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(meta['isUserAtPretransitionedOhFacility']).to be false
        expect(meta['isUserFacilityReadyForInfoAlert']).to be false
        expect(meta['migratingFacilitiesList']).to eq([])
      end
    end
  end

  describe 'emergency_cutover_lock' do
    before do
      allow(Flipper).to receive(:enabled?).with(:event_bus_gateway_letter_ready_push_notifications, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cst_multi_claim_provider_mobile, instance_of(Flipper::Actor)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_cerner_pilot,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_labs_and_tests_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                                instance_of(User)).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_schedules,
                                                instance_of(User)).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_oh_migration_trusted_user_bypass,
                                                instance_of(User)).and_return(false)
    end

    context 'when user is not at a migrating facility' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive_messages(
          pretransitioned_oh_facilities: '',
          facilities_ready_for_info_alert: '',
          oh_migrations_list: '2026-10-01:[999,Other VA]'
        )
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm, instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx, instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr, instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                  instance_of(User)).and_return(true)
      end

      it 'returns an empty emergencyCutoverLock array even when lock flags are enabled' do
        get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                   params: { 'appointmentIEN' => '123', 'locationId' => '123' }
        assert_schema_conform(200)

        expect(meta['emergencyCutoverLock']).to eq([])
      end
    end

    context 'when user is at a migrating facility' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive_messages(
          pretransitioned_oh_facilities: '',
          facilities_ready_for_info_alert: '',
          oh_migrations_list: '2026-10-01:[555,Facility A]'
        )
      end

      context 'when no emergency lock flags are enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm,
                                                    instance_of(User)).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx,
                                                    instance_of(User)).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr,
                                                    instance_of(User)).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                    instance_of(User)).and_return(false)
        end

        it 'returns an empty emergencyCutoverLock array' do
          get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                     params: { 'appointmentIEN' => '123', 'locationId' => '123' }
          assert_schema_conform(200)

          expect(meta['emergencyCutoverLock']).to eq([])
        end
      end

      context 'when one emergency lock flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm,
                                                    instance_of(User)).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx,
                                                    instance_of(User)).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr,
                                                    instance_of(User)).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                    instance_of(User)).and_return(false)
        end

        it 'returns only the locked tool in emergencyCutoverLock' do
          get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                     params: { 'appointmentIEN' => '123', 'locationId' => '123' }
          assert_schema_conform(200)

          expect(meta['emergencyCutoverLock']).to eq(['rx'])
        end
      end

      context 'when all emergency lock flags are enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_sm,
                                                    instance_of(User)).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_rx,
                                                    instance_of(User)).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_mr,
                                                    instance_of(User)).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:mhv_oh_emergency_cutover_lock_appointments,
                                                    instance_of(User)).and_return(true)
        end

        it 'returns all tools in emergencyCutoverLock' do
          get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                     params: { 'appointmentIEN' => '123', 'locationId' => '123' }
          assert_schema_conform(200)

          expect(meta['emergencyCutoverLock']).to contain_exactly('sm', 'rx', 'mr', 'appointments')
        end

        it 'sets prescriptions, appointments to false in authorizedServices' do
          get '/mobile/v0/user/authorized-services', headers: sis_headers,
                                                     params: { 'appointmentIEN' => '123', 'locationId' => '123' }
          assert_schema_conform(200)

          expect(attributes['authorizedServices']['prescriptions']).to be false
          expect(attributes['authorizedServices']['appointments']).to be false
        end
      end
    end
  end
end
