# frozen_string_literal: true

# Facility Locator kill-switch Flipper flags default to *enabled* in the test env
# (see config/initializers/flipper.rb, which enables every feature when Rails.env.test?).
# For the Facility Locator specs that inverts production reality: every endpoint would return
# 503 because the switches are "on". This shared context restores the production/dev default
# (all switches off) so specs exercise real behavior. Examples that assert the 503 path re-stub
# a specific flag to true in a nested context, which overrides the default below.
#
# Auto-applied to every modules/facilities_api spec (that module owns the switches). Cross-module
# consumers tag their top-level describe with `:facility_locator_kill_switches` to opt in.
RSpec.shared_context 'facility locator kill switches disabled' do
  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    %i[
      facility_locator_disabled
      facility_locator_va_disabled
      facility_locator_ppms_provider_locator_disabled
      facility_locator_ppms_facility_service_locator_disabled
      facility_locator_ppms_pos_locator_disabled
      facility_locator_ppms_specialties_disabled
    ].each do |flag|
      allow(Flipper).to receive(:enabled?).with(flag).and_return(false)
    end
  end
end

RSpec.configure do |config|
  config.include_context 'facility locator kill switches disabled', :facility_locator_kill_switches

  config.define_derived_metadata(file_path: %r{modules/facilities_api/spec/}) do |metadata|
    metadata[:facility_locator_kill_switches] = true
  end
end
