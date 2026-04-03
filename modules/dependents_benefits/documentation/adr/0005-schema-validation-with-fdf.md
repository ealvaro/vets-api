# 5. schema validation with fdf

Date: 2026-04-03

## Status

Accepted

## Context

With Fully Digital Forms (FDF), aka FormsAPI, the form schemas are shared from vets-json-schema, which is incorporated as a submodule curing build.

## Decision

To reduce duplication of effort in maintaining the schema, we will revert to storing the schemas in vets-json-schema.
This is a reversal of the earlier ADR `modules/dependents_benefits/documentation/adr/0004-move-schemas-into-module.md`

## Consequences

This will make maintenance of the schema and integration with FDF simpler and more auditable.
