# frozen_string_literal: true

FactoryBot.define do
  factory :mobile_maintenance_lighthouse_first, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHQI9WA' }
    external_service { 'lighthouse_benefits_claims' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'lighthouse is down' }
  end

  factory :mobile_maintenance_lighthouse_second, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHQI9WB' }
    external_service { 'lighthouse_benefits_claims' }
    start_time { '2021-05-26 21:33:39' }
    end_time { '2021-05-26 22:33:39' }
    created_at { '2021-05-25 12:15:17' }
    description { 'lighthouse is down' }
  end

  factory :mobile_maintenance_lighthouse_third, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHQI9WC' }
    external_service { 'lighthouse_benefits_claims' }
    start_time { '2021-05-27 21:33:39' }
    end_time { '2021-05-27 22:33:39' }
    created_at { '2021-05-26 12:15:17' }
    description { 'lighthouse is down' }
  end

  factory :mobile_maintenance_mpi, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHQI9WB' }
    external_service { 'mpi' }
    start_time { '2021-05-25 23:33:39' }
    end_time { '2021-05-26 01:45:00' }
    created_at { '2021-05-24 12:15:17' }
    description { 'mpi is down' }
  end

  factory :mobile_maintenance_bgs_first, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHA6DOA' }
    external_service { 'bgs' }
    start_time { '2021-05-25 23:33:39' }
    end_time { '2021-05-26 01:45:00' }
    created_at { '2021-05-24 12:15:17' }
    description { '' }
  end

  factory :mobile_maintenance_bgs_second, class: '::MaintenanceWindow' do
    pagerduty_id { 'PHA6DOG' }
    external_service { 'bgs' }
    start_time { '2021-05-26 23:33:39' }
    end_time { '2021-05-27 01:45:00' }
    created_at { '2021-05-25 12:15:17' }
    description { '' }
  end

  factory :mobile_maintenance_vbms, class: '::MaintenanceWindow' do
    pagerduty_id { 'PXF4P0E' }
    external_service { 'vbms' }
    start_time { '2021-05-25 23:33:39' }
    end_time { '2021-05-27 01:45:00' }
    created_at { '2021-05-22 12:01:15' }
    description { '' }
  end

  factory :mobile_maintenance_vaos, class: '::MaintenanceWindow' do
    pagerduty_id { 'PVAOS01' }
    external_service { 'vaos' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'vaos is down' }
  end

  factory :mobile_maintenance_ccra, class: '::MaintenanceWindow' do
    pagerduty_id { 'PCCRA01' }
    external_service { 'ccra' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'ccra is down' }
  end

  factory :mobile_maintenance_dmc, class: '::MaintenanceWindow' do
    pagerduty_id { 'PDMC001' }
    external_service { 'dmc' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'dmc is down' }
  end

  factory :mobile_maintenance_vbs, class: '::MaintenanceWindow' do
    pagerduty_id { 'PVBS001' }
    external_service { 'vbs' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'vbs is down' }
  end

  factory :mobile_maintenance_vetext, class: '::MaintenanceWindow' do
    pagerduty_id { 'PVETEXT1' }
    external_service { 'vetext' }
    start_time { '2021-05-25 21:33:39' }
    end_time { '2021-05-25 22:33:39' }
    created_at { '2021-05-24 12:15:17' }
    description { 'vetext is down' }
  end
end
