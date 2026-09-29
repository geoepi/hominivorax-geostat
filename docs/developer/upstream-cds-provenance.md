# CDS upstream provenance

Production orchestration records the CDS inputs consumed by geostatistical
preprocessing. The four model covariates are mapped to the CDS products as
follows:

| Model covariate | Preprocessing name | CDS product |
| --- | --- | --- |
| `mintemp` | `minimum_temperature` | `era5_mintemp` |
| `soilmoist` | `soil_moisture` | `era5_soilmoist` |
| `leafarea` | `leaf_area_low` | `era5_lai_low` |
| `rhum` | `relative_humidity` | `agera5_relhum_min` |

Each selected weekly raster must have a parseable `<raster>.json` sidecar,
the expected product and ISO week, an `input_fingerprint`, and a valid
64-character `output_sha256`. The raster itself is not rehashed by the
orchestrator; the CDS sidecar is hashed and retained as the authoritative
output record. Optional source-family and request-hash fields are retained
when supplied by CDS.

The source chain is:

```text
CDS weekly raster + JSON sidecar
  -> scripts/run_preprocessing.R raster extraction
  -> stage1/model_inputs.rds
  -> Stage 2 and downstream geostatistical stages
```

Before a production submission, the orchestrator selects the latest successful
CDS portfolio manifest whose validated endpoint covers the resolved geostat
horizon and all four required products. It writes:

* `metadata/upstream_cds_provenance.csv`: one deterministic record per product
  and modeled week;
* `metadata/cds_coverage_certificate.yml`: a compact successful-coverage
  certificate independent of file-level lineage;
* `upstream_provenance.cds_datagrab` content in `run_manifest.yml` and
  `production_summary.yml`, including artifact and certificate hashes.

Per-product and overall SHA-256 fingerprints canonicalize the selected records
in product/model/week order. Run-specific destination paths are retained for
traceability but excluded from fingerprints.

Resume rehydration requires the recorded repository commit to equal the
current checkout commit. A missing or different commit stops resume before
stage or scheduler execution; historical manifests remain readable through the
manifest reader.

The provenance layer is metadata-only. It does not modify observations,
covariate values, transformations, formulas, mesh/SPDE construction, INLA
settings, fitted values, diagnostics, predictions, masking, RPI calculations,
or scheduler resources.
