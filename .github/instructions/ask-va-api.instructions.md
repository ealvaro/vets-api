---
applyTo: "modules/ask_va_api/**/*"
---

# Ask VA API Module Instructions

## Module Overview

`ask_va_api` is a Rails engine at `modules/ask_va_api/` that proxies between the AskVA frontend and the VA CRM (Dynamics). It handles inquiry submission, static reference data, and CRM payload translation.

## CRM Data Flow — Optionset Cache and Translation

The CRM optionset data has **two independent consumers** — be careful not to confuse internal usage with external route surface.

### Internal (load-bearing)
- `Crm::CacheData` fetches and caches CRM data in Redis (60-minute TTL)
- `AskVAApi::Translator` uses cached optionset to map frontend values → CRM option IDs for fields like `response_type`, `dependent_relationship`, `inquiry_about`, `level_of_authentication`
- `Crm::OptionsetDataJob` pre-warms the optionset cache via Sidekiq

### External (route surface)
- Routes in `config/routes.rb` map to `StaticDataController` actions
- A route can exist without a corresponding controller action — verify before assuming an endpoint works

**When removing or modifying CRM-related routes, always verify the internal cache/translation pipeline is preserved.** The `Translator` is used during inquiry creation and is not coupled to any external route.

## StaticDataController Pattern

The controller uses a `get_resource` private method that dynamically resolves classes by convention:

```ruby
# For resource_type 'categories':
AskVAApi::Categories::Retriever  # fetches data
AskVAApi::Categories::Serializer # serializes response
AskVAApi::Categories::Entity     # data model
```

Each endpoint needs an explicit public action method in the controller **and** the corresponding Retriever/Serializer/Entity classes. A route without both will fail at runtime.

### Removing a StaticDataController Endpoint

When deprecating an endpoint (e.g., `announcements`, `optionset`), remove **all 7+ artifacts** in this order:

1. **Route** — `config/routes.rb` (delete the `get` line)
2. **Controller action** — `app/controllers/ask_va_api/v0/static_data_controller.rb` (delete the method)
3. **Lib classes** — delete the entire directory `app/lib/ask_va_api/<resource>/` (entity.rb, retriever.rb, serializer.rb)
4. **Mock data** — delete `config/locales/get_<resource>_mock_data.json` **only if the resource has a dedicated mock file**. Some resources (e.g. the former `contents`, and `categories`/`topics`/`subtopics`) read the shared `config/locales/static_data.json` instead — do **not** delete that shared file.
5. **Request spec block** — remove the `describe` block from `spec/requests/ask_va_api/v0/static_data_spec.rb`
6. **Lib specs** — delete the entire directory `spec/app/lib/ask_va_api/<resource>/`
7. **Grep check** — confirm zero remaining references to the resource name in `modules/ask_va_api/`

**Do NOT touch** the shared `get_resource` private method or any other endpoint's code.

## Test Layout

| Type | Location |
|------|----------|
| Request specs | `spec/requests/ask_va_api/v0/` |
| Lib/model specs | `spec/app/lib/ask_va_api/` |
| Service specs | `spec/services/crm/` |
| Sidekiq job specs | `spec/sidekiq/crm/` |
| Mock data | `config/locales/get_*_mock_data.json` |

### Key specs for CRM-related changes
```bash
# Translator (optionset → CRM ID mapping)
bundle exec rspec modules/ask_va_api/spec/app/lib/ask_va_api/translator_spec.rb

# CRM cache service
bundle exec rspec modules/ask_va_api/spec/services/crm/cache_data_spec.rb

# Inquiry creation (exercises full CRM payload pipeline)
bundle exec rspec modules/ask_va_api/spec/requests/ask_va_api/v0/inquiries_spec.rb
```
