# C-1 and refreshed original holdout comparison

Exact identity match across both tiers: **yes**.

## Holdout alignment

| Tier | C-1 rows | Refreshed rows | Matched | C-1 only | Refreshed only | Exact match |
|---|---:|---:|---:|---:|---:|:---:|
| tier1 | 4768 | 4768 | 4768 | 0 | 0 | yes |
| tier2 | 7471 | 7471 | 7471 | 0 | 0 | yes |

Holdout identities match exactly in both tiers. The aggregate descriptive metric tables use the same holdout identities and are compared in matched_summary_metric_comparison.csv.
Tier 1 metrics retain the established presence-background design: the common saved Stage 2 terrestrial integration rows are availability support, not confirmed absences.

## Tier 2 paired point errors

Matched rows: 7471; C-1 only: 0; refreshed only: 0.
Paired MAE differences are refreshed minus C-1; negative values favor the refreshed point prediction on the shared rows. This is descriptive and has no prespecified numeric acceptance threshold.

## Geographic and temporal error patterns

Matched Tier 2 absolute errors are summarized by administrative unit, epiweek, and their combination in matched_tier2_spatial_temporal_errors.csv. Groups with fewer than 30 rows are retained as LOW_SUPPORT.

## Files

- matched_holdout_counts.csv
- matched_tier2_paired_absolute_error.csv
- matched_tier2_spatial_temporal_errors.csv
- matched_summary_metric_comparison.csv

This is a descriptive comparison of the completed C-1 fit and one refreshed original-specification fit. It does not establish exact model equivalence, causal effects, or production superiority.
