# frozen_string_literal: true

# Rake tasks for local development seeding of Form 21P-530A related caches.
# These tasks pre-warm Redis caches so the app works without a live BGS connection.
#
# Usage:
#   bundle exec rake form21p530a:seed_cemetery_cache
#
namespace :form21p530a do
  desc 'Seed the FindCemeteriesService Redis cache with fake data for local development. ' \
       'The cache TTL is 24 hours (same as production), so run this once per dev session.'
  task seed_cemetery_cache: :environment do
    require 'form21p530a/find_cemeteries_service'

    fake_cemeteries = [
      { org_nm: 'Arlington National Cemetery', addr_line_one: '1 Memorial Ave', addr_line_two: nil,
        city_nm: 'Arlington', state: 'VA', zip_code: '22211',
        day_phone_area_nbr: '703', day_phone_phone_nbr: '6071000' },
      { org_nm: 'Fort Logan National Cemetery', addr_line_one: '4400 W Kenyon Ave', addr_line_two: nil,
        city_nm: 'Denver', state: 'CO', zip_code: '80236',
        day_phone_area_nbr: '303', day_phone_phone_nbr: '7611000' },
      { org_nm: 'Abraham Lincoln National Cemetery', addr_line_one: '20953 W Hoff Rd', addr_line_two: nil,
        city_nm: 'Elwood', state: 'IL', zip_code: '60421',
        day_phone_area_nbr: '815', day_phone_phone_nbr: '4231831' },
      { org_nm: 'Golden Gate National Cemetery', addr_line_one: '1300 Sneath Ln', addr_line_two: nil,
        city_nm: 'San Bruno', state: 'CA', zip_code: '94066',
        day_phone_area_nbr: '650', day_phone_phone_nbr: '5898200' },
      { org_nm: 'Houston National Cemetery', addr_line_one: '10410 Veterans Memorial Dr', addr_line_two: nil,
        city_nm: 'Houston', state: 'TX', zip_code: '77038',
        day_phone_area_nbr: '281', day_phone_phone_nbr: '4478000' }
    ]

    service = Form21p530a::FindCemeteriesService.new
    cache_key = Time.zone.now.to_date.to_s

    # Bypass the service's BGS call and write directly to Redis
    response = Form21p530a::FindCemeteriesResponse.new(fake_cemeteries)
    service.send(:do_cached_with, key: cache_key) { response }

    puts "✓ Cemetery cache seeded with #{fake_cemeteries.size} fake entries (key: #{cache_key})"
    puts '  Cache key is date-based; a new key is used each day. Redis TTL is 24 hours from seeding.'
    puts '  Endpoint: GET /v0/form21p530a/cemeteries'
  end
end
