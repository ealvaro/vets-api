# 2. Making the digital-forms-api form agnostic and not hardcoded to 686c

Date: 2026-05-27

## Status

Accepted

Amended 2026-07-09: the PORO is renamed `DigitalFormsApi::SubmissionResponse` (originally `DigitalFormsApi::Submission`) — the status-tracking work (A1, 2026-06) has since claimed `DigitalFormsApi::Submission` for its ActiveRecord persistence model, so the name is updated throughout below. §5's `SubmissionHelper` has also since shipped (A2) with a keyword signature (`claim:`, `payload:`, `participant_id:`, `claim_label:`, `user_account:`) and `epCode` derived from the claim label's leading digits, superseding the positional sketch in §5.

Amended 2026-07-13: the first `SubmissionResponse` slice has shipped as a behavior-preserving extraction — its constructor takes only the retrieve response (`SubmissionResponse.new(response)`) and it exposes just `#veteran_id` and `#payload`, the two fields the controller reads today. The two-argument constructor, `plugin`/`form_id` resolution, template translation, and serializer shown in §1/§3/§4 remain the target design, not yet built (the `params[:id]` second argument there feeds §3's `submission_id`).

## Context

The `digital_forms_api` (FDF / FormsAPI) module treats 21-686c as its only form: `FORM_ID = '21-686c'` is hardcoded in `submissions_controller.rb` (6 references), a dependents-named Flipper flag is referenced directly, and the controller leaks the upstream BIP shape via `dig('envelope', ...)` while dropping `submissionId`, `claim`, and `document` metadata.

The shared services (`Service::Submissions`, `Service::Templates`), routes, and template caching are already form-agnostic. The only barriers to a second form are controller-level assumptions and per-form concerns (Flipper flag, authorization, saved-claim class) that live in the controller.

Scoped to `modules/digital_forms_api` and its direct integrators. Out-of-scope follow-ups (e.g. CE metadata indexing) will be filed as separate tickets.

## Decision

Move per-form concerns into a thin plugin layer, isolate the upstream shape behind a PORO, and lock down the wire format with a serializer.

### 1. PORO — isolates the upstream shape

`DigitalFormsApi::SubmissionResponse` wraps the `Service::Submissions#retrieve` response. The initial shipped slice exposes only `#veteran_id` and `#payload`; the following accessors are part of the target design: `form_id`, `veteran_id_hash`, `ep_code`, `claim_label`, `source_request_id` (from `envelope`), `claim_metadata`, `document_metadata` (from `submission` — currently dropped), `template_details`, `template_version` (set by controller after lookup), and `plugin` (`Forms.resolve(form_id)`, lazily memoized).

The PORO will also translate the nested template shape (`template['formTemplate']['formTemplate'][form_id]`) into the flat `template_details`/`template_version` attributes the serializer expects, keeping both BIP shapes isolated in one place.

### 2. Plugin layer — self-registering, no central map

```ruby
module DigitalFormsApi::Forms
  def self.register(form_id, klass) = registry[form_id] = klass
  def self.resolve(form_id) = registry[form_id] || Base
  def self.supported_ids = registry.keys
  def self.registry = @registry ||= {}
end
```

The engine eager-loads plugins via `config.eager_load_paths`:

```ruby
# in engine.rb
initializer 'digital_forms_api.eager_load_forms' do
  forms_path = root.join('lib', 'digital_forms_api', 'forms')
  config.eager_load_paths << forms_path.to_s if forms_path.exist?
end
```

Form ID strings decouple from Ruby class names (`21P-530` needs no contorted constant). This diverges from `simple_forms_api`'s explicit `FORM_NUMBER_MAP`; the trade-off is one less file to edit per new form at the cost of relying on eager-load.

`Forms::Base` declares `class_attribute :flipper_flag, :saved_claim_class`, a `self.form_id(id)` macro that self-registers, `enabled_for?(current_user)`, and `denial_reason_for(submission, current_user)` (lifted verbatim from the current controller — returns `'missing_participant_id'`, `'malformed_veteran_id'`, `'identifier_type_mismatch'`, `'participant_id_mismatch'`, or `nil`).

`Forms::VBA21686c < Base` declares `form_id '21-686c'`, `flipper_flag`, and `saved_claim_class`.

**Deferred** (per review with @Yang-Yang1): `before_submit`/`after_submit` hooks, `notification_personalization`, per-form `serializer_attributes` — add when a second form needs them.

### 3. Serializer

`DigitalFormsApi::SubmissionSerializer` (`JSONAPI::Serializer`) emits a uniform shape: `submission`, `template`, `form_id`, `submission_id`, `template_version`, `claim_metadata`, `document_metadata`. No per-form escape hatch. Rendered via `serializable_hash[:data][:attributes]`.

### 4. Controller

**Form ID is discovered post-retrieval.** The controller calls `retrieve(params[:id])` without a form ID — `envelope.formId` comes from the BIP response, extracted by the PORO. Gating (Flipper, authorization) happens after the round-trip, which is acceptable since the controller is deciding whether the *current user* may view an existing submission.

```ruby
sub = SubmissionResponse.new(submissions_service.retrieve(params[:id]), params[:id])
return bad_request if sub.form_id.blank?
return render_forbidden(:feature_flag_disabled) unless sub.plugin.enabled_for?(current_user)
if (reason = sub.plugin.denial_reason_for(sub, current_user))
  return render_forbidden(reason)
end
template = templates_service.template(sub.form_id)
sub.template_details = template['templateDetails']
sub.template_version = template['templateVersion']
render json: SubmissionSerializer.new(sub).serializable_hash[:data][:attributes]
```

Delete the `FORM_ID` constant. Telemetry passes `form_id` from the PORO. `render_forbidden` preserves existing logging and telemetry contracts.

### 5. SubmissionHelper

`DigitalFormsApi::SubmissionHelper.submit(claim, payload, veteran_pid, claimant_pid, claim_label, ep_code)` builds the metadata envelope, resolves the plugin from `claim.claim_form_type`, and calls `Service::Submissions#submit`. The duplicate `submit_via_forms_api` methods in `v0/dependents_applications_controller` and `dependents_benefits/.../claims_controller` collapse into this.

**Form ID contract:** `SavedClaim` subclasses must return a form ID matching what the plugin registered. Each plugin spec should assert alignment:

```ruby
it 'matches the SavedClaim form constant' do
  expect(SavedClaim::DependencyClaim::FORM).to eq('21-686c')
  expect(DigitalFormsApi::Forms.resolve('21-686c')).to eq(DigitalFormsApi::Forms::VBA21686c)
end
```

`documentation/adding_a_form.md` should include this spec as a required step. Heavy forms (e.g. 526) opt out of `SubmissionHelper` and use the plugin only for Flipper flag lookup / form ID resolution.

### Files

| Action | Path |
| --- | --- |
| edit  | `modules/digital_forms_api/app/controllers/digital_forms_api/submissions_controller.rb` |
| new   | `modules/digital_forms_api/app/models/digital_forms_api/submission_response.rb` (PORO) |
| new   | `modules/digital_forms_api/app/serializers/digital_forms_api/submission_serializer.rb` |
| new   | `modules/digital_forms_api/lib/digital_forms_api/forms/base.rb` |
| new   | `modules/digital_forms_api/lib/digital_forms_api/forms/vba_21_686c.rb` |
| new   | `modules/digital_forms_api/lib/digital_forms_api/submission_helper.rb` |
| edit  | `modules/digital_forms_api/lib/digital_forms_api/engine.rb` (eager-load `forms/`) |
| edit  | `app/controllers/v0/dependents_applications_controller.rb` |
| edit  | `modules/dependents_benefits/app/controllers/dependents_benefits/v0/claims_controller.rb` |
| new   | `documentation/adding_a_form.md` |
| new   | Specs for each new class |

## Consequences

**Easier:** Adding a new lightweight form requires one plugin file (~10 lines) plus a cassette — no controller, serializer, or service changes. The upstream BIP shape lives in exactly one place. Previously dropped metadata is surfaced. Plugin classes are unit-testable in isolation.

**Risks:** Self-registration relies on engine eager-load; a form file not in `lib/digital_forms_api/forms/` won't register. Covered by `documentation/adding_a_form.md` and verification step 7.

**Non-goals:** No central registry, no attachment/overflow hooks, no Rails generator, no PDF generation (BIP handles it), no JSON:API breaking change, no frontend changes.

**Future work:** CE metadata indexing for Caseflow Reader (separate ticket). Hook expansion (`before_submit`, `after_submit`) — add when a second form needs them.

## Verification

1. `bundle exec rspec modules/digital_forms_api/spec` — passes with at least two `Forms::*` classes exercised.
2. `bundle exec rspec spec/controllers/v0/dependents_applications_controller_spec.rb modules/dependents_benefits/spec` — integrators pass after switching to `SubmissionHelper`.
3. `bundle exec rubocop` — clean.
4. Manual: `GET /digital_forms_api/v0/submissions/:id` returns 200 with full shape; 400 when `formId` blank; 403 on auth/gating failure.
5. Re-vendor `schema/openapi.json` in `fdf-previewer`; run `va-payload-lint` against existing fixtures.
6. Smoke test in `form-renderer` sandbox — 686c flow unchanged.
7. Drop a throwaway plugin (`Forms::Test99999 < Base`, `form_id '99-TEST'`, stub Flipper flag, VCR cassette with `formId: '99-TEST'`) → 200 with serialized shape, proving no 686c-specific logic fires. Zero other code edits needed. Revert after.
