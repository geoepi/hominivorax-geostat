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
random_effect_summaries
rpi
rpi_class_summary
rpi_class_map
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

### Random-effect summaries and comparison

`random_effect_summaries` is the canonical fitted-hyperparameter table. It
contains actual INLA posterior summaries with stable columns:

```text
component, parameter, mean, sd, q025, median, q975, mode, units, scale, source
```

The accepted model exposes at least Tier 1 and Tier 2 SPDE range/stdev, Tier 1
weekly RW1 and administrative IID precision, Tier 2 weekly RW1 precision,
cattle RW2 precision, the Tier 2 copy coefficient, and the negative-binomial
size/dispersion parameter. SPDE ranges are reported in km only after checking
the Stage 3A `spde_metadata` coordinate-unit and prior-range fields. `mode` is
`NA` when INLA does not expose a posterior mode on the reported scale.

When both accepted runs are supplied, `random_effect_comparison` compares
fitted means with `reference_20725437`, `production_20742007`,
`absolute_difference`, and `ratio_or_fold_change` columns.

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

`rpi_readiness` is always defined as a readiness object. Its status is
`BLOCKED` only when the standardized potential-abundance stack, cleaned
observation representation, continuous time span, or semantic parameters are
missing. With the accepted cleaned observations and potential-abundance
stack, the status is `READY` and canonical RPI products can be completed.

RPI uses `tier2_intensity_plugin × nominal_average_raster_cell_area`, with
area derived dynamically from the supplied raster template. It calibrates the
10th percentile at cleaned observation locations, finds the longest
consecutive suitable-week run, converts weeks to generations using 21 and 7
days, and applies `<3`, `3–<8`, `8–<15`, and `>=15` generation classes.
Canonical outputs include `objects/rpi.rds`,
`tables/rpi_class_summary.csv`, `spatial/rpi_continuous.tif`,
`spatial/rpi_class.tif`, `figures/rpi_class.pdf/png`, and
`metadata/rpi_metadata.rds/csv`. `rpi_class_summary` contains
`class_id`, `class_label`, `cell_count`, `area_km2`, and
`proportion_of_supported_cells`.

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
`arbitrary_new_run` is accepted without treating the historical reference run
as special. Reference mode may continue to use the historical identifier in
examples and regression fixtures only.

Historical documentation may describe an earlier blocked run, but the current
contract recognizes the accepted private cleaned-observation source and no
longer treats RPI as globally blocked. No fitting, validation, projection, or
rasterization semantics are part of this reporting schema.
