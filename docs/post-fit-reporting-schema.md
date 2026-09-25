# Post-fit reporting schema

This document freezes the reporting-layer interfaces. The schemas are
independent of the reference run ID and are intended to be reused for a
future accepted production fit by changing only the explicit input paths,
run ID, and output root.

## Stable logical products

The canonical logical product names are:

```text
fixed_effects_tier1
fixed_effects_tier2
species_composition
cattle_effect
temporal_effects
selected_week_maps
model_summary
potential_abundance
rpi_readiness
```

The run ID belongs in the output path, metadata, and manifest. It is not part
of an analytical object or table name. Supporting audit products may retain
their descriptive names, including `host_lookup`, `host_assignments`,
`host_unmatched_audit`, `species_composition_first_host_sensitivity`,
`selected_map_values`, `cell_area_audit`, and `reporting_qa_audit`.

## Canonical objects and tables

### Fixed effects

`fixed_effects_tier1` and `fixed_effects_tier2` are data frames with the
following stable columns:

```text
tier
term
label
posterior_mean
posterior_sd
q025
median
q975
effect_scale
source_model_variable
units_transformation_note
```

`posterior_mean` and `posterior_sd` are the repository's stable names for the
mean and standard deviation requested in the reporting contract. Tier 2
cattle RW2 support is not duplicated in the fixed-effect table.

### Cattle effect

`cattle_effect` retains the actual weighted partial contribution used by the
model. It must not be replaced by raw RW2 latent means or rescaled for
presentation. The stable columns are:

```text
model_index
cattle_q
cattle_mid
cattle_mid_log1p
active_count
full_count
observed_positive_count
fitted_level
active_bin
support_status
rw2_latent_mean
rw2_latent_sd
rw2_latent_q025
rw2_latent_median
rw2_latent_q975
posterior_mean
posterior_sd
q025
median
q975
units
contribution_definition
```

The contribution is `RW2 posterior summary × cattle_mid_log1p`, matching
`f(cattle_q, cattle_mid_log1p, model = "rw2", ...)`. The current supported
units are `individuals/km²`, sourced from the configured
`cattle_density.tif` / `GLW4-2020.D-DA.CTL` cattle-density layer. Stage 2
defines `cattle_mid` as the midpoint of the Tier 2-fitted type-7 quantile
breaks on raw cattle density and defines `cattle_mid_log1p` as
`log1p(cattle_mid)`. No density rescaling is applied by reporting.

### Temporal effects

`temporal_effects` contains one row for each `week_steps` and `tier2_week`
component:

```text
timestep
epiyear
epiweek
calendar_date
posterior_mean
posterior_sd
q025
median
q975
component
tier
scale_semantics
```

Calendar dates come only from the supplied Stage 2 temporal mapping.

### Species composition and host audit

`species_composition` contains:

```text
common_name
broad_group
count
prop
pct
tier
denominator
denominator_type
source_file
mapping_version
```

The primary denominator is always `expanded_host_assignments`; compound
records may contribute more than one assignment. The primary figure label is
`Percentage of expanded host assignments (%)`. The first-host calculation is
retained only in `species_composition_first_host` and
`species_composition_first_host_sensitivity`.

`host_unmatched_audit` records every row that was unmatched before the
conservative lookup extension:

```text
source_row_id
host_raw
host_normalized
match_status
proposed_mapping
proposed_common_name
proposed_broad_group
classification
mapping_evidence
action
source_file
mapping_version
```

Ambiguous or unknown labels remain `Unreported` and are not guessed.

### Map selection

The selected-week metadata and the `selected_map_values` object include:

```text
run_id
time_index
epiyear
epiweek
selection_rule
selection_position
tier1_probability_path
tier2_intensity_path
tier1_raster
tier2_raster
```

The deterministic rule is first week, approximately one-third through,
approximately two-thirds through, and final week. The reference selections
are `2024-W01`, `2024-W36`, `2025-W18`, and `2026-W01`; these dates are not
hard-coded into the selection function.

### Model summary

`model_summary` is a factual list with stable fields:

```text
likelihood_families
tier_rows
holdout_counts
mesh_vertices
temporal_weeks
spatial_groups
fitted_fixed_effect_count
fitted_hyperparameter_count
DIC
WAIC
log_marginal_likelihood
```

It is not a diagnostics verdict or a biological interpretation.

### Potential abundance and RPI readiness

`potential_abundance` is explicitly:

```text
source_quantity = tier2_intensity_plugin
conversion_type = nominal_average_cell_area
cell_area_km2 = 623.4671529
direct_model_output = FALSE
```

Its human-readable label is `standardized potential abundance`; it is not
called `expected_count`.

`rpi_readiness` is always defined as a readiness object, even when blocked.
The blocked reference run has no authoritative RPI raster or figure. The
historical `nws_obs` calibration provenance must be recovered before any RPI
product is generated.

## Figure interfaces

Plotting functions consume canonical objects rather than run-specific
filenames:

| Product | Input | Outputs |
| --- | --- | --- |
| `species_composition` | `species_composition` | `species_composition.pdf`, `species_composition.png` |
| `cattle_effect` | `cattle_effect` plus supported units metadata | `cattle_effect.pdf`, `cattle_effect.png` |
| `temporal_effects` | `temporal_effects` | `temporal_effects.pdf`, `temporal_effects.png` |
| `selected_week_maps` | selected-week metadata plus validated Phase 3 rasters | `selected_week_maps.pdf`, `selected_week_maps.png` |

Map scaling remains functional and deterministic. The compressed Tier 1
reference appearance is not retuned for this reference fit; aesthetics may
be revisited after production-fit acceptance.

## Manifest interface

The manifest is run-isolated and records one row per artifact. Current stable
columns are:

```text
artifact_type
logical_product_name
path
file_format
source_object
source_run
checksum_sha256
generated_at_utc
bytes
```

`source_run` is the run ID, `logical_product_name` is the stable product name,
`file_format` is the format, and `checksum_sha256` is the artifact checksum.
The object plot prefix (`plot_`) is removed from logical product names, so
plot artifacts remain associated with `selected_week_maps`,
`cattle_effect`, or another stable product rather than a reference-specific
filename.

## Portability and provenance

The runner requires explicit fit, Stage 2, Stage 3A, Phase 2, Phase 3,
observation-source, output-root, and run-ID inputs. A future run such as
`arbitrary_new_run` is accepted without treating `20725437` as special.
Reference mode may continue to use `20725437` in examples and regression
fixtures only.

The reference RPI status remains `BLOCKED` pending historical calibration
observation provenance. No fitting, validation, projection, or rasterization
semantics are part of this reporting schema.
