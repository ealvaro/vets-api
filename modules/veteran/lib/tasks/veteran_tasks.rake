# frozen_string_literal: true

namespace :veteran do
  desc 'Reload VSO Information'
  task reload_vso_data: :environment do
    puts 'Loading VSO data from OGC'
    # running inline to prevent async race conditions with org/rep loading output
    Veteran::VSOReloader.perform_inline
    puts "#{Veteran::Service::Organization.count} Organizations loaded"
    puts "#{Veteran::Service::Representative.count} Representatives loaded"
  end

  desc 'Load sample data for VSO Reps and Orgs'
  task load_sample_vso_data: :environment do
    # legacy orgs that have been discredited in OGC data but are still used in test data for claims_api
    Veteran::Service::Organization.find_or_create_by(poa: '074', name: '074 - American Legion')
    Veteran::Service::Organization.find_or_create_by(
      poa: '095', name: '095 - ITALIAN AMERICAN WAR VETERANS OF THE US, INC.'
    )
    Veteran::Service::Organization.find_or_create_by(poa: '1NY', name: '1NY - SAMANTHA Y WARSHAUER')
    # updated organizations from OGC rep data that is populated by VSOReloader: 083 071 097 070 00V
    Veteran::Service::Organization.find_or_create_by(poa: '083', name: 'Disabled American Veterans')
    Veteran::Service::Organization.find_or_create_by(poa: '071', name: 'Paralyzed Veterans of America')
    Veteran::Service::Organization.find_or_create_by(poa: '097', name: 'Veterans of Foreign Wars')
    Veteran::Service::Organization.find_or_create_by(poa: '070', name: 'Vietnam Veterans of America')
    Veteran::Service::Organization.find_or_create_by(poa: '00V', name: 'Wounded Warrior Project')
    # legacy org POA codes (removed in updated OGC data from VSOReloader): 074, 095, 1NY
    # legacy rep POA codes (removed in updated OGC data from VSOReloader): 067, A1Q
    # updated org POA codes: 083, 071, 097, 070, 00V
    # updated rep POA codes: 00O, 066, 099, 1L7

    # rep codes come from ClaimsApi::FindPOAsService used to validate dependent POA assignment
    # in dependent_claimant_verification_service.rb and are picked because they are unused by
    # reps from the OGC data loaded by VSOReloader
    Veteran::Service::Representative.find_or_create_by(
      representative_id: '98765',
      user_types: %w[attorney],
      poa_codes: %w[067 A1Q 095 074 1NY 083 071 097 070 00V 00O 066 099 1L7],
      first_name: 'Tamara',
      last_name: 'Ellis',
      email: 'va.api.user+idme.001@gmail.com'
    )
    # legacy org POA codes (removed in updated OGC data from VSOReloader): 074, 095, 1NY
    # legacy rep POA codes (removed in updated OGC data from VSOReloader): 072, A1H
    # updated org POA codes: 083, 071, 097, 070, 00V
    # updated rep POA codes: 2JT, 4R4, DM2, IL7

    # rep codes come from ClaimsApi::FindPOAsService used to validate dependent POA assignment
    # in dependent_claimant_verification_service.rb and are picked because they are unused by
    # reps from the OGC data loaded by VSOReloader
    Veteran::Service::Representative.find_or_create_by(
      representative_id: '12345',
      user_types: %w[attorney],
      poa_codes: %w[072 A1H 095 074 1NY 083 071 097 070 00V 2JT 4R4 DM2 IL7],
      first_name: 'John',
      last_name: 'Doe',
      email: 'va.api.user+idme.007@gmail.com'
    )
  end
end
