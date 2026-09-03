# IVC ChampVa
This module allows you to generate form_mappings based on a PDF file.
With this in place, you can submit a form payload from the vets-website
and have this module map that payload to the associated PDF and submit it
to PEGA via S3.

PEGA has the ability to hit an endpoint to update the database table `ivc_champva_forms`
with their `case_id` and `status` in the payload.

## Key Features

### VES Integration
The module includes a VES (Veterans Eligibility System) integration for CHAMPVA form submissions. Eligible form data is automatically formatted and submitted to the VES API, which validates and processes CHAMPVA applications.

The VES integration follows a specific workflow:

1. **Conditional Submission Logic** (`should_process_ves?`):
   - Form 10-10d (CHAMPVA Application) is **always** submitted to VES
   - Standalone form 10-7959c (OHI) is submitted to VES only when the `champva_send_7959c_to_ves` flag is enabled
   - There is no hard environment check; which VES endpoint is hit (real vs. mocked) is controlled per-environment via `Settings.ivc_champva_ves_api` configuration

2. **Submission Ordering**:
   - The system first prepares both the PEGA submission (PDF generation) and VES submission (data formatting)
   - PDF files are uploaded to S3 for PEGA processing first
   - Only if the S3 upload is successful (status 200) will the system proceed with the VES submission
   - This ensures that application data is never sent to VES without a corresponding successful PDF submission

3. **Data Transformation**:
   - Raw form data is transformed into VES-compatible format by the `VesDataFormatter`
   - The formatter creates a structured `VesRequest` object with applicant, sponsor, and beneficiary information
   - The system performs extensive validation on the transformed data before submission

4. **Error Handling and Resilience**:
   - VES submission errors are logged but do not prevent the overall form submission from succeeding
   - This design ensures that PEGA processing can continue even if VES is unavailable
   - Any failed VES submissions are tracked in the database with their status and full request payload
   - The `VesRetryFailuresJob` background job automatically retries failed submissions periodically

5. **Database Storage**:
   - VES submission data is encrypted using KMS before being stored in the database
   - Each successful submission updates the corresponding form record with:
     - `application_uuid`: Unique identifier from VES
     - `ves_status`: Response status from VES
     - `ves_request_data`: Encrypted copy of the submitted data

### CHAMPVA Benefits Card
Authenticated `GET /ivc_champva/v1/champva_card` returns card metadata for the logged-in user. The frontend generates the printable PDF client-side from this JSON. Not `/v0/champva_card`.

Gated by Flipper `champva_benefits_card` (disabled → `404` `{ "error_message": "Not found" }`). Session ICN is sent to VES EE Summary (`ChampvaEligibilityService.benefits_card_for`). One call serves both the digital and physical card flows.

Success `200`:

```json
{
  "data": {
    "type": "champva_card",
    "attributes": {
      "role": "beneficiary",
      "beneficiary_infos": [
        {
          "icn": "1234567890V123456",
          "full_name": "Alex Doe",
          "date_of_birth": "1990-01-15",
          "mailing_address": {
            "line1": "123 Main St", "line2": null, "line3": null,
            "city": "Austin", "state": "TX", "province_code": null,
            "zip_code": "78701", "zip_plus4": null,
            "postal_code": null, "country": "USA"
          },
          "enrollment_status": "eligible",
          "eligibility_status": "Eligible",
          "eligibility_reason": "P&T",
          "sensitive_record": false,
          "relationship_type": "Child",
          "effective_date": "2020/02/01",
          "expiration_date": "2024/06/01"
        }
      ]
    }
  }
}
```

`X-Key-Inflection: camel` camelizes every key (`beneficiaryInfos`, `fullName`, `zipPlus4`, ...). `beneficiary_infos` is an array so the shape does not change when the sponsor flow returns one entry per beneficiary; today it always holds exactly one.

Field sources — VES EE Summary carries no name, date of birth, or subject ICN, so identity comes from the session (which resolves it from the MPI profile `UserLoader` already cached, costing no extra call):

| Field | Source |
|------|------|
| `icn`, `full_name`, `date_of_birth` | session |
| `mailing_address` | `demographics.contactInfo.addresses[]` |
| `sensitive_record` | `sensitivityInfo.sensitivityFlag` (`null` when absent — unknown, not false) |
| `eligibility_status` / `eligibility_reason` | `champvaEligibilities[].status` / `.reason`, passed through raw |
| `effective_date` / `expiration_date` | `eligibilityDates[].startDate` / `.endDate`, `%Y/%m/%d` |
| `relationship_type` | `relationships[].relationshipType` |

VES added `demographics` and `sensitivityInfo` to the dataset in Aug 2026, so every field above is populated in SQA. `mailing_address` is still `null` when VES omits `demographics`, when every address is filtered out, or when the beneficiary is ineligible — all three are optional/gated, not error cases.

Address selection: reject `badAddressReason` and past `endDate`, prefer `addressTypeCode` `P`/`Permanent` over `R`/`Residential`, tiebreak on latest `addressChangeDateTime`. VES returns one entry per type rather than a change history, so type decides and the tiebreak is defensive only. Real responses omit empty members entirely (`line2`, `line3`, `provinceCode`, `postalCode` were all absent from the SQA sample), and supply `county`, `addressChangeSource`, and `addressChangeSite`, which we ignore.

A `200` therefore always means "eligible, here is the card." Only `eligible` entries are enriched — `full_name`, `date_of_birth`, and `mailing_address` would be `null` otherwise, since the frontend renders nothing for them and the sponsor flow would otherwise pay an MPI call per beneficiary it discards.

Anyone else gets a `404`, under one of two distinct codes:

- **`ineligible`** — VES has a CHAMPVA record for this person but will not issue a card. `enrollment_status` carries the specific verdict. Per frontend preference the business logic stays on the backend and the UI renders static content, so no card data is returned; the service still computes it, so moving this to a `200` is a one-branch change in `render_ineligible`. **Whether this stays a 404 is still open.**
- **`not_enrolled`** — VES returned an empty payload. That covers both a veteran/sponsor querying their own ICN and a person with no CHAMPVA record; VES returns `{"data":{}}` for both, so they cannot be told apart (`determine_role`). The sponsor flow is disabled until VES ships a roster endpoint; when it does, empty becomes the positive signal to call it rather than a 404.

`enrollment_status` is our derived verdict, and `eligible` requires **both** an eligible VES status and a date window covering today:

| Value | Meaning | Result |
|------|------|------|
| `eligible` | VES says eligible and a window covers today | `200` + card |
| `ineligible` | VES denies, or no usable date window | `404` `ineligible` |
| `expired` | every window closed before today | `404` `ineligible` |
| `not_yet_effective` | every window opens after today | `404` `ineligible` |

Requiring the VES status closed a real hole: the shipped test fixture is `status: "Ineligible"` inside a live 2002 → 2024 window, so on the date-window logic alone that person was issued a card.

| Scenario | Status | Body |
|------|--------|------|
| Not signed in | `401` | existing auth error |
| Flipper off | `404` | `{ "error_message": "Not found" }` |
| Not LOA3 | `403` | `{ "error": { "code": "not_verified", "message": "..." } }` |
| No ICN | `422` | `{ "error": { "code": "missing_icn", "message": "..." } }` |
| Eligible beneficiary | `200` | card payload above |
| Ineligible / expired / not yet effective | `404` | `{ "error": { "code": "ineligible", "message": "...", "enrollment_status": "expired" } }` |
| Empty VES payload (veteran/sponsor or no record) | `404` | `{ "error": { "code": "not_enrolled", "message": "..." } }` |
| VES timeout | `504` | `{ "error": { "code": "upstream_timeout", "message": "..." } }` |
| Other VES / non-200 | `502` | `{ "error": { "code": "upstream_error", "message": "..." } }` |

LOA3 is required because `MPIData#profile` returns `nil` below it, leaving name, date of birth, and ICN all `nil` — without the guard an unverified user would get the misleading `missing_icn`.

Dataset: card flow passes the dedicated `ChampvaDigitalCardData` dataset into `get_ee_summary` (a smaller subset than `allEEData`); existing eligibility persist keeps the method default `CSTChampvaEligibility`. Out of scope: sponsor/beneficiary roster lookup, the physical-card request endpoint, Payor ID, PDF generation. Confirm with VES if printed-card expiration differs from `endDate`, and whether `confidentialAddressCategories` suppresses display of an address.

### Retry Mechanisms
The module implements a robust retry mechanism with configurable parameters for failed operations. An `IvcChampva::Retry` service handles retrying problematic operations with configurable max retries, delay, and condition-based retry logic. The system automatically retries when specific error messages occur during form processing.

### Email Notifications
The system includes an email notification service that sends confirmation emails to applicants once their form is processed by PEGA. Email templates are form-specific and dynamically selected based on the form number. Email notifications can be tracked and use custom callbacks for monitoring successful deliveries.

### Form Merging
The module supports merging 10-10d CHAMPVA applications with Other Health Insurance (OHI) forms through the `submit_champva_app_merged` endpoint, which automatically generates and attaches 10-7959c forms as supporting documents when applicants indicate they have other health insurance.

### Combined PDF Flow for FMP
The module includes a feature for Foreign Medical Program (FMP) claims that combines all submitted documents into a single PDF before submission to PEGA. When a form 10-7959f-2 (FMP Claim) is submitted:

1. The system collects all PDFs associated with the submission, including:
   - The main form (10-7959f-2)
   - All supporting documents (medical bills, receipts, medical records, etc.)
2. The `PdfCombiner` service merges these into a single coherent PDF document while preserving page order
3. The combined PDF is uploaded to S3 as a single file with appropriate metadata
4. The system tracks all original document filenames in the database for reference
5. A metadata JSON file is generated to trigger PEGA processing of the submission

### Performance Monitoring
The module has comprehensive monitoring through DataDog, tracking various metrics including form submissions, PEGA updates, VES interactions, and email notifications. Monitoring is managed through the `IvcChampva::Monitor` class, providing visibility into the system's performance and helping identify issues.

### Multi-form Processing
The system can process multiple PDF forms in a single submission, with appropriate attachment IDs assigned to each. This capability supports forms that may require multiple PDFs to be generated, such as forms with multiple applicants.

### Status Validation & Notifications
A `MissingFormStatusJob` background job automatically identifies forms that haven't received a status update from PEGA within a configurable timeframe and can send failure notification emails to users. This ensures forms don't get "lost" in the system without being processed.

A `NotifyPegaMissingFormStatusJob` similar to `MissingFormStatusJob` but sends emails to the Pega team.

### Enhanced PDF Handling
The module includes advanced PDF handling with features like:
- PDF authentication stamping showing the user's login status and time of submission (e.g., "Signed electronically and submitted via VA.gov at 15:30:45 Signee signed with an identity-verified account." or "Signee not signed in.")
- Digital signature application for forms requiring signatures
- Multi-page form support with conditional page generation
- PDF unlock capabilities for password-protected files
- Robust temp file management for high concurrency environments

### Error Handling
The system implements comprehensive error handling with consistent status codes and error messages. Failed operations are logged and tracked, with appropriate retry mechanisms for recoverable errors.

## Feature Flags
Current feature flags used to control functionality:

| Flag | Purpose | Notes |
|------|---------|-------|
| `champva_send_to_ves` | Enables sending form submission data to the VES API | Long-running feature flag pending integration signoff from VES team |
| `champva_log_all_s3_uploads` | Enables detailed logging for all S3 uploads |
| `champva_claims_insurance_dates` | Uses the 12/31/2027 OMB revision of 10-7959A (requires `champva_form_versioning`); shared with FE | Adds beneficiary email, OHI effective/termination dates, signer email on the PDF and in Pega metadata |
| `champva_send_7959c_to_ves` | Routes standalone 10-7959c (OHI) submissions to VES | 10-10d always routes to VES regardless of this flag |
| `champva_benefits_card` | Enables `GET /ivc_champva/v1/champva_card` | Returns CHAMPVA card metadata from VES EE Summary |
| (TODO) | Enables the endpoint to submit combined 10-10d/10-7959c form submissions | Feature is WIP |
|`form1010d_extended`|Enables access to the combined 10-10d/10-7959c form experience (frontend) |This form is a WIP|

## Uploads_Controller
The uploads_controller.rb file in the IVC Champva module is a key component of the application, responsible for handling file uploads. It contains several private methods that perform various tasks related to file uploads. The get_attachment_ids_and_form method constructs attachment IDs based on the parsed form data and also instantiates a new form object.

The supporting_document_ids method retrieves the IDs of any supporting documents included in the parsed form data. The get_file_paths_and_metadata method generates file paths and metadata for the uploaded files, and also handles any attachments associated with the form. The get_form_id method retrieves the ID of the form being processed.

## Helpful Links
- [Swagger API UI](https://software-vets-api.pages.va.ghe.com/) then search "https://dev-api.va.gov/v1/apidocs" to see the ivc_champva endpoint
- [Project MarkDowns](https://va.ghe.com/software/va.gov-team/tree/master/products/health-care/champva)
  - [Team Resource Repository](https://va.ghe.com/software/va.gov-team/blob/master/products/health-care/champva/team/team-resource-repository.md)
  - [VES Integration](https://va.ghe.com/software/va.gov-team/blob/master/products/health-care/champva/engineering/ves_use_case_and_objectives.md)
  - [Missing PEGA Status Playbook](https://va.ghe.com/software/va.gov-team/blob/master/products/health-care/champva/team/ivc-forms-monitoring-playbook.md)
- [DataDog Dashboard](https://vagov.ddog-gov.com/dashboard/zsa-453-at7/ivc-champva-forms)
- [Pega Callback API ADR](https://va.ghe.com/software/va.gov-team/blob/master/products/health-care/champva/ADR-callback-api-to-receive-status-from-pega.md)
- [Pega Callback API Implementation Plan](https://va.ghe.com/software/va.gov-team/blob/master/products/health-care/champva/callback-api-technical-spec.md)

## Endpoints
- `/ivc_champva/v1/forms` - Submit a CHAMPVA form
- `/ivc_champva/v1/forms/10-10d-ext` - Submit a 10-10d form with automatic OHI form generation (WIP)
- `/ivc_champva/v1/forms/submit_supporting_documents` - Upload supporting documents for a form
- `/ivc_champva/v1/forms/status_updates` - Receive status updates from PEGA
- `/ivc_champva/v1/champva_card` - Authenticated CHAMPVA benefits card metadata (Flipper `champva_benefits_card`)

## Supported Forms
The module currently supports the following forms:
- VHA 10-10d - CHAMPVA Application
- VHA 10-7959c - Other Health Insurance (OHI)
- VHA 10-7959f-1 - Foreign Medical Program Registration
- VHA 10-7959f-2 - Foreign Medical Program Claim
- VHA 10-7959a - CHAMPVA Claim

### Generate files for new forms
`rails ivc_champva:generate\['path to PDF file'\]`

### Updating expired forms
Form PDFs have an expiration date found in the upper right corner below the OMB control number.
To update a form with the latest PDF:
1. Locate the latest version of the form PDF via VA.gov
2. Save the PDF somewhere on disk. **Important:** for `generate_mapping`, the filename before `.pdf` must match the existing mapping basename (e.g. save as `vha_10_7959a.pdf` in a temp path), not `VA.Form....pdf`, or the task will derive the wrong form name.
3. Run `rails ivc_champva:generate_mapping\['path to PDF file'\]` - a file will be generated:
    - A JSON.erb mapping file in `modules/ivc_champva/app/form_mappings` (it will have "latest" in the name)
   - **Note:** `generate_mapping` compares field names to the existing `.json.erb` using `JSON.parse` on that file. If the current mapping is ERB (not pure JSON), that step fails—use `pdftk the.pdf dump_data_fields` (or `PdfForms#get_field_names` in `rails runner`) to list fields and update the mapping manually.
4. Compare the new mapping file with the existing one, updating mappings as appropriate.
5. When the mapping file is complete, replace the original mapping file with the new one, **or** add a versioned form: new template `templates/vha_{id}.pdf`, mapping `form_mappings/vha_{id}.json.erb`, model `app/models/ivc_champva/vha_{id}.rb`, register in `FormVersionManager` + `config/features.yml`, and gate with `champva_form_versioning` + a `champva_form_*` flag.
6. Replace the existing form PDF found in `modules/ivc_champva/templates/vha_{FORM NUMBER}.pdf` with the new one (for a new revision, add a new template file instead of overwriting when using `FormVersionManager`).
7. Verify stamping behavior by running ivc_champva unit tests locally and observing the generated PDFs in the `tmp` directory.
8. Adjust the form OMB expiration unit test found in `modules/ivc_champva/spec/models/vha_{FORM NUMBER}_spec.rb`

### Installation
Ensure the following line is in the root project's Gemfile:

  `gem 'ivcchampva', path: 'modules/ivcchampva'`

### License
This module is open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
