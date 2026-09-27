# Provenance and data residency

This project treats the cleaned observation CSV as an authoritative governed
input, not as a production artifact to be copied through every stage.

## Authoritative source

The source is referenced by path and SHA-256 in provenance metadata:

`/project/disease_ecology/NWScrewworm/data/processed_data/case_detections/combined_clean_obs_2027-07-31.csv`

Downstream code may read, hash, and transform this file. Production output
directories must not contain byte-for-byte copies or bundled full copies of the
source CSV.

## Persistence policy by stage

- Stage 1 may persist derived Tier 1 rows required for response construction,
  covariates, host normalization, spatial support, and temporal indexing. The
  accepted artifact currently retains source-derived date, host, lon/lat,
  projected coordinates, source IDs, and model fields.
- Stage 2 may persist model-ready Tier 1/Tier 2 representations, response and
  holdout flags, covariates, cell/week keys, and provenance references. The
  accepted Tier 1 table inherits several Stage 1 source-derived fields for
  model reconciliation; this is a documented minimization opportunity, not a
  source-file copy.
- Stage 3A and Stage 3B persist INLA stacks, design matrices, responses,
  posterior/fit objects, formulae, priors, and provenance. They must not embed
  raw source observations or host text solely for convenience.
- Extraction and validation may persist holdout identifiers, observed
  responses, model indices, predictions, and the spatial/temporal keys needed
  to reconcile validation. Full source rows are not required.
- Projection and rasterization persist prediction-grid keys, derived values,
  raster geometry, and QA/provenance metadata.
- Structural and masked products persist derived raster values, CRS/support,
  cell/week keys, QA, and observation provenance by reference.
- Final reporting may reread the authoritative source for host summaries and
  dynamic RPI calibration. Persisted row-level calibration data must be
  minimal: observation index, week/layer matching, support flags, extracted
  value, and eligibility. Host reporting should prefer aggregate summaries;
  the current host-assignment table is retained for mapping auditability and
  is a future minimization candidate.

## Provenance by reference

Manifests and metadata should store source path, SHA-256, role, schema/version
information, and CRS/coordinate-field information where relevant. They should
not embed the source dataset. Derived artifacts may contain row-level data
when that data is necessary to reproduce model design, holdout validation, or
the dynamic same-week RPI threshold.

## Audit outputs

`scripts/run_provenance_residency_audit.R` writes an immutable audit directory
containing:

- `artifact_lineage.csv`
- `data_residency_audit.csv`
- `exact_copy_scan.csv`
- `near_copy_candidates.csv`
- `stale_assumption_audit.csv`
- `provenance_audit_summary.txt`

The audit does not rerun or rewrite accepted production artifacts and never
copies the authoritative observation CSV into its output directory.
