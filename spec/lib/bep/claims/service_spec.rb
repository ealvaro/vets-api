# frozen_string_literal: true

require 'rails_helper'
require 'bep/claims/service'

RSpec.describe BEP::Claims::Service do
  let(:service) { BEP::Claims::Service.new }

  describe '#create_claim' do
    let(:create_params) do
      {
        serviceTypeCode: 'CP',
        programTypeCode: 'CPL',
        benefitClaimTypeCode: '130DCY686',
        claimant: {
          participantId: 123_456_789
        },
        veteran: {
          participantId: 123_456_789,
          firstName: 'JOE',
          lastName: 'JOESON'
        },
        dateOfClaim: Time.zone.now.iso8601,
        tempStationOfJurisdiction: 281,
        submtrRoleTypeCd: 'VBA',
        submtrApplcnTypeCd: 'VBMS'
      }
    end

    it 'successfully calls the api' do
      VCR.use_cassette('bep/claims/create_claim') do
        response = service.create_claim(create_params)

        expect(response.status).to eq(201)
        expect(response.body['claim_id']).to eq(600_964_424)
      end
    end
  end

  describe '#create_contention' do
    let(:claim_id) { 600_964_424 }
    let(:contention_params) do
      {
        createContentions: [
          {
            medicalInd: true,
            beginDate: Time.zone.now.iso8601,
            createDate: Time.zone.now.iso8601,
            altContentionName: 'My Test Contention',
            contentionTypeCode: 'NEW',
            classificationType: 1250,
            diagnosticTypeCode: '6100',
            claimantText: 'test claimant text',
            contentionStatusTypeCode: 'C',
            originalSourceTypeCode: 'PHYS'
          }
        ]
      }
    end

    it 'successfully calls the api' do
      VCR.use_cassette('bep/claims/create_contention') do
        response = service.create_contention(claim_id, contention_params)

        expect(response.status).to eq(201)
        expect(response.body['contention_ids']).to eq([868_026])
      end
    end
  end
end
