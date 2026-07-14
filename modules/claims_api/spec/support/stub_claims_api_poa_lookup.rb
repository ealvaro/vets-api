# frozen_string_literal: true

# Stubs ClaimsApi::PoaLookupService.new for claims_api request specs.
#
# Use alongside stub_poa_verification (from spec/support/poa_stub.rb) when a
# spec exercises both the claims_api concerns (poa_verification, target_veteran)
# and the lib/bgs/power_of_attorney_verifier.rb codepath, which is common in
# v1 forms/claims request specs.
def stub_claims_api_poa_lookup
  poa_stub = instance_double(PowerOfAttorney, code: 'A01')
  poa_lookup_stub = instance_double(ClaimsApi::PoaLookupService)
  allow(ClaimsApi::PoaLookupService).to receive(:new).and_return(poa_lookup_stub)
  allow(poa_lookup_stub).to receive(:power_of_attorney).and_return(poa_stub)
end
