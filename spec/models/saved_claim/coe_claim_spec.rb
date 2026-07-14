# frozen_string_literal: true

require 'rails_helper'
require 'lgy/service'
require 'lgy/constants'

RSpec.describe SavedClaim::CoeClaim do
  let(:base_form_data) do
    {
      'status' => 'SUBMITTED',
      'veteran' => {
        'firstName' => 'Eddie',
        'middleName' => 'Joseph',
        'lastName' => 'Caldwell',
        'suffixName' => '',
        'dateOfBirth' => '1933-10-27',
        'vetAddress1' => '123 ANY ST',
        'vetAddress2' => '',
        'vetAddress3' => '',
        'vetCity' => 'ANYTOWN',
        'vetState' => 'AL',
        'vetZip' => '54321',
        'vetZipSuffix' => nil,
        'mailingAddress1' => '123 ANY ST',
        'mailingAddress2' => '',
        'mailingAddress3' => '',
        'mailingCity' => 'ANYTOWN',
        'mailingState' => 'AL',
        'mailingZip' => '54321',
        'mailingZipSuffix' => '',
        'contactPhone' => '2223334444',
        'contactEmail' => 'vet@example.com',
        'vaLoanIndicator' => true,
        'vaHomeOwnIndicator' => true,
        'activeDutyIndicator' => true,
        'disabilityIndicator' => false
      },
      'relevantPriorLoans' => [],
      'periodsOfService' => []
    }
  end

  let(:base_legacy_form) do
    {
      'relevantPriorLoans' => [
        {
          'dateRange' => { 'from' => '2017-01-01T00:00:00.000Z', 'to' => '' },
          'propertyAddress' => { 'propertyAddress1' => '234', 'propertyAddress2' => '234', 'propertyCity' => 'asdf',
                                 'propertyState' => 'AL', 'propertyZip' => '11111' },
          'propertyOwned' => false,
          'vaLoanNumber' => '123123123123',
          'intent' => 'IRRRL'
        },
        {
          'dateRange' => { 'from' => '2010-01-01T00:00:00.000Z', 'to' => '2011-01-01T00:00:00.000Z' },
          'propertyAddress' => { 'propertyAddress1' => '939393', 'propertyAddress2' => '234', 'propertyCity' => 'asdf',
                                 'propertyState' => 'AL', 'propertyZip' => '11111' },
          'propertyOwned' => true,
          'vaLoanNumber' => '456456456456',
          'intent' => 'REFI'
        }
      ],
      'vaLoanIndicator' => true,
      'periodsOfService' => [
        {
          'serviceBranch' => 'Air Force',
          'dateRange' => { 'from' => '2000-01-01T00:00:00.000Z', 'to' => '2010-01-16T00:00:00.000Z' }
        }
      ],
      'identity' => 'ADSM',
      'contactPhone' => '2223334444',
      'contactEmail' => 'vet@example.com',
      'fullName' => { 'first' => 'Eddie', 'middle' => 'Joseph', 'last' => 'Caldwell' },
      'dateOfBirth' => '1933-10-27',
      'applicantAddress' => { 'country' => 'USA', 'street' => '123 ANY ST', 'city' => 'ANYTOWN', 'state' => 'AL',
                              'postalCode' => '54321' },
      'privacyAgreementAccepted' => true
    }
  end

  let(:base_v2_form) do
    {
      'version' => 2,
      'fullName' => { 'first' => 'Eddie', 'middle' => 'Joseph', 'last' => 'Caldwell' },
      'dateOfBirth' => '1933-10-27',
      'veteran' => {
        'mailingAddress' => { 'addressLine1' => '123 ANY ST', 'addressLine2' => '', 'addressLine3' => '',
                              'city' => 'ANYTOWN', 'stateCode' => 'AL', 'zipCode' => '54321' },
        'homePhone' => { 'areaCode' => '222', 'phoneNumber' => '3334444' },
        'email' => { 'emailAddress' => 'vet@example.com' }
      },
      'militaryHistory' => {
        'status' => 'ADSM',
        'separatedDueToDisability' => false,
        'preDischargeClaim' => false,
        'periodsOfService' => [
          {
            'serviceBranch' => 'AF',
            'dateRange' => { 'from' => '2000-01-01T00:00:00.000Z', 'to' => '2010-01-16T00:00:00.000Z' }
          }
        ]
      },
      'loanHistory' => {
        'certificateUse' => 'HOME_PURCHASE',
        'hadPriorLoans' => true,
        'relevantPriorLoans' => [
          {
            'loanDate' => '2017-01-01T00:00:00.000Z',
            'propertyAddress' => { 'country' => 'USA', 'street1' => '234', 'street2' => '234',
                                   'city' => 'asdf', 'state' => 'AL', 'postalCode' => '11111' },
            'vaLoanNumber' => '123123123123',
            'entitlementRestoration' => 'INTEREST_RATE_REDUCTION_REFINANCE'
          },
          {
            'loanDate' => '2010-01-01T00:00:00.000Z',
            'propertyAddress' => { 'country' => 'USA', 'street1' => '939393', 'street2' => '234',
                                   'city' => 'asdf', 'state' => 'AL', 'postalCode' => '11111' },
            'vaLoanNumber' => '456456456456',
            'entitlementRestoration' => 'CASH_OUT_REFINANCE'
          }
        ]
      },
      'privacyAgreementAccepted' => true
    }
  end

  describe '#send_to_lgy(edipi:, icn:)' do
    before do
      allow(Flipper).to receive(:enabled?).with(:coe_form_rebuild_cveteam).and_return(false)
    end

    it 'logs an error if edipi is nil' do
      coe_claim = create(:coe_claim)
      allow(coe_claim).to receive(:prepare_form_data).and_return({})
      allow_any_instance_of(LGY::Service).to receive(:put_application).and_return({})
      expect(Rails.logger).to receive(:error).with(/COE application cannot be submitted without an edipi!/)
      coe_claim.send_to_lgy(edipi: nil, icn: nil)
    end

    it 'logs an error if edipi is an empty string' do
      coe_claim = create(:coe_claim)
      allow(coe_claim).to receive(:prepare_form_data).and_return({})
      allow_any_instance_of(LGY::Service).to receive(:put_application).and_return({})
      expect(Rails.logger).to receive(:error).with(/COE application cannot be submitted without an edipi!/)
      coe_claim.send_to_lgy(edipi: '', icn: nil)
    end

    context 'with legacy form version' do
      let(:relevant_prior_loans) do
        [{
          'vaLoanNumber' => '123123123123',
          'startDate' => '2017-01-01T00:00:00.000Z',
          'paidOffDate' => '',
          'loanAmount' => nil,
          'loanEntitlementCharged' => nil,
          'propertyOwned' => false,
          'oneTimeRestorationRequested' => false,
          'irrrlRequested' => true,
          'cashoutRefinaceRequested' => false,
          'noRestorationEntitlementIndicator' => false,
          'homeSellIndicator' => nil,
          'propertyAddress1' => '234',
          'propertyAddress2' => '234',
          'propertyCity' => 'asdf',
          'propertyState' => 'AL',
          'propertyCounty' => '',
          'propertyZip' => '11111',
          'propertyZipSuffix' => ''
        }, {
          'vaLoanNumber' => '456456456456',
          'startDate' => '2010-01-01T00:00:00.000Z',
          'paidOffDate' => '2011-01-01T00:00:00.000Z',
          'loanAmount' => nil,
          'loanEntitlementCharged' => nil,
          'propertyOwned' => true,
          'oneTimeRestorationRequested' => false,
          'irrrlRequested' => false,
          'cashoutRefinaceRequested' => true,
          'noRestorationEntitlementIndicator' => false,
          'homeSellIndicator' => nil,
          'propertyAddress1' => '939393',
          'propertyAddress2' => '234',
          'propertyCity' => 'asdf',
          'propertyState' => 'AL',
          'propertyCounty' => '',
          'propertyZip' => '11111',
          'propertyZipSuffix' => ''
        }]
      end

      it 'sends the right data to LGY' do
        coe_claim = create(:coe_claim, form: base_legacy_form.to_json)
        form_data = base_form_data.deep_merge({
                                                'relevantPriorLoans' => relevant_prior_loans,
                                                'periodsOfService' => [{
                                                  'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                  'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                  'militaryBranch' => 'AIR_FORCE',
                                                  'serviceType' => 'ACTIVE_DUTY',
                                                  'disabilityIndicator' => false
                                                }]
                                              })

        expect_any_instance_of(LGY::Service)
          .to receive(:put_application)
          .with(payload: form_data)
          .and_return({})
        coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
      end

      context 'send AIR_FORCE as branch for Air National Guard to LGY' do
        it 'sends the right data to LGY' do
          air_ng_service = { 'periodsOfService' => [{ 'serviceBranch' => 'Air National Guard',
                                                      'dateRange' => { 'from' => '2000-01-01T00:00:00.000Z',
                                                                       'to' => '2010-01-16T00:00:00.000Z' } }] }
          coe_claim = create(:coe_claim, form: base_legacy_form.deep_merge(air_ng_service).to_json)
          form_data = base_form_data.deep_merge({
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'AIR_FORCE',
                                                    'serviceType' => 'RESERVE_NATIONAL_GUARD',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })
          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'send MARINES as branch for Marine Corps Reserve to LGY' do
        it 'sends the right data to LGY' do
          marine_reserves_service_period = { 'periodsOfService' => [{ 'serviceBranch' => 'Marine Corps Reserve',
                                                                      'dateRange' => {
                                                                        'from' => '2000-01-01T00:00:00.000Z',
                                                                        'to' => '2010-01-16T00:00:00.000Z'
                                                                      } }] }
          coe_claim = create(:coe_claim, form: base_legacy_form.deep_merge(marine_reserves_service_period).to_json)
          form_data = base_form_data.deep_merge({
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'MARINES',
                                                    'serviceType' => 'RESERVE_NATIONAL_GUARD',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })
          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'send MARINES as branch for Marine Corps to LGY' do
        it 'sends the right data to LGY' do
          marine_corps_service_period = { 'periodsOfService' => [{ 'serviceBranch' => 'Marine Corps',
                                                                   'dateRange' => {
                                                                     'from' => '2000-01-01T00:00:00.000Z',
                                                                     'to' => '2010-01-16T00:00:00.000Z'
                                                                   } }] }
          coe_claim = create(:coe_claim, form: base_legacy_form.deep_merge(marine_corps_service_period).to_json)
          form_data = base_form_data.deep_merge({
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'MARINES',
                                                    'serviceType' => 'ACTIVE_DUTY',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })
          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'no loan information' do
        it 'sends the right data to LGY' do
          coe_claim = create(:coe_claim, form: base_legacy_form.deep_merge({ 'relevantPriorLoans' => [] }).to_json)
          form_data = base_form_data.deep_merge({
                                                  'veteran' => { 'vaHomeOwnIndicator' => false },
                                                  'relevantPriorLoans' => [],
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'AIR_FORCE',
                                                    'serviceType' => 'ACTIVE_DUTY',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })
          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end
    end

    context 'with v2_form version' do
      let(:relevant_prior_loans) do
        [{
          'vaLoanNumber' => '123123123123',
          'startDate' => '2017-01-01T00:00:00.000Z',
          'paidOffDate' => '',
          'loanAmount' => nil,
          'loanEntitlementCharged' => nil,
          'propertyOwned' => true,
          'oneTimeRestorationRequested' => false,
          'irrrlRequested' => true,
          'cashoutRefinaceRequested' => false,
          'noRestorationEntitlementIndicator' => false,
          'homeSellIndicator' => nil,
          'propertyAddress1' => '234',
          'propertyAddress2' => '234',
          'propertyCity' => 'asdf',
          'propertyState' => 'AL',
          'propertyCounty' => '',
          'propertyZip' => '11111',
          'propertyZipSuffix' => ''
        }, {
          'vaLoanNumber' => '456456456456',
          'startDate' => '2010-01-01T00:00:00.000Z',
          'paidOffDate' => '',
          'loanAmount' => nil,
          'loanEntitlementCharged' => nil,
          'propertyOwned' => true,
          'oneTimeRestorationRequested' => false,
          'irrrlRequested' => false,
          'cashoutRefinaceRequested' => true,
          'noRestorationEntitlementIndicator' => false,
          'homeSellIndicator' => nil,
          'propertyAddress1' => '939393',
          'propertyAddress2' => '234',
          'propertyCity' => 'asdf',
          'propertyState' => 'AL',
          'propertyCounty' => '',
          'propertyZip' => '11111',
          'propertyZipSuffix' => ''
        }]
      end

      it 'sends the right data to LGY with v2 form structure' do
        coe_claim = create(:coe_claim, form: base_v2_form.to_json)
        form_data = base_form_data.deep_merge({
                                                'relevantPriorLoans' => relevant_prior_loans,
                                                'periodsOfService' => [{
                                                  'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                  'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                  'militaryBranch' => 'AIR_FORCE',
                                                  'serviceType' => 'ACTIVE_DUTY',
                                                  'disabilityIndicator' => false
                                                }]
                                              })

        expect_any_instance_of(LGY::Service)
          .to receive(:put_application)
          .with(payload: form_data)
          .and_return({})
        coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
      end

      context 'send AIR_FORCE as branch for Air National Guard to LGY with v2 form' do
        it 'sends the right data to LGY' do
          air_ng_service_period = { 'militaryHistory' => { 'periodsOfService' =>
          [{ 'serviceBranch' => 'ANG',
             'dateRange' => {
               'from' => '2000-01-01T00:00:00.000Z',
               'to' => '2010-01-16T00:00:00.000Z'
             } }] } }
          coe_claim = create(:coe_claim, form: base_v2_form.deep_merge(air_ng_service_period).to_json)
          form_data = base_form_data.deep_merge({
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'AIR_FORCE',
                                                    'serviceType' => 'RESERVE_NATIONAL_GUARD',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })

          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'send MARINES as branch for Marine Corps Reserve to LGY with v2 form' do
        it 'sends the right data to LGY' do
          marine_reserves_service_period = { 'militaryHistory' => { 'periodsOfService' =>
          [{ 'serviceBranch' => 'MCR',
             'dateRange' => {
               'from' => '2000-01-01T00:00:00.000Z',
               'to' => '2010-01-16T00:00:00.000Z'
             } }] } }
          coe_claim = create(:coe_claim, form: base_v2_form.deep_merge(marine_reserves_service_period).to_json)
          form_data = base_form_data.deep_merge({
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'MARINES',
                                                    'serviceType' => 'RESERVE_NATIONAL_GUARD',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })

          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'send MARINES as branch for Marine Corps to LGY with v2 form' do
        it 'sends the right data to LGY' do
          marine_corps_service_period = { 'militaryHistory' => { 'periodsOfService' =>
          [{ 'serviceBranch' => 'MC',
             'dateRange' => {
               'from' => '2000-01-01T00:00:00.000Z',
               'to' => '2010-01-16T00:00:00.000Z'
             } }] } }
          coe_claim = create(:coe_claim, form: base_v2_form.deep_merge(marine_corps_service_period).to_json)
          form_data = base_form_data.deep_merge({
                                                  'veteran' => { 'vaLoanIndicator' => true },
                                                  'relevantPriorLoans' => relevant_prior_loans,
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'MARINES',
                                                    'serviceType' => 'ACTIVE_DUTY',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })

          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end

      context 'no loan information with v2 form' do
        it 'sends the right data to LGY with no prior VA loans' do
          no_loan_history = { 'loanHistory' => { 'hadPriorLoans' => false, 'relevantPriorLoans' => [] } }
          coe_claim = create(:coe_claim, form: base_v2_form.deep_merge(no_loan_history).to_json)
          form_data = base_form_data.deep_merge({
                                                  'veteran' => { 'vaLoanIndicator' => false,
                                                                 'vaHomeOwnIndicator' => false },
                                                  'relevantPriorLoans' => [],
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'AIR_FORCE',
                                                    'serviceType' => 'ACTIVE_DUTY',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })

          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end

        it 'sends the right data to LGY when loanHistory is replaced with no prior loans' do
          base_v2_form['loanHistory'] = {
            'certificateUse' => 'HOME_PURCHASE',
            'hadPriorLoans' => false,
            'relevantPriorLoans' => []
          }
          coe_claim = create(:coe_claim, form: base_v2_form.to_json)
          form_data = base_form_data.deep_merge({
                                                  'veteran' => { 'vaLoanIndicator' => false,
                                                                 'vaHomeOwnIndicator' => false },
                                                  'relevantPriorLoans' => [],
                                                  'periodsOfService' => [{
                                                    'enteredOnDuty' => '2000-01-01T00:00:00.000Z',
                                                    'releasedActiveDuty' => '2010-01-16T00:00:00.000Z',
                                                    'militaryBranch' => 'AIR_FORCE',
                                                    'serviceType' => 'ACTIVE_DUTY',
                                                    'disabilityIndicator' => false
                                                  }]
                                                })

          expect_any_instance_of(LGY::Service)
            .to receive(:put_application)
            .with(payload: form_data)
            .and_return({})
          coe_claim.send_to_lgy(edipi: '1222333222', icn: '1112227772V019333')
        end
      end
    end
  end
end
