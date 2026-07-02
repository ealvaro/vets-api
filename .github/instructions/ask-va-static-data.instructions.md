---
applyTo: "modules/ask_va_api/app/controllers/ask_va_api/v0/static_data_controller.rb,modules/ask_va_api/app/lib/ask_va_api/base_retriever.rb,modules/ask_va_api/app/lib/ask_va_api/categories/**/*,modules/ask_va_api/app/lib/ask_va_api/contents/**/*,modules/ask_va_api/app/lib/ask_va_api/topics/**/*,modules/ask_va_api/app/lib/ask_va_api/subtopics/**/*,modules/ask_va_api/app/lib/ask_va_api/announcements/**/*,modules/ask_va_api/spec/app/lib/ask_va_api/categories/**/*,modules/ask_va_api/spec/app/lib/ask_va_api/contents/**/*,modules/ask_va_api/spec/app/lib/ask_va_api/topics/**/*,modules/ask_va_api/spec/app/lib/ask_va_api/subtopics/**/*,modules/ask_va_api/spec/requests/ask_va_api/v0/static_data_spec.rb,modules/ask_va_api/config/routes.rb"
---

# Copilot Instructions for Ask VA API / Static Data

**Path-Specific Instructions for the `ask_va_api` module's static data endpoints**

These instructions automatically apply when working with:
- **Controller:** `StaticDataController` — all static data endpoints (`/categories`, `/contents`, `/announcements`, etc.)
- **Retrievers/Entities/Serializers:** Classes under `app/lib/ask_va_api/{resource}/`
- **Base class:** `BaseRetriever` — shared superclass for all retrievers
- **Specs:** Request specs in `spec/requests/ask_va_api/v0/static_data_spec.rb` and unit specs under `spec/app/lib/ask_va_api/`

---

## `get_resource` Dynamic Resolution Pattern

`StaticDataController` uses a convention-based pattern to dynamically resolve classes. A controller action calls `get_resource('resource_name')` which resolves to three classes via `constantize`:

- `AskVAApi::{ResourceName}::Retriever`
- `AskVAApi::{ResourceName}::Serializer`
- `AskVAApi::{ResourceName}::Entity`

**Pattern:**
```ruby
# Controller action — just call get_resource with the resource name
def categories
  get_resource('categories', user_mock_data: params[:user_mock_data])
  render_result(@categories)
end
```

The resource name string (`'categories'`) is `.camelize`d to resolve class constants, so `'categories'` → `AskVAApi::Categories::Retriever`, etc. The instance variable is set as `@categories` (matching the resource name).

**Anti-pattern:**
```ruby
# DON'T reuse another resource's classes to avoid creating new ones.
# This creates coupling that prevents clean removal later.
def categories
  get_resource('contents', user_mock_data: params[:user_mock_data], type: 'category')
  render_result(@contents)
end
```

**Why:** Each endpoint should have its own Retriever/Entity/Serializer triad so that deprecated endpoints (like `/contents`) can be fully removed without breaking newer endpoints.

---

## BaseRetriever Subclass Pattern

### When to use
When adding a new static data endpoint to `StaticDataController`.

### Required files (the "triad")

For a resource named `foo`, create three files:

1. **Retriever** — `app/lib/ask_va_api/foo/retriever.rb`
2. **Entity** — `app/lib/ask_va_api/foo/entity.rb`
3. **Serializer** — `app/lib/ask_va_api/foo/serializer.rb`

### Retriever pattern
```ruby
module AskVAApi
  module Foo
    class Retriever < BaseRetriever
      private

      def fetch_data
        data = user_mock_data ? static_data : fetch_from_cache
        filter_data(data)
      end

      def static_data
        @static_data ||= begin
          static = File.read('modules/ask_va_api/config/locales/static_data.json')
          JSON.parse(static, symbolize_names: true)
        end
      end

      def fetch_from_cache
        Crm::CacheData.new.call(endpoint: 'Topics', cache_key: 'categories_topics_subtopics')
      end

      def filter_data(data)
        # Filter and sort the raw data for this resource type
      end
    end
  end
end
```

Key points:
- Do **not** override `initialize` if you only need `user_mock_data:` and `entity_class:` — `BaseRetriever` provides these.
- Override `initialize` only when the retriever needs additional keyword arguments (e.g., `Contents::Retriever` takes `type:` and `parent_id:`).
- `BaseRetriever#call` handles mapping raw data through `entity_class` and error rescue via `ErrorHandler`.

### Entity pattern
```ruby
module AskVAApi
  module Foo
    class Entity
      attr_reader :id, :name  # ... all attributes

      def initialize(info)
        @id = info[:Id]        # Map CRM PascalCase keys
        @name = info[:Name]
      end
    end
  end
end
```

### Serializer pattern
```ruby
module AskVAApi
  module Foo
    class Serializer
      include JSONAPI::Serializer
      set_type :foo  # Must match the endpoint/resource name

      attributes :name  # ... all serialized attributes
    end
  end
end
```

**Critical:** `set_type` must match the resource name. The JSONAPI response `type` field will be this value.

---

## Nested Route / Child Resource Pattern

### When to use
When adding an endpoint with a parent resource in the URL (e.g., `/categories/:category_id/topics`).

### Controller action
Map the route param to the retriever's `parent_id` kwarg:
```ruby
def topics
  get_resource('topics', user_mock_data: params[:user_mock_data], parent_id: params[:category_id])
  render_result(@topics)
end

def subtopics
  get_resource('subtopics', user_mock_data: params[:user_mock_data], parent_id: params[:topic_id])
  render_result(@subtopics)
end
```

The route param name (`category_id`, `topic_id`) comes from the route definition in `routes.rb`. The retriever always receives it as `parent_id`.

### Retriever with `parent_id:`
Override `initialize` to accept `parent_id:`, then filter by `ParentId == @parent_id`:
```ruby
module AskVAApi
  module Topics
    class Retriever < BaseRetriever
      def initialize(parent_id:, **args)
        super(**args)
        @parent_id = parent_id
      end

      private

      def fetch_data
        data = user_mock_data ? static_data : fetch_from_cache
        filter_data(data)
      end

      # ... static_data and fetch_from_cache same as base pattern ...

      def filter_data(data)
        return [] if data[:Topics].blank?

        data[:Topics]
          .select { |topic| topic[:ParentId] == @parent_id }
          .sort_by { |topic| topic[:Name] }
      end
    end
  end
end
```

**Why `**args` + `super`:** `get_resource` merges `entity_class:` into the options hash before calling `retriever_class.new(**options)`. Using `**args` captures `user_mock_data:` and `entity_class:` and forwards them to `BaseRetriever#initialize` via `super`.

## Data Source: CRM Cache

Static data endpoints share the same CRM cache:
- **Endpoint:** `'Topics'`
- **Cache key:** `'categories_topics_subtopics'`
- **Service:** `Crm::CacheData.new.call(endpoint:, cache_key:)`

The cache returns a hash with `{ Topics: [...] }`. Each item has:
- `Id`, `Name`, `ParentId`, `Description`, `RequiresAuthentication`, `AllowAttachments`, `RankOrder`, `DisplayName`, `TopicType`, `ContactPreferences`

Filtering by hierarchy:
- **Categories:** `ParentId.nil?` (top-level), sorted by `RankOrder`
- **Topics:** `ParentId == category_id`, sorted by `Name`
- **Subtopics:** `ParentId == topic_id`, sorted by `Name`

Mock data: `modules/ask_va_api/config/locales/static_data.json` (used when `user_mock_data` param is truthy).

---

## Endpoint Removal Checklist

### When to use
When removing a deprecated static data endpoint from `StaticDataController`.

### Artifacts to remove (the "full triad + wiring")

For a resource named `foo`, delete these files and code:

| # | Artifact | Path/Location |
|---|----------|---------------|
| 1 | Route | `config/routes.rb` — the `get` line |
| 2 | Controller action | `static_data_controller.rb` — the `def foo` method |
| 3 | Retriever | `app/lib/ask_va_api/foo/retriever.rb` |
| 4 | Entity | `app/lib/ask_va_api/foo/entity.rb` |
| 5 | Serializer | `app/lib/ask_va_api/foo/serializer.rb` |
| 6 | Mock data | `config/locales/get_foo_mock_data.json` (if separate from `static_data.json`) |
| 7 | i18n mock list | `config/locales/en.yml` — the data list used by the retriever's mock mode |
| 8-10 | Spec files | `spec/app/lib/ask_va_api/foo/{retriever,entity,serializer}_spec.rb` |
| 11 | Request spec block | `spec/requests/ask_va_api/v0/static_data_spec.rb` — the `describe` block |

Also check: `require` statements in the controller that were only needed by the removed retriever (e.g., `require 'brd/brd'`).

### Critical: Preserve CRM payload field references

Field names like `branch_of_service` can appear in **two unrelated contexts**:
1. **Endpoint code** (the triad, route, mock data) — REMOVE
2. **CRM payload fields** (inquiry builders, translator, optionset cache) — KEEP

Before removing, grep the module to distinguish endpoint-specific references from CRM payload references:

```bash
# Find ALL references — then classify each as endpoint vs. CRM payload
grep -rn "foo_name" modules/ask_va_api/app/ modules/ask_va_api/config/
```

**Anti-pattern:**
```bash
# DON'T blindly remove all references matching the resource name.
# CRM payload builders and optionset cache use the same field names.
```

**Why:** The CRM `Translator` and inquiry payload builders (`veteran_profile.rb`, `submitter_profile.rb`) use field names like `BranchOfService` for mapping form data to CRM payloads. These are completely independent of the endpoint serving that data.

### Post-removal cleanup
- Remove the resource's glob from this instruction file's `applyTo` pattern
- Verify: `bundle exec rspec modules/ask_va_api/spec/` passes

---

## Test Patterns

### Request specs (`static_data_spec.rb`)

Use the shared example for error handling:
```ruby
context 'when an error occurs' do
  before do
    allow_any_instance_of(Crm::CacheData)
      .to receive(:call)
      .and_raise(StandardError)
    get endpoint_path
  end

  it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                  'StandardError: StandardError'
end
```

Success case pattern:
```ruby
context 'when successful' do
  before { get endpoint_path, params: { user_mock_data: true } }

  it 'returns data' do
    expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
    expect(response).to have_http_status(:ok)
  end
end
```

### Unit specs (retriever, entity, serializer)

Each class in the triad should have its own spec file under `spec/app/lib/ask_va_api/{resource}/`. Follow the existing `contents/` or `categories/` specs as templates.

---

## Deprecation Context

`/contents` is a multiplexed endpoint that serves categories, topics, and subtopics via a `type` query parameter. It is being replaced by dedicated endpoints (`/categories`, `/topics/:id/subtopics`, etc.) per issues #2170, #2414, #2415, #2428, #2429. Each new endpoint gets its own class triad so `/contents` and `Contents::*` can be fully removed later.

---

## Authentication: Static Data Endpoints Are Public

`StaticDataController` declares `skip_before_action :authenticate`, so **all** static data endpoints (`/categories`, `/topics`, `/subtopics`, `/contents`, `/branch_of_service`) are served in **unauthenticated** request flows. The frontend hits these to populate the category/topic/subtopic pickers early in the Ask VA form, before sign-in.

### Implication for feature flags gating these endpoints

When registering a Flipper flag in `config/features.yml` that gates frontend use of these endpoints, use **`actor_type: cookie_id`**, not `user`. A `user` actor has no value for logged-out visitors, so a percentage rollout would not apply to them — only a blanket "enable for everyone" would. `cookie_id` keys off the Google Analytics cookie and supports consistent percentage rollouts to anonymous visitors. This matches the convention of most frontend `ask_va_*` flags (e.g. `ask_va_announcement_banner`, `ask_va_enhanced_inbox`), which use `cookie_id`. (See #2428.)

---

## Maintenance: Updating This File

When adding a new resource directory (e.g., `app/lib/ask_va_api/new_resource/`), update the `applyTo` frontmatter at the top of this file to include the new paths. Without this, Copilot won't apply these instructions when working on files in the new directory.

Add both the source and spec paths:
- `modules/ask_va_api/app/lib/ask_va_api/new_resource/**/*`
- `modules/ask_va_api/spec/app/lib/ask_va_api/new_resource/**/*`
