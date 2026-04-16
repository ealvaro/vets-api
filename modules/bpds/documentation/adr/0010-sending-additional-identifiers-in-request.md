# 10. sending additional identifiers in request

Date: 2026-04-15

## Status

Accepted

## Context

We want to reduce the number of skipped BPDS jobs due to a lack of identifiers

## Decision

Include additional unique user identifiers in the BPDS request - ssn, inc, edipi - and allow for future expansion.

## Consequences

There is no longer a standard check of missing PID or fileNumber. Consumers of the BPDS data will need to check for identifier presence.
