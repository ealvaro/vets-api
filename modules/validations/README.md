# Validations

A shared Rails engine providing general-purpose validation utilities for use across vets-api modules. It was created to consolidate cross-team validation logic (e.g. zip code lookup) in a single place, rather than having teams depend on each other's namespaced routes.

See [ADR 0001](documentation/adr/0001-general-use-validations-module.md) for background and rationale.

## Endpoints

All endpoints are mounted at `/validations`.

### Zip Code Validation

```shell
GET /validations/v0/zipcode/:zipcode
```

Validates a US zip code by:

1. Normalizing input (trims leading/trailing whitespace)
2. Checking format (`12345` or `12345-6789`)
3. Looking up the 5-digit zip in `std_zipcodes` (~42k rows)

For ZIP+4 input, only the first 5 digits are used for database lookup.

To reduce DB load, the `std_zipcodes` zip list is cached in `Rails.cache`.
The cache expires daily, currently.  The StdZipcodeImport job runs monthly.

**Response:**

```json
{ "zip_is_valid": true, "zipcode": "12345", "message": "Valid zipcode" }
```

or

```json
{ "zip_is_valid": false, "zipcode": "55555", "message": "Zipcode does not exist" }
```

## Models

The following shared models are used:

- `StdZipcode` — zip code lookup table
- `StdState` — state reference data
- `StdCounty` — county reference data

## Installation

Ensure the following line is in the root project's Gemfile:

  gem 'validations', path: 'modules/validations'

## License

This module is open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
