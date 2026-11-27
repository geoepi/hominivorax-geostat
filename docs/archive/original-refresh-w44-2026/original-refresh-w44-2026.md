# Original model refresh through 2026-W44

Model: **ORIGINAL_REFRESH_W44_2026**. Final qualification: **ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS**. C-1 disposition: **C1_ARCHIVED_NOT_SELECTED_FOR_PRODUCTION**.

## Decision summary

The frozen original fixed-effect specification was restored from the manifest-free branch of R/joint_inla_spec.R at the development base commit. It contains 14 established predictor terms plus intercept1 and intercept2 (16 fixed coefficients total), including mintemp:soilmoist and mintemp:leafarea. C-1-only clay, wv0010, and spressure are absent from the Stage 3A design.
The refreshed data revision is the approved 2026-11-13 observation release through 2026-W44 (2026-11-01). The C-1 Stage 1 artifact was reused only after its artifact hash, source checksum, manifest, explicit window, predictor schema, mesh, coordinate, and exposure contracts passed. Stage 2 and Stage 3A were rebuilt in this isolated output tree.

## Separate qualification evidence

| Gate | Result |
|---|---|
| Stage1 | PASS |
| Stage2 | PASS |
| Stage3A | PASS |
| Stage3B_dry_run | PASS |
| Stage3B_fit_health | PASS |
| predictive_validation | PASS |

The Stage 3B fit-health and production extraction gates recorded 21 and 0 checks, with 0 failures. Extraction recorded 23 PASS and 0 FAIL checks. Model/validation warnings retained: 3; Atlas runtime warning lines retained separately: 4.

### Computational qualification

Stage 1/2/3A prepared through 2026-W44. Stage 2 Tier 1/Tier 2 source rows: 3451435 / 2749320; Stage 3A mesh vertices: 13507; quarter groups: 20. The formula audit confirms 16 fixed effects, original interactions, both likelihoods, and executed_fit = FALSE.
Stage 3B job 21355414 used 12 CPUs and 280G requested memory; elapsed 10:40:50; peak RSS 169361860K. Fit artifact SHA-256: e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c.

The Slurm stderr log contained 2 occurrence(s) of INLA_EXPERIMENTAL_VB_WARNING and 0 unclassified warning line(s). Exact messages, occurrence counts, source log, and dispositions are archived in original_refresh_fit_warnings.csv. Atlas runtime warnings are retained there separately. The documented experimental VB correction warning was not treated as a fit failure, and no refit was attempted in response to it.

### Predictive performance

| Tier | Metric | Value | Status | n |
|---|---|---:|---|---:|
| tier1 | withheld_occurrences | 4768.00 | PASS | 4768 |
| tier1 | reference_background_rows | 2521533. | PASS | 2521533 |
| tier1 | reference_background_spatial_nodes | 10044.0 | PASS | 10044 |
| tier1 | reference_background_weeks | 252.000 | PASS | 252 |
| tier1 | reference_background_total_weight | 2486400996. | PASS | 2521533 |
| tier1 | PB_AUC | 0.990703 | PASS | 4768 |
| tier1 | PB_AUC | 0.990753 | PASS | 4768 |
| tier1 | continuous_boyce_index | 0.999734 | PASS | 4768 |
| tier1 | continuous_boyce_index | 0.999748 | PASS | 4768 |
| tier1 | same_week_weighted_percentile_rows | 4768.00 | PASS | 4768 |
| tier1 | same_week_unweighted_percentile_rows | 4768.00 | PASS | 4768 |
| tier1 | same_week_area_weighted_n | 4768.00 | PASS | 4768 |
| tier1 | same_week_area_weighted_mean | 0.982909 | PASS | 4768 |
| tier1 | same_week_area_weighted_sd | 0.0487476 | PASS | 4768 |
| tier1 | same_week_area_weighted_min | 0.00682132 | PASS | 4768 |
| tier1 | same_week_area_weighted_q05 | 0.936311 | PASS | 4768 |
| tier1 | same_week_area_weighted_q25 | 0.981356 | PASS | 4768 |
| tier1 | same_week_area_weighted_median | 0.995861 | PASS | 4768 |
| tier1 | same_week_area_weighted_q75 | 0.999778 | PASS | 4768 |
| tier1 | same_week_area_weighted_q95 | 1.00000 | PASS | 4768 |
| tier1 | same_week_area_weighted_max | 1.00000 | PASS | 4768 |
| tier1 | same_week_area_weighted_fraction_above_0.50 | 0.997483 | PASS | 4768 |
| tier1 | same_week_area_weighted_fraction_above_0.75 | 0.995176 | PASS | 4768 |
| tier1 | same_week_area_weighted_fraction_above_0.90 | 0.980285 | PASS | 4768 |
| tier1 | same_week_unweighted_n | 4768.00 | PASS | 4768 |
| tier1 | same_week_unweighted_mean | 0.983186 | PASS | 4768 |
| tier1 | same_week_unweighted_sd | 0.0487678 | PASS | 4768 |
| tier1 | same_week_unweighted_min | 0.00687077 | PASS | 4768 |
| tier1 | same_week_unweighted_q05 | 0.937658 | PASS | 4768 |
| tier1 | same_week_unweighted_q25 | 0.982006 | PASS | 4768 |
| tier1 | same_week_unweighted_median | 0.996217 | PASS | 4768 |
| tier1 | same_week_unweighted_q75 | 0.999801 | PASS | 4768 |
| tier1 | same_week_unweighted_q95 | 1.00000 | PASS | 4768 |
| tier1 | same_week_unweighted_max | 1.00000 | PASS | 4768 |
| tier1 | same_week_unweighted_fraction_above_0.50 | 0.997483 | PASS | 4768 |
| tier1 | same_week_unweighted_fraction_above_0.75 | 0.994966 | PASS | 4768 |
| tier1 | same_week_unweighted_fraction_above_0.90 | 0.980076 | PASS | 4768 |
| tier1 | same_week_area_weighted_week_equal_mean | 0.989744 | PASS | 223 |
| tier1 | same_week_unweighted_week_equal_mean | 0.989867 | PASS | 223 |
| tier2 | holdout_rows | 7471.00 | PASS | 7471 |
| tier2 | zero_count_rows | 0 | PASS | 7471 |
| tier2 | mae | 2.07097 | PASS | 7471 |
| tier2 | rmse | 3.15264 | PASS | 7471 |
| tier2 | pearson | 0.781745 | PASS | 7471 |
| tier2 | spearman | 0.648070 | PASS | 7471 |
| tier2 | calibration_mean_ratio | 0.982682 | PASS | 7471 |
| tier2 | calibration_intercept | -0.110021 | PASS | 7471 |
| tier2 | calibration_slope | 1.00758 | PASS | 7471 |
| tier2 | predictive_interval_coverage | not estimable | WARNING | 7471 |

Tier 1 uses held-out detections against same-week terrestrial integration/background support; these locations have unknown biological status and are not confirmed absences. Tier 2 point metrics are on expected-count scale. Observation-level negative-binomial predictive intervals were reported unavailable; conditional-mean marginals were not substituted. Geographic and temporal subgroup summaries use the established 30-row display threshold.

### Model parsimony and scientific interpretation

The refreshed candidate uses the established 16-term original formula and excludes the three C-1 additions. This restores the simpler operational specification while preserving the joint binomial/negative-binomial architecture, row-specific family links, tier-specific intercepts, SPDE fields, quarter grouping, temporal RW1 effects, Tier 1 administrative IID effect, shared/copy field, cattle RW2, original priors, reporting censoring, Tier 2 zero/background policy, exposures, holdout selectors, and prediction-grid convention.
Fixed-effect summaries are conditional on the retained spatial and random-effect structure. Random-effect and hyperparameter diagnostics are summarized separately; no individual predictor is interpreted causally. Results do not establish model superiority or exact equivalence to C-1.

### Production readiness

The refreshed original specification is the next production candidate, **not yet a production replacement**. It passed the documented technical gates with limitations from positive-only Tier 1 holdouts, absent observation-level predictive intervals, and descriptive predictive metrics without numeric acceptance cutoffs. No production merge or artifact replacement was performed.

## Refreshed inputs and Stage 2 support

- Observation source SHA-256: 784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac; source rows: 164,767.
- Stage 1 Tier 1/Tier 2/prediction-grid rows: 3451435/2749320/4007808; reused artifact path: outputs/original_refresh_w44_2026/stage1/model_inputs.rds.
- Stage 2 active Tier 2 response rows: 29883; Tier 1 holdouts: 4768; Tier 2 holdouts: 7471.
- Tier 1/Tier 2 A-matrix dimensions: 3451435 x 270140 / 2749320 x 270140.

## Fixed-effect posterior summaries

| Term | Mean | SD | 95% marginal interval |
|---|---:|---:|---:|
| intercept1 | -14.50 | 0.2866 | [-15.06, -13.94] |
| intercept2 | -6.710 | 0.1294 | [-6.964, -6.457] |
| north | -2.330 | 0.3204 | [-2.958, -1.702] |
| road_dens | 0.3698 | 0.01128 | [0.3477, 0.3919] |
| night_illum | 1.068 | 0.01448 | [1.039, 1.096] |
| mintemp | 0.1519 | 0.04410 | [0.06541, 0.2383] |
| soilmoist | -0.05193 | 0.02526 | [-0.1014, -0.002422] |
| leafarea | -0.03849 | 0.02611 | [-0.08965, 0.01268] |
| rhum | 0.1414 | 0.02162 | [0.09905, 0.1838] |
| cattle | -0.1456 | 0.08963 | [-0.3213, 0.03005] |
| horses | 0.1387 | 0.01343 | [0.1124, 0.1650] |
| pigs | 0.04163 | 0.01335 | [0.01547, 0.06779] |
| goats | -0.01374 | 0.02290 | [-0.05862, 0.03113] |
| sheep | 0.008549 | 0.02364 | [-0.03778, 0.05488] |
| mintemp:soilmoist | 0.02900 | 0.02861 | [-0.02707, 0.08508] |
| mintemp:leafarea | -0.04575 | 0.03444 | [-0.1133, 0.02176] |

Full fixed-effect and hyperparameter summaries, a compact random-component summary, and validation audit tables are preserved beside this report.

## Configuration C-1 comparison

Matched holdout rows: 12239; unmatched C-1 plus refreshed rows: 0; paired Tier 2 MAE difference (refreshed minus C-1): 0.000731802439250512.
Read the matched-comparison report for Tier 1/2 identity counts, aggregate metrics when exact identity coverage permits, and geographic/temporal paired error summaries. Unmatched aggregate metrics are not presented as a controlled comparison. The refreshed-model subgroup tables separately summarize Tier 1 availability percentiles and Tier 2 errors by administrative unit, year, epiweek, and year-week.

## Slurm and software provenance

- Fit Slurm job: 21355414; allocation: 12 CPUs / 280G; elapsed: 10:40:50; peak RSS: 169361860K; exit status: 0.
- Fit-source repository commit: 42f27497b251cdcd84d2b44b1844cd18292610a8; report-generator repository commit: 1f9924e7c1a3b459b9302e298b08c1d6d8cac999.
- R: R version 4.4.3 (2025-02-28); INLA: 25.9.19.
- Fit SHA-256: e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c; Stage 3A SHA-256: 74dc75e578474712cc06c62634b50c26631779003c8e804bbd2f7ff62bbb74a5; Stage 2 SHA-256: 1a09657781f6989154d331a7467c6dbc28d7be8011991709d3259e94eac95fe0; copied Stage 1 SHA-256: 64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af.

## Archived evidence files

- original_refresh_fixed_effect_summaries.csv
- original_refresh_hyperparameter_summaries.csv
- original_refresh_random_component_summary.csv
- original_refresh_predictive_metrics.csv
- original_refresh_fit_health.csv
- original_refresh_fit_warnings.csv
- original_refresh_extraction_audit.csv
- original_refresh_validation_audit.csv
- original_refresh_stage1_reuse_audit.csv
- original_refresh_formula_audit.csv
- matched_holdout_counts.csv
- matched_tier2_paired_absolute_error.csv
- matched_c1_original_refresh_comparison.md
- tier1_same_week_percentiles_by_admin.csv
- tier2_spatial_admin_metrics.csv
- tier2_temporal_year_metrics.csv
- tier2_temporal_epiweek_metrics.csv
- tier2_temporal_yearweek_metrics.csv
- original_refresh_predictive_subgroup_summary.md
- original_refresh_artifact_manifest.csv
- slurm_execution_summary.csv

Full serialized model artifacts and row-level validation files remain in their immutable Atlas run paths recorded in original_refresh_artifact_manifest.csv. No geographic posterior surface or raster was generated.
