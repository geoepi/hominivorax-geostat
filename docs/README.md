# Documentation index

This directory separates operator guidance from technical contracts.

## For scientists and operators

- [User workflow](user-workflow.md) — one-page preparation, submission,
  monitoring, results, and resume guide.
- [Atlas deployment](developer/atlas-deployment.md) — canonical production
  checkout, secure configuration, output location, and operator commands.
- [Model workflow overview](model-workflow-overview.md) — ecological purpose,
  observations, Tier 1/Tier 2 logic, and derived products.
- [Interpretation guide](interpretation-guide.md) — how to read modeled
  detection, intensity, potential abundance, and RPI outputs.
- [Data and preprocessing](data-and-preprocessing.md) — input coverage,
  cleaning, temporal resolution, and preprocessing behavior.

## Technical workflow and products

- [Model architecture](developer/model-architecture.md) — stages, scheduler
  jobs, fitted versus structural products, temperature masking, and RPI.
- [Production orchestration](developer/production-orchestration.md) — command
  options, dynamic runtime contracts, resources, and resumption.
- [Production validation](developer/production-validation.md) — Prepare, Fit,
  and Post-fit gates and their failure semantics.
- [Post-fit acceptance](post-fit-acceptance.md) — extraction, validation,
  projection, raster, and acceptance interfaces.
- [Post-fit reporting](post-fit-reporting.md) and [reporting schema](post-fit-reporting-schema.md)
  — reporting products, metadata, and RPI outputs.
- [Model specification](model-specification.md) — accepted likelihoods,
  effects, exposure, and preserved model contracts.

## Provenance, maintenance, and release

- [Provenance and data residency](developer/provenance-and-data-residency.md)
  — source-by-reference policy and audit outputs.
- [Stage 1 contract](developer/stage1-contract.md), [Stage 2 contract](developer/stage2-contract.md),
  [Stage 3A contract](developer/stage3a-contract.md), and [Stage 3B contract](developer/stage3b-contract.md).
- [Extraction contract](developer/extraction-contract.md) — post-fit row and
  index reconciliation.
- [Release procedures](developer/release-procedures.md) — final checks for
  documentation, validation, synchronization, and tagging.
- [Repository cleanup audit](developer/repository-cleanup-audit.md) — retained,
  diagnostic, and intentionally ignored material.
- [Deferred development](deferred-development.md) — future scientific and
  engineering work intentionally outside the release baseline.
- [Atlas environment](atlas-environment.md) and [synchronization](synchronization.md)
  — governed execution and checkout maintenance.
