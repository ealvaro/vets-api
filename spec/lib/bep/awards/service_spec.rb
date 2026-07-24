# frozen_string_literal: true

require 'rails_helper'
require 'bep/awards/service'
require_relative 'support/current_awards_response'

RSpec.describe BEP::Awards::Service do
  let(:user) { create(:evss_user, :loa3) }
  let(:participant_id) { user.participant_id }
  let(:service) { BEP::Awards::Service.new }

  include_context 'BEP Awards CurrentAwardsResponse'

  describe '#get_awards_pension' do
    let(:faraday_response) { double('faraday_connection') }

    before do
      allow(faraday_response).to receive(:env)
    end

    context 'with a successful submission' do
      it 'successfully receives an Award Pension object' do
        VCR.use_cassette('bep/awards/get_awards_pension') do
          response = service.get_awards_pension(participant_id)

          expect(response.status).to eq(200)
          expect(response.body['awards_pension']['is_eligible_for_pension']).to be(true)
          expect(response.body['awards_pension']['is_in_receipt_of_pension']).to be(true)
        end
      end
    end
  end

  describe '#get_current_awards' do
    let(:faraday_response) { double('faraday_connection') }

    before do
      allow(faraday_response).to receive(:env)
    end

    context 'with a successful submission' do
      it 'successfully receives a list of current awards' do
        # Mock the service to return the mock response
        allow(service).to receive(:perform).and_return(
          OpenStruct.new(
            status: 200,
            body: mock_response_body
          )
        )

        response = service.get_current_awards(participant_id)

        expect(response.status).to eq(200)
        expect(response.body).to have_key('award')

        award = response.body['award']
        expect(award['award_type']).to eq('CPL')
        expect(award['award_type_desc']).to eq('Compensation/Pension Live')
        expect(award['beneficiary_id']).to eq(12_960_359)
        expect(award['veteran_id']).to eq(12_960_359)
        expect(award['award_event_list']).to have_key('award_events')
        award_events = award['award_event_list']['award_events']
        expect(award_events).to be_an(Array)
        expect(award_events.length).to be > 0

        first_event = award_events.first
        expect(first_event['award_event_status']).to eq('Authorized')
        expect(first_event['award_event_type']).to eq('S')

        expect(first_event['award_line_list']).to have_key('award_lines')
        award_lines = first_event['award_line_list']['award_lines']
        expect(award_lines).to be_an(Array)
        expect(award_lines.length).to be > 0

        first_line = award_lines.first
        expect(first_line['award_line_type']).to eq('IP')
        expect(first_line['gross_amount']).to eq('462.00')
        expect(first_line['net_amount']).to eq('462.00')
      end
    end
  end
end
