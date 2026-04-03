# frozen_string_literal: true

require_relative '../../../../../support/helpers/rails_helper'

RSpec.describe 'Mobile::V0::Messaging::Health::EhrCrosswalk', type: :request do
  include SchemaMatchers

  let!(:user) { sis_user(:mhv, mhv_correlation_id: '123', mhv_account_type: 'Premium') }

  before do
    Timecop.freeze(Time.zone.parse('2017-05-01T19:25:00Z'))
  end

  after do
    Timecop.return
  end

  context 'when not authorized' do
    it 'responds with 403 error' do
      VCR.use_cassette('mobile/messages/session_error') do
        get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
      end
      expect(response).not_to be_successful
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when authorized' do
    before do
      VCR.insert_cassette('sm_client/session')
    end

    after do
      VCR.eject_cassette
    end

    it 'responds to GET #crosswalk with entries' do
      VCR.use_cassette('sm_client/triage_teams/gets_ehr_crosswalk_entries') do
        get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
      end

      expect(response).to be_successful
      parsed = JSON.parse(response.body)
      expect(parsed['data']).to be_an(Array)
      expect(parsed['data'].first['type']).to eq('ehr_crosswalk_entries')
    end

    it 'returns empty data array when patient has no crosswalk entries' do
      VCR.use_cassette('sm_client/triage_teams/gets_empty_ehr_crosswalk') do
        get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
      end

      expect(response).to be_successful
      parsed = JSON.parse(response.body)
      expect(parsed['data']).to eq([])
    end

    context 'fuzz tests' do
      before do
        allow_any_instance_of(SM::Client).to receive(:get_crosswalk).and_return(fuzzed_data)
      end

      let(:valid_entry) do
        { vista_triage_group_id: 12_345, vista_triage_group_name: 'TEAM A',
          oh_triage_group_id: 67_890, oh_triage_group_name: 'OH TEAM A' }
      end

      context 'with nil values in entry fields' do
        let(:fuzzed_data) do
          [{ vista_triage_group_id: nil, vista_triage_group_name: nil,
             oh_triage_group_id: nil, oh_triage_group_name: nil }]
        end

        it 'serializes without error' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          expect(parsed['data'].length).to eq(1)
        end
      end

      context 'with missing keys in entries' do
        let(:fuzzed_data) { [{ vista_triage_group_id: 111 }] }

        it 'serializes with missing attributes as nil' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          attrs = parsed['data'].first['attributes']
          expect(attrs['ohTriageGroupId']).to be_nil
          expect(attrs['ohTriageGroupName']).to be_nil
        end
      end

      context 'with extra unexpected keys in entries' do
        let(:fuzzed_data) do
          [valid_entry.merge(unexpected_field: 'surprise', nested: { deep: true }, arr: [1, 2, 3])]
        end

        it 'ignores extra fields and serializes normally' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          attrs = parsed['data'].first['attributes']
          expect(attrs.keys).not_to include('unexpectedField', 'nested', 'arr')
          expect(attrs['vistaTriageGroupId']).to eq(12_345)
        end
      end

      context 'with string values where integers are expected' do
        let(:fuzzed_data) do
          [{ vista_triage_group_id: 'not-a-number', vista_triage_group_name: 12_345,
             oh_triage_group_id: '', oh_triage_group_name: 0 }]
        end

        it 'passes through values without coercion' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          attrs = parsed['data'].first['attributes']
          expect(attrs['vistaTriageGroupId']).to eq('not-a-number')
          expect(attrs['vistaTriageGroupName']).to eq(12_345)
        end
      end

      context 'with special characters in string fields' do
        let(:fuzzed_data) do
          [{ vista_triage_group_id: 1,
             vista_triage_group_name: "<script>alert('xss')</script>",
             oh_triage_group_id: 2,
             oh_triage_group_name: "O'Malley & Sons — \"Quoted\" \nNewline\tTab" }]
        end

        it 'returns special characters safely in JSON' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          attrs = parsed['data'].first['attributes']
          expect(attrs['vistaTriageGroupName']).to include('<script>')
          expect(attrs['ohTriageGroupName']).to include("O'Malley")
        end
      end

      context 'with a large number of entries' do
        let(:fuzzed_data) do
          (1..500).map do |i|
            { vista_triage_group_id: i, vista_triage_group_name: "VistA Team #{i}",
              oh_triage_group_id: i + 1000, oh_triage_group_name: "OH Team #{i}" }
          end
        end

        it 'handles large payloads without error' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          expect(parsed['data'].length).to eq(500)
        end
      end

      context 'with duplicate entries' do
        let(:fuzzed_data) { [valid_entry, valid_entry, valid_entry] }

        it 'returns all duplicates (no dedup)' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          expect(parsed['data'].length).to eq(3)
        end
      end

      context 'with completely empty hashes' do
        let(:fuzzed_data) { [{}, {}, {}] }

        it 'serializes empty entries without error' do
          get '/mobile/v0/messaging/health/recipients/crosswalk', headers: sis_headers
          expect(response).to be_successful
          parsed = JSON.parse(response.body)
          expect(parsed['data'].length).to eq(3)
        end
      end
    end
  end
end
