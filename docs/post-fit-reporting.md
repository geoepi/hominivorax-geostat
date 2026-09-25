# Post-fit reporting architecture

This branch adds a results pipeline after the validated fit/acceptance workflow:

```text
MODEL PIPELINE       Stage 1 -> Stage 2 -> Stage 3A -> Stage 3B
ACCEPTANCE PIPELINE  fit health -> extraction -> Phase 1 -> Phase 2 -> Phase 3
RESULTS PIPELINE     extract -> canonical objects -> tables/figures -> later report
```

The reporting module is [R/postfit_reporting.R](/D:/Github/hominivorax-geostat/R/postfit_reporting.R). It consumes explicit artifact paths and run IDs. It does not alter model specification, preprocessing, likelihoods, priors, SPDE/copy-field structure, holdouts, validation, projection, or rasterization.

## Canonical objects

The runner writes a run-isolated hierarchy:

```text
postfit_reporting/<run_id>/
  objects/
  tables/
  figures/
  spatial/
  metadata/
  qa/
```

Every table and figure is derived from a canonical object. The initial object schemas are:

- `fixed_effects_tier1`: one row per fitted Tier 1 fixed term; model term, label, posterior summary, scale, source variable, and transformation note.
- `fixed_effects_tier2`: the equivalent Tier 2 object. Tier 2 nonlinear cattle support is not mixed into this table.
- `cattle_effect`: one row per `cattle_q` support bin, including active/full/positive support, `cattle_mid`, `cattle_mid_log1p`, raw RW2 summaries, and the weighted model contribution.
- `temporal_effects`: one row per fitted `week_steps` or `tier2_week` timestep, joined to the Stage 2 temporal mapping.
- `species_composition`: one row per host label with an explicit cohort definition and denominator.
- `selected_map_values`: direct values read from selected Phase 3 rasters, with the selection rule and source paths.
- `model_summary`: factual fit context, not a diagnostics verdict.
- `rpi_readiness_audit`: the semantic gate and parameters; a final RPI product is written only when the gate passes.

Canonical tables are saved as both RDS and CSV. Plots are saved as RDS plus PDF/PNG where generated.

## Extraction authority

Fixed effects, temporal effects, and cattle effects call the validated helpers in [R/joint_inla_extract.R](/D:/Github/hominivorax-geostat/R/joint_inla_extract.R). The cattle contribution is explicitly:

```text
posterior cattle_q RW2 summary × cattle_mid_log1p
```

This matches the fitted term `f(cattle_q, cattle_mid_log1p, model = "rw2", ...)`; the raw RW2 latent value is retained separately and is not plotted as the model contribution.

Temporal calendar dates are copied only from `stage2$temporal_mapping`. If no date field is present, the object retains timestep/year/week and does not invent dates.

## Species-cohort audit

The old repository material contains host standardization and broad host groups in `config/host_lookup.csv`, but it does not establish whether the historical composition figure used raw submissions, cleaned submissions, analysis-eligible records, positive records, or another denominator. The runner therefore requires `--species-cohort` whenever `--species-data` is supplied and otherwise records an unresolved audit. It does not guess a denominator.

The old result material inventoried for manuscript compatibility includes:

- `local/linear_predict.R`;
- `local/results_summary.qmdx`;
- legacy `local/Results_2026-02-23/*/fixed_eff.rds` and host-effect RDS files.

Those scripts use legacy positional/model-specific objects and do not define a stable manuscript table schema. The new canonical coefficient tables are therefore the compatibility layer; exact manuscript-specific formatting remains unavailable until the draft table definition is supplied from the manuscript workflow.

## Phase 3 maps

The map reader consumes validated Phase 3 Tier 1 probability and Tier 2 intensity rasters. It selects deterministic positions 1, approximately one-third, approximately two-thirds, and the final modeled week. Raster values are read directly by cell; no resampling, interpolation, clipping, or display rescaling is applied. Tier 1 and Tier 2 limits are held constant across their selected panels. An explicit current administrative/coastline layer can be supplied with `--boundary`; when supplied it is transformed to the raster CRS for a consistent context overlay.

## Potential abundance and RPI gate

The legacy conversion is traceable in `local/results_summary.qmdx`:

```r
cell_area <- prod(res(r_template))
```

The legacy template `local/spatial_templates/study_area_raster.tif` has resolution approximately `24.99502 × 24.94366` in the historical projected-kilometre workflow, giving an exact product of approximately `623.4672 km^2`; the old documentation rounds this to 625 km². The runner does not apply this legacy constant to the reference fit unless that template or an explicitly audited constant is supplied. The derived quantity is named `potential_abundance` and is documented as:

```text
tier2_intensity_plugin × nominal_average_raster_cell_area
```

It is not a direct model output and is not called `expected_count`.

[R/calc_RPI.R](/D:/Github/hominivorax-geostat/R/calc_RPI.R) was audited without changing it. It extracts values at supplied observation locations, calibrates the lower `cut_quant` threshold, uses the longest consecutive run above threshold, converts weeks to generations, and classifies using the existing four classes. The new namespaced implementation is enabled only when the supplied stack is explicitly standardized potential abundance, an observation source is available, the time span is known, and the default threshold/class definitions remain compatible. Otherwise `metadata/rpi_readiness_audit.*` is written and no final RPI map is produced.

## Provenance

The runner records input checksums, git commit, R/package versions, output object/table/figure lists, map selection, species audit, cattle/temporal semantics, cell-area provenance, RPI status, and a manifest containing artifact paths, formats, checksums, source objects, source run, timestamp, and file sizes.

Use [scripts/run_postfit_reporting.R](/D:/Github/hominivorax-geostat/scripts/run_postfit_reporting.R) with explicit `--fit`, `--build`, `--stage2`, `--phase3-root`, and output arguments. The example configuration is [config/postfit_reporting.example.yml](/D:/Github/hominivorax-geostat/config/postfit_reporting.example.yml). No final Quarto/HTML/PDF summary report is part of this milestone.
