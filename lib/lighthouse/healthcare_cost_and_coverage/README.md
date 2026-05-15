# Healthcare Cost and Coverage API requests
This serves as documentation for the requests we make to the Lighthouse Healthcare Cost and Coverage API. You can find ICN's for the sandbox environment [here](https://developer.va.gov/explore/api/health-care-costs-coverage/test-users). 

To make these requests, you will need:
1. [Lighthouse sandbox credentials](https://developer.va.gov/explore/api/health-care-costs-coverage/client-credentials)
2. A working `rails console`
3. Mock data turned off in your `settings.local.yml` file

With some of these calls, an ID is required. You will have to run a 'collection' request and grab an ID from there.

## Service calls
These are what's called by the controller.

### List request
`service = MedicalCopays::LighthouseIntegration::Service.new(<icn>)`

`cool = service.list(count: 250, page: 1)`

### Month request (used by endpoint)
`service = MedicalCopays::LighthouseIntegration::Service.new(<icn>)`

`response = service.list_months(month_count: 250)`

### Summary request
`service = MedicalCopays::LighthouseIntegration::Service.new(<icn>)`

`response = service.summary(month_count: 19)`

## Resource calls
These are what's called by the service.

### Invoice resource
`require 'lighthouse/healthcare_cost_and_coverage/invoice/service'`

`service = ::Lighthouse::HealthcareCostAndCoverage::Invoice::Service.new(<icn>)`

Collection: `response = service.list(count: 50, page: 1)`

Single record: `response = service.read(<invoice id>)`

### Patient resource
`require 'lighthouse/healthcare_cost_and_coverage/patient/service'`

`service = ::Lighthouse::HealthcareCostAndCoverage::Patient::Service.new(<icn>)`

`response = service.read(<icn>)`

### Account resource

#### Getting the Account ID 
Data from invoice request: `invoice_data = <invoice data>.with_indifferent_access`
`account_ref = invoice_data.dig('account', 'reference')`
`account_id = account_ref.split('/').last`

`require 'lighthouse/healthcare_cost_and_coverage/account/service'`

`service = ::Lighthouse::HealthcareCostAndCoverage::Account::Service.new(<icn>)`

`response = service.list(id: <account id>)`

### ChargeItem resource
`require 'lighthouse/healthcare_cost_and_coverage/charge_item/service'`

`CHARGE_ITEM_FETCH_LIMIT = 100`

`service = Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service.new(<icn>)`

`response = service.list(count: CHARGE_ITEM_FETCH_LIMIT)`

### PaymentReconciliation resource
`require 'lighthouse/healthcare_cost_and_coverage/payment_reconciliation/service'`

`PAYMENT_FETCH_LIMIT = 100`

`service = ::Lighthouse::HealthcareCostAndCoverage::PaymentReconciliation::Service.new(<icn>)`

`response = service.list(count: PAYMENT_FETCH_LIMIT)`

### Organization resource
`require 'lighthouse/healthcare_cost_and_coverage/organization/service'`

`invoice_data = <data from invoice read call>.with_indifferent_access`

`org_ref = invoice_data.dig('issuer', 'reference')`

`org_id = org_ref.split('/').last`

`service = ::Lighthouse::HealthcareCostAndCoverage::Organization::Service.new(<icn>)`

`response = service.read(<organization id>)`

### Encounter resource
`require 'lighthouse/healthcare_cost_and_coverage/encounter/service'`

`ENCOUNTER_FETCH_LIMIT = 200`

`service = ::Lighthouse::HealthcareCostAndCoverage::Encounter::Service.new(<icn>)`

`response = service.list(count: ENCOUNTER_FETCH_LIMIT)`

### Medication Dispense resource
`require 'lighthouse/healthcare_cost_and_coverage/medication_dispense/service'`

`service = ::Lighthouse::HealthcareCostAndCoverage::MedicationDispense::Service.new(<icn>)`

`response = service.list(id: <medication dispense id>)`

### Medication resource
`require 'lighthouse/healthcare_cost_and_coverage/medication/service'`

`service = ::Lighthouse::HealthcareCostAndCoverage::Medication::Service.new(<icn>)`

`medications = service.list(id: <medication id>)`