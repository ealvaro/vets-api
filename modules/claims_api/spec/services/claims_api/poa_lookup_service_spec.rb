# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::PoaLookupService do
  let(:user) do
    ClaimsApi::Veteran.new(
      uuid: '123456789',
      ssn: '123456789',
      first_name: 'Firstname',
      last_name: 'Lastname',
      va_profile: ClaimsApi::Veteran.build_profile('1970-01-01'),
      last_signed_in: Time.now.utc
    )
  end

  let(:org_web_service) { ClaimsApi::OrgWebService }

  context 'initialization' do
    it 'initializes from a user' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: { person_poa: [{ begin_dt: Time.zone.now, legacy_poa_cd: '033' }] } })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.power_of_attorney.code).to eq('074')
        expect(lookup.previous_power_of_attorney.code).to eq('033')
      end
    end

    it 'does not bomb out if poa is missing' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/not_find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.power_of_attorney).to be_nil
        expect(lookup.previous_power_of_attorney).to be_nil
      end
    end

    it 'handles nil response from find_poa_history_by_ptcpnt_id' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/not_find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return(nil)
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.power_of_attorney).to be_nil
        expect(lookup.previous_power_of_attorney).to be_nil
      end
    end

    it 'provides most recent previous poa' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({
                        person_poa_history: {
                          person_poa: [
                            { begin_dt: 2.years.ago, legacy_poa_cd: '233' },
                            { begin_dt: 1.year.ago, legacy_poa_cd: '133' },
                            { begin_dt: 3.years.ago, legacy_poa_cd: '333' }
                          ]
                        }
                      })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.previous_power_of_attorney.code).to eq('133')
      end
    end

    it 'does not bomb out if poa history contains a single record' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: { person_poa: { begin_dt: Time.zone.now, legacy_poa_cd: '033' } } })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.power_of_attorney.code).to eq('074')
        expect(lookup.previous_power_of_attorney.code).to eq('033')
      end
    end
  end

  describe '#current_poa_code' do
    it 'returns the POA code when present' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.current_poa_code).to eq('074')
      end
    end

    it 'returns nil when no POA exists' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/not_find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.current_poa_code).to be_nil
      end
    end

    context 'when respect_expiration is true' do
      it 'returns nil when the POA end_date is in the past' do
        VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
          allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
            .and_return({ person_poa_history: nil })
          lookup = ClaimsApi::PoaLookupService.new(user)
          lookup.power_of_attorney = PowerOfAttorney.new(code: '074', end_date: '01/01/2020')
          expect(lookup.current_poa_code(respect_expiration: true)).to be_nil
        end
      end

      it 'returns the code when the POA end_date is in the future' do
        VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
          allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
            .and_return({ person_poa_history: nil })
          lookup = ClaimsApi::PoaLookupService.new(user)
          lookup.power_of_attorney = PowerOfAttorney.new(code: '074', end_date: '01/01/2099')
          expect(lookup.current_poa_code(respect_expiration: true)).to eq('074')
        end
      end

      it 'returns the code when no end_date is present' do
        VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
          allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
            .and_return({ person_poa_history: nil })
          lookup = ClaimsApi::PoaLookupService.new(user)
          expect(lookup.current_poa_code(respect_expiration: true)).to eq('074')
        end
      end
    end

    context 'when respect_expiration is false (default)' do
      it 'returns the code even when end_date is in the past' do
        VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
          allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
            .and_return({ person_poa_history: nil })
          lookup = ClaimsApi::PoaLookupService.new(user)
          lookup.power_of_attorney = PowerOfAttorney.new(code: '074', end_date: '01/01/2020')
          expect(lookup.current_poa_code).to eq('074')
        end
      end
    end
  end

  describe '#previous_poa_code' do
    it 'returns the previous POA code' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: { person_poa: [{ begin_dt: Time.zone.now, legacy_poa_cd: '033' }] } })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.previous_poa_code).to eq('033')
      end
    end

    it 'returns nil when no previous POA exists' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/not_find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.previous_poa_code).to be_nil
      end
    end
  end

  describe '#poa_begin_date' do
    it 'returns the begin_date when present' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.poa_begin_date).to be_present
      end
    end

    it 'returns nil when no POA exists' do
      VCR.use_cassette('claims_api/bgs/claimant_web_service/not_find_poa_by_participant_id') do
        allow_any_instance_of(org_web_service).to receive(:find_poa_history_by_ptcpnt_id)
          .and_return({ person_poa_history: nil })
        lookup = ClaimsApi::PoaLookupService.new(user)
        expect(lookup.poa_begin_date).to be_nil
      end
    end
  end
end
