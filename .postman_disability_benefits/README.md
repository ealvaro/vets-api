# Disability Benefits - Postman Collection

Postman collection for testing Disability Benefits API endpoints locally.

## Import

1. Open Postman
2. Click **Import** → select `Disability Benefits.postman_collection.json`

## Setup

After importing, edit the collection variables in Postman as needed (e.g. `base_url`, `profile_key`, `attachment_id`). These changes live inside Postman's internal storage and won't affect the committed files.

## Running

1. Ensure your local vets-api server is running on the configured `base_url`
2. Select a request and click **Send**
3. The collection pre-request script will automatically authenticate via the mocked sign-in flow

## Authentication

The collection-level pre-request script handles the full mocked authentication flow automatically:

1. Calls `/v0/sign_in/authorize` to get a signed state
2. Fetches available mock profiles from `/mocked_authentication/credential_list`
3. Authenticates via `/mocked_authentication/authorize` → `/v0/sign_in/callback`
4. Exchanges the login code for an access token at `/v0/sign_in/token`

The resulting `access_token` is stored as a collection variable and used by all requests.

## CSRF Token

If the requests requires a `X-CSRF-Token` header run the **Get CSRF Token** request manually to populate the `csrf_token` collection variable for use in the request.

## Endpoints

### Upload Supporting Evidence

Uploads a file via multipart POST to `/v0/upload_supporting_evidence`.

- In the **Body** tab, use the file picker for `supporting_evidence_attachment[file_data]` to select the PDF
- Set the `attachment_id` collection variable (e.g. `L1839`) to test document validation; leave empty to skip

## Notes

- Postman does not support variable substitution for file paths in form-data. Use the file picker in the UI to select files.
- The `access_token` is auto-populated by the pre-request script.
- To update the collection for the team, export from Postman and commit the updated JSON.
