## Common model classes

This directory provides base classes and mixins under the `Common` namespace for building serializable, sortable, filterable, and Redis-backed data models across vets-api.

## Purpose

To establish consistent conventions for non-ActiveRecord models: how they declare attributes, how collections of them are paginated and filtered, and how short-lived objects are stored and retrieved from Redis.

## Classes

### `Common::Base`

The foundation for non-ActiveRecord model objects. Includes `ActiveModel::Serialization`, `Virtus.model`, and `Comparable`. Subclasses declare typed attributes via Virtus and can mark them as `sortable` or `filterable` for use with `Common::Collection`.

```ruby
class Prescription < Common::Base
  attribute :prescription_id, Integer, sortable: { order: 'ASC', default: true }
  attribute :status, String, filterable: %w[eq not_eq]
  attribute :dispensed_date, Common::UTCTime, sortable: { order: 'DESC' }
end
```

Tracks attribute changes (`changed?`, `changed`, `changes`) relative to the values at initialization.

### `Common::Collection`

A wrapper around an array of model objects that adds filtering, sorting, and pagination. Accepts a `cache_key` to transparently back the collection with Redis (1-hour TTL by default).

```ruby
collection = Common::Collection.fetch(Prescription, cache_key: cache_key, ttl: 3600) do
  { data: prescriptions, metadata: {}, errors: {} }
end

collection.find_by(status: { eq: 'active' })
          .sort('-dispensed_date')
          .paginate(page: 1, per_page: 10)
```

Filtering operators: `eq`, `not_eq`, `lteq`, `gteq`, `match`. Only attributes declared as `filterable` on the model class can be used. Sort fields must be declared as `sortable`.

### `Common::RedisStore`

An ActiveModel-compatible base class for objects that are persisted to Redis rather than a relational database. Subclasses configure their namespace, TTL, and key attribute using class-level declarations.

```ruby
class MySession < Common::RedisStore
  redis_store 'my_session'
  redis_ttl 3600
  redis_key :token

  attribute :token, String
  attribute :user_id, Integer
end

session = MySession.find(token)
session = MySession.find_or_build(token)
session.save
session.destroy
```

Requires `redis_store` and `redis_key` to be set. Objects are serialized to JSON via Oj. Invalid objects are automatically removed from Redis on retrieval.

### `Common::Resource`

A thin subclass of `Dry::Struct` for immutable, typed value objects. Prefer this over `Common::Base` when the object should be strictly typed and immutable by design.

```ruby
class AddressInfo < Common::Resource
  attribute :street, Types::Strict::String
  attribute :city, Types::Strict::String
end
```

## Supporting Classes

**`Common::CacheAside`** — a concern for `Common::RedisStore` subclasses that implements the cache-aside pattern. Wraps a block, checks the cache first, and stores the result if the response reports itself as cacheable (`response.cache?`).

**`Common::UTCTime`** — a Virtus attribute type that coerces all time values to UTC. Use it in `Common::Base` subclasses to ensure consistent time handling.

**`Common::Ascending` / `Common::Descending`** — internal wrappers used by `Common::Collection#sort` to support multi-field sorting with mixed directions.
