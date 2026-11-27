# W44 production promotion review

**Decision: `W44_PRODUCTION_PROMOTION_BLOCKED`**

Review snapshot: 2026-11-27. The refreshed original model is scientifically
qualified with the documented limitations below, but the current production
contract cannot activate an existing fit artifact. No production configuration
or artifact was changed, and no fit, posterior sampling, or raster job was
submitted.

## Candidate and scientific qualification

- Candidate model: `ORIGINAL_REFRESH_W44_2026`;
  qualification: `ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS`.
- Candidate code and complete-suite commit: `caa682268b8e41de8d56aaedd8a44df099377dd7`;
  branch `feature/original-refresh-w44-2026` was clean and synchronized with
  `origin` at review start.
- Approved observations: `combined_clean_obs_2026-11-13.csv`, SHA-256
  `784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac`;
  164,767 source rows, analysis 2022-W01 through 2026-W44, ending
  2026-11-01. The existing Stage 1 audit records matching before-read and
  after-read checksums and retains later source rows outside the analysis
  window.
- Formula identity: `original_joint_inla_v1`, regenerated from the frozen
  manifest-free `make_joint_formula` reference at
  `4a463bd62727cf33f783a31d9627afdb576a077f`. The exact fixed-effect order is
  `intercept1, intercept2, north, road_dens, night_illum, mintemp, soilmoist,
  leafarea, rhum, mintemp:soilmoist, mintemp:leafarea, cattle, horses, pigs,
  goats, sheep` (16 coefficients). `clay`, `wv0010`, and `spressure` are
  absent. The formula audit also passes the binomial and negative-binomial
  likelihoods, deterministic fit-free Stage 3A assembly, stack mapping, and
  projection compatibility. The qualification report records the preserved
  row-specific links, SPDE fields, quarter grouping, RW1 temporal effects,
  Tier 1 administrative IID effect, shared/copy field, cattle RW2, priors,
  censoring, zero/background policy, holdout selectors, and prediction-grid
  contract.

## Canonical test suite

The repository command `Rscript tests/run_tests.R --log-dir
/project/disease_ecology/hominivorax-geostat-original-refresh-w44-2026/outputs/original_refresh_w44_2026/validation/canonical_test_logs_caa6822`
completed on the exact candidate code commit above, on Atlas login node
`atlas-login-2`, through the `atlas-r44-spatial-v1` runtime profile. R was
4.4.3 and INLA was 25.9.19. This was a direct login-node run, so it had no
Slurm job ID. Exit code was 0:

| Executed | PASS | WARN | FAIL | SKIP | Warning lines |
|---:|---:|---:|---:|---:|---:|
| 36 | 21 | 15 | 0 | 0 | 23 |

The per-test summary is archived in
[`canonical_test_summary_caa6822.tsv`](canonical_test_summary_caa6822.tsv)
(SHA-256 `063bd12101f028bcdf57140094780219d3999212ca760fa881213f9ef42e11c8`).
The full stdout and stderr logs remain in the Atlas validation output tree at
`/project/disease_ecology/hominivorax-geostat-original-refresh-w44-2026/outputs/original_refresh_w44_2026/validation/canonical_test_logs_caa6822/run-222ff255d14b86/`.
The separate runner self-test passed, confirming failure propagation and
repository-root context.

Warning classes retained from the logs:

- Atlas RTC/local-time-zone configuration warning.
- INLA deprecation warnings for `inla.mesh.2d()` and `inla.sp2segment()`.
- `sf` warning that `st_point_on_surface` assumes constant geometry
  attributes.
- Expected negative-path fixture output for malformed provenance inputs,
  disabled or failing preflight cases, and production-submission refusal when
  preflight is unavailable. These fixtures exited successfully and exercised
  the intended refusal behavior.

All warning-bearing test scripts and their warning-line counts are in the TSV.
Warnings were not suppressed. No test process failed.

## Artifact inventory and checksum verification

The authoritative inventory is
[`original_refresh_artifact_manifest.csv`](original_refresh_artifact_manifest.csv).
Its SHA-256 is
`8927eccc2140d7fcac54a9a8aeb2f71b8f66921487a8ac31208534c2ea0067aa`; the
main qualification report SHA-256 is
`62aa07157d1442d9c4bd0b42ec76a26b1680f92c8aa4cedd6401d1c75273ca86`.
The Stage 1, Stage 2, Stage 3A, and Stage 3B files were independently hashed on
Atlas during this review; each actual digest matched the inventory:

| Stage | Artifact | SHA-256 | Bytes |
|---|---|---|---:|
| 1 | `outputs/original_refresh_w44_2026/stage1/model_inputs.rds` | `64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af` | 697,619,900 |
| 2 | `outputs/original_refresh_w44_2026/stage2/joint_model_inputs.rds` | `1a09657781f6989154d331a7467c6dbc28d7be8011991709d3259e94eac95fe0` | 697,271,352 |
| 3A | `outputs/original_refresh_w44_2026/stage3a/joint_inla_build.rds` | `74dc75e578474712cc06c62634b50c26631779003c8e804bbd2f7ff62bbb74a5` | 2,634,681,832 |
| 3B | `outputs/original_refresh_w44_2026/stage3b/joint_model_fit.rds` | `e9409c37ca88dedb0441d65c184c2c5cae9ca1dcf923aeb52db03bf8e451605c` | 6,634,772,026 |

All paths above are under the existing Atlas development output tree
`/project/disease_ecology/hominivorax-geostat-original-refresh-w44-2026/`.
The extraction audit (23 PASS, 0 FAIL), fit-health audit (21 PASS, 0 WARN or
FAIL), predictive metrics, validation audit, subgroup reports, fixed-effect
and hyperparameter summaries, warning provenance, and matched C-1 comparison
are preserved in the archive and inventoried by role and digest. No large
artifact was copied.

Fit job `21355414` completed with exit `0:0` after 10:40:50, using 12 CPUs and
280G requested memory; peak RSS was 169361860K. The fit source commit was
`42f27497b251cdcd84d2b44b1844cd18292610a8`; the archived report-generation
commit was `1f9924e7c1a3b459b9302e298b08c1d6d8cac999`. The report generator
script blob at that report commit matches the candidate branch blob
`48f7391e7bde39c139f24bde6c1a0a252825f41f`.
The single `squeue` snapshot during this review showed no active job for the
user; W44 and historical fit jobs were complete.

The preserved historical frozen fit at
`/project/disease_ecology/nws-geostat-output/joint_inla_fit/production_stage3b_20260924/joint_model_fit.rds`
was also independently hashed: `d67c4ac2f570dd609bc484e858bdbe5b25cbc77c5db6eb26ee93ab7bf8e62340`.
Its job `20742007` remains `COMPLETED` with exit `0:0`; it was not modified.
The archived C-1 fit remains identified by its original manifest and digest
`c1662497af6e26313ead3055686195880673ad21efeb6c05f51bfe878080b28d`.

## Qualification results and limitations

- Fit health: 21 PASS and no failures. Fit stderr retains two
  `INLA_EXPERIMENTAL_VB_WARNING` occurrences and zero unclassified warning
  lines; the warnings are preserved as provenance and were not treated as a
  fit failure.
- Extraction: 23 PASS and 0 FAIL. The extracted fit has 16 fixed effects, 10
  hyperparameters, and 7 random-effect components. Administrative mapping
  retains 342 levels, with 324 fitted/direct Tier 1 levels; unused levels are
  explicitly represented.
- Validation: 29 PASS and 1 WARN. The warning is that observation-level
  negative-binomial predictive intervals cannot be reconstructed from the
  saved fit. Tier 1 has positive-only holdouts and availability background,
  not confirmed absences.
- C-1 holdouts matched exactly: Tier 1 4,768/4,768 and Tier 2 7,471/7,471;
  no unmatched records. W44 Tier 1 area-weighted PB-AUC was 0.990703 and CBI
  0.999734. Tier 2 point-prediction MAE was 2.07097, RMSE 3.15264, Pearson
  0.781745, Spearman 0.648070, and calibration mean ratio 0.982682.
- Paired Tier 2 MAE difference (refreshed original minus C-1) was +0.000732.
  It is descriptive and practically small under the evaluated holdout design;
  it does not establish superiority.
- No geographic prediction rasters or new posterior samples were generated.

## Three-way production configuration comparison

| Configuration | Model and formula | Data/window | Output and current status |
|---|---|---|---|
| Historical frozen production | Original 16-coefficient formula; historical fit job `20742007` | The private active production file currently points to the 2026-W39 observation release; `2024-W01` start and `last_complete_epiweek` end rule | Historical fit remains at its original immutable output path. Current canonical checkout is `main` at `cf21c04ef53158b9bcca38dad75e7f75ee9e984a`. |
| Archived Configuration C-1 | 19 coefficients including `clay`, `wv0010`, and `spressure`; archived, not selected for production | Approved 2026-11-13 release through 2026-W44 | C-1 fit and reports remain in their original archive paths; no promotion reference is present in the active private configuration. |
| Refreshed original W44 | Restored original 16-coefficient formula; excludes all three C-1-only terms | Approved 2026-11-13 release through 2026-W44, ending 2026-11-01 | Candidate artifacts remain in the named development output tree. Proposed production identifier `ORIGINAL_W44_2026_PRODUCTION` is not active and has no production artifact path. |

The tracked `config/production.example.yml` is stale for this candidate: its
observation template resolves to a 2027-07-31 file and its no-submit dry-run
resolved only through 2026-W30. The actual private production config dry-run
resolved through W39. Both dry-runs submitted no jobs. The active private
config SHA-256 is `0667d4ab1c6780da0ce435bd3a7e67fa83a2b90d0c8cc8b4658909d3d4f6ea49`.
The private deployment manifest still records a different production-config
digest (`45022942bca0fd9dd49fe50a7b19c0049badadf8d38f7071e0826e692b90b966`)
and a different canonical commit (`d2a2ff96766971416b41e00123b46ddbf1906322`)
than the observed active checkout/config. The actual manifest file digest is
`7d1eae69290f63e7432d2a7c9fc9796a637981ffd96718808d187ad079e9fc16`.

## Promotion blockers

The private production configuration has no model-version or existing-fit
artifact reference. The production orchestration path is hard-wired to submit
Prepare, Fit, and Post-fit stages. A normal submission would fit again and
run the post-fit raster path, which is outside this authorization. The current
code therefore has no supported way to activate the already fitted W44 model
while obeying the no-refit/no-raster requirements.

The W44 fit also has no confirmed stable, versioned production storage
location: its present path is under the development checkout, and the storage
policy for a manifest pointer to that path has not been confirmed. The private
deployment manifest/config mismatch must also be reconciled before activation.

Consequently, the production ID remains proposed only; the private config and
deployment manifest were not changed. The W44 model remains a qualified
candidate, not the active production model. Clearing this decision requires an
approved activation contract and stable artifact-reference location, plus
reconciliation of the private deployment manifest. Any new activation
mechanism is an operational contract decision and must be reviewed under SAE
governance.

## Git and deployment state

The tested code revision `caa682268b8e41de8d56aaedd8a44df099377dd7` was
synchronized with `origin` when the suite ran. The review evidence was then
added as documentation-only commits; PR #15 was opened at head
`1641b5022363ea1a934f94a09c350b01ab118011`.
The repository has no `.github/workflows` directory. GitHub exposed no candidate
statuses/check-runs in the prior audit; the branch-protection endpoint was
inaccessible to the connected account. No merge, tag, Atlas production sync,
or production configuration write was performed. The active configuration
remains on W39, and the two no-submit dry-runs created no jobs.

Draft PR [#15](https://github.com/geoepi/hominivorax-geostat/pull/15) targets
`main`. It is open and unmerged for code review; no status checks were
reported. No reviewer approval, merge, release tag, or Atlas synchronization
has occurred.

The follow-on promotion record, JSON manifest, and copied test summary are
documentation/evidence changes (Category A). The JSON parsed successfully,
and a local whitespace scan found no trailing whitespace in these three
files. No second test-suite run was needed because these additions do not
change executable behavior.
