# frozen_string_literal: true

require 'rails_helper'
require 'bgs/person_cache'

RSpec.describe BGS::PersonCache do
  let(:user_object) { create(:evss_user, :loa3) }
  let(:cache) { described_class.new(user_object) }
  let(:person_params) do
    {
      vnp_proc_id: '1234',
      vnp_ptcpnt_id: nil,
      first_nm: 'Joe',
      middle_nm: 'P',
      last_nm: 'Whitlock',
      suffix_nm: nil,
      brthdy_dt: '2026-02-05T12:00:00+00:00',
      birth_cntry_nm: 'USA',
      birth_state_cd: 'ID',
      birth_city_nm: 'Nowhere',
      file_nbr: '123456789',
      ssn_nbr: '123456789',
      death_dt: nil,
      ever_maried_ind: 'N',
      vet_ind: 'Y',
      martl_status_type_cd: 'N',
      vnp_srusly_dsabld_ind: 'N'
    }
  end

  let(:bgs_service) { BGS::Service.new(user_object) }

  before do
    allow(BGS::Service).to receive(:new).and_return(bgs_service)
  end

  describe '#create_person' do
    context 'with no cache hit' do
      it 'calls the bgs service and creates a new person/participant' do
        VCR.use_cassette('bgs/service/create_person') do
          VCR.use_cassette('bgs/service/create_participant') do
            expect(bgs_service).to receive(:create_participant).and_call_original
            expect(bgs_service).to receive(:create_person).and_call_original
            result = cache.create_person(person_params)
            expect(result[:vnp_ptcpnt_id]).to eq('149456')
            internal = cache.instance_variable_get('@cache')
            expect(internal.key?('joe p whitlock-123456789-2026-02-05T12:00:00+00:00')).to be(true)
          end
        end
      end
    end

    context 'with a cache hit' do
      before do
        VCR.use_cassette('bgs/service/create_person') do
          VCR.use_cassette('bgs/service/create_participant') do
            cache.create_person(person_params)
          end
        end
      end

      it 'returns the existing participant and does not call bgs' do
        expect(bgs_service).not_to receive(:create_participant).and_call_original
        expect(bgs_service).not_to receive(:create_person).and_call_original
        result = cache.create_person(person_params)
        expect(result[:vnp_ptcpnt_id]).to eq('149456')
      end

      it 'ignores case' do
        expect(bgs_service).not_to receive(:create_participant).and_call_original
        expect(bgs_service).not_to receive(:create_person).and_call_original
        result = cache.create_person(person_params.merge({ first_nm: 'jOE' }))
        expect(result[:vnp_ptcpnt_id]).to eq('149456')
      end
    end

    context 'with some missing/null fields' do
      let(:fake_participant) { { vnp_ptcpnt_id: '1234' } }
      let(:person_params) do
        {
          vnp_proc_id: '1234',
          vnp_ptcpnt_id: nil,
          first_nm: 'Joe',
          middle_nm: 'P',
          last_nm: nil
        }
      end

      before do
        allow(bgs_service).to receive(:create_participant).and_return(fake_participant)
        allow(bgs_service).to receive(:create_person)

        # get the cache warmed
        cache.create_person(person_params)
      end

      it 'handles missing/null fields and still returns a cache hit' do
        expect(cache.instance_variable_get('@cache').size).to eq(1)

        expect(bgs_service).not_to receive(:create_participant)
        expect(bgs_service).not_to receive(:create_person)
        result = cache.create_person(person_params)
        expect(result[:vnp_ptcpnt_id]).to eq('1234')
      end
    end
  end
end
