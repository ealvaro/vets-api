# frozen_string_literal: true

module LGY
  module Constants
    # Service branch code mapping for new v2 form format
    # Maps client service branch codes to LGY-accepted values
    # Based on: https://va.ghe.com/software/vets-website/blob/main/src/platform/forms-system/src/js/web-component-patterns/content/serviceBranch.json
    SERVICE_BRANCH_MAPPING = {
      # ARMY mappings
      'AAC' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },        # Army Air Corps or Army Air Force
      'ARMY' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },       # Army
      'AR' => { branch: 'ARMY', service_type: 'RESERVE_NATIONAL_GUARD' }, # Army Reserves
      'ARNG' => { branch: 'ARMY', service_type: 'RESERVE_NATIONAL_GUARD' }, # Army National Guard
      'WAC' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },        # Women's Army Corps
      'PA' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },         # Philippine Army
      'PG' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },         # Philippines Guerrilla
      'PS' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },         # Philippines Scout
      'WAAC' => { branch: 'ARMY', service_type: 'ACTIVE_DUTY' },       # Women's Army Auxiliary Corps

      # NAVY mappings
      'NAVY' => { branch: 'NAVY', service_type: 'ACTIVE_DUTY' }, # Navy
      'NR' => { branch: 'NAVY', service_type: 'RESERVE_NATIONAL_GUARD' }, # Navy Reserves
      'N ACAD' => { branch: 'NAVY', service_type: 'ACTIVE_DUTY' },     # Naval Academy
      'PN' => { branch: 'NAVY', service_type: 'ACTIVE_DUTY' },         # Philippine Navy
      'NNC' => { branch: 'NAVY', service_type: 'ACTIVE_DUTY' },        # Navy Nursing Corps
      'WAVES' => { branch: 'NAVY', service_type: 'ACTIVE_DUTY' },      # Women's Voluntary Emergency Service

      # MARINES mappings
      'MC' => { branch: 'MARINES', service_type: 'ACTIVE_DUTY' }, # Marine Corps
      'MCR' => { branch: 'MARINES', service_type: 'RESERVE_NATIONAL_GUARD' }, # Marine Corps Reserves

      # AIR_FORCE mappings (including Space Force)
      'AF' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' }, # Air Force
      'AFR' => { branch: 'AIR_FORCE', service_type: 'RESERVE_NATIONAL_GUARD' }, # Air Force Reserves
      'ANG' => { branch: 'AIR_FORCE', service_type: 'RESERVE_NATIONAL_GUARD' }, # Air National Guard
      'AF ACAD' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' }, # Air Force Academy
      'PAF' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' },   # Philippine Air Force
      'AFNC' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' },  # Air Force Nursing Corps
      'WASP' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' },  # Women's Air Force Service Pilots
      'SF' => { branch: 'AIR_FORCE', service_type: 'ACTIVE_DUTY' },    # Space Force -> Air Force

      # COAST_GUARD mappings
      'CG' => { branch: 'COAST_GUARD', service_type: 'ACTIVE_DUTY' }, # Coast Guard
      'CGR' => { branch: 'COAST_GUARD', service_type: 'RESERVE_NATIONAL_GUARD' }, # Coast Guard Reserves
      'CG ACAD' => { branch: 'COAST_GUARD', service_type: 'ACTIVE_DUTY' }, # Coast Guard Academy
      'SPARS' => { branch: 'COAST_GUARD', service_type: 'ACTIVE_DUTY' }, # Coast Guard Women's Reserve

      # OTHER mappings
      'PHS' => { branch: 'OTHER', service_type: 'ACTIVE_DUTY' },       # Public Health Service
      'NOAA' => { branch: 'OTHER', service_type: 'ACTIVE_DUTY' },      # National Oceanic & Atmospheric Administration
      'MM' => { branch: 'OTHER', service_type: 'ACTIVE_DUTY' },        # Merchant Marine
      'ESA' => { branch: 'OTHER', service_type: 'ACTIVE_DUTY' },       # Environmental Services Administration
      'USMA' => { branch: 'OTHER', service_type: 'ACTIVE_DUTY' }       # US Military Academy
    }.freeze
  end
end
