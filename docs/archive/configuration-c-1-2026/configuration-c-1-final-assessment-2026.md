# Configuration C-1 final fixed-effect assessment

Disposition: **C1_ARCHIVED_NOT_SELECTED_FOR_PRODUCTION**.

## Provenance

- Completed fit: Stage 3B job 21304948; SHA-256 c1662497af6e26313ead3055686195880673ad21efeb6c05f51bfe878080b28d.
- Fit repository commit: 923c1c0ad3d1c19c524b3dc981bbb8170620c6a0; C-1 configuration SHA-256 1d24b041875d9d10995240d64add12e4d8ec796cb32f85a738d38a42c9027a84.
- C-1 source manifest SHA-256: 9f1509e98906c77cfcaa57b6146212d5e60eab7a569d309788d6f6fd738dfc8d.
- Stage 2 artifact: /project/disease_ecology/hominivorax-geostat-c1-validation-20261121/outputs/configuration_c/c1-validation-20261121-stage2-index-repair/stage2/joint_model_inputs.rds; SHA-256 55f5e2854461a1f7c694745a68f33b0d441471dd0efa492f840f12d2bb3cbb04.
- Reused Stage 1 artifact: /project/disease_ecology/hominivorax-geostat-c1-validation-20261121/outputs/configuration_c/c1-validation-20261121-stage2-index-repair/stage1/model_inputs.rds; SHA-256 64571f7b3a7aa59625cbe788d10ce8f149f1b53b8015efcabceed99dcc25f9af.
- Observation release: combined_clean_obs_2026-11-13.csv; SHA-256 784168081cc1d3206f3537b8731994cbfc34be15be7c515fe06710d4ea9bdaac; 164,767 source rows; analyzed through 2026-W44 (2026-11-01).
- Runtime: R R version 4.4.3 (2025-02-28); INLA 25.9.19.

The C-1 fit was reused as completed. No C-1 refit, preprocessing rerun, Stage 3A rebuild, joint latent posterior sampling, or prediction surface was performed. All coefficient summaries below use the saved one-dimensional INLA fixed-effect marginals.

## Fixed-effect posterior summaries

| Term | Source units | Mean | Median | SD | 95% credible interval | Contains zero | P(beta > 0) |
|---|---|---:|---:|---:|---:|:---:|---:|
| clay | SoilGrids mapped g/kg; coefficient per g/kg | 0.00033666 | 0.00033625 | 0.00020093 | [-0.000057656, 0.00073015] | yes | 0.9528 |
| wv0010 | SoilGrids mapped 10^-3 cm3 cm-3; coefficient per mapped unit | 0.00070404 | 0.00070289 | 0.00055202 | [-0.00037929, 0.0017851] | yes | 0.8985 |
| spressure | ERA5-Land product Pa; C-1 fitted column kPa per manifest | 0.0024905 | 0.0024829 | 0.0036271 | [-0.0046276, 0.0095935] | yes | 0.7531 |

## Observed predictor distributions and practical effects

The primary distribution is all finite Tier 2 rows in the completed C-1 Stage 2 analytical support (including rows not active in the likelihood, such as holdout, censored, and zero-policy rows). The sensitivity distribution is the subset with nonmissing response_training. These ranges describe the stored mapped units and are not restricted to positive counts.

| Term | Stage 2 sample | IQR | Median multiplicative effect over IQR (95% marginal interval) | Median multiplicative effect over 10th–90th range (95% marginal interval) |
|---|---|---:|---:|---:|
| clay | all finite Stage 2 Tier 2 analytical-support rows | 121.66 | 1.0418 [0.99301, 1.0929] | 1.0759 [0.98753, 1.1722] |
| clay | active Tier 2 response_training rows | 86.884 | 1.0296 [0.99500, 1.0655] | 1.0607 [0.98995, 1.1364] |
| wv0010 | all finite Stage 2 Tier 2 analytical-support rows | 57.875 | 1.0415 [0.97829, 1.1088] | 1.0773 [0.96062, 1.2081] |
| wv0010 | active Tier 2 response_training rows | 31.086 | 1.0221 [0.98828, 1.0571] | 1.0465 [0.97577, 1.1224] |
| spressure | all finite Stage 2 Tier 2 analytical-support rows | 9.4874 | 1.0238 [0.95705, 1.0953] | 1.0482 [0.91604, 1.1994] |
| spressure | active Tier 2 response_training rows | 8.3173 | 1.0209 [0.96224, 1.0831] | 1.0439 [0.92311, 1.1804] |

For each linear log-link coefficient beta and predictor spread d, the multiplicative summary is exp(beta × d); the interval endpoints transform the saved marginal 2.5% and 97.5% quantiles. It is a relative conditional intensity/count-rate contrast over the stated predictor difference, not an absolute count change or a causal effect.

## Scientific interpretation

Direction and uncertainty are reported directly from the saved coefficient marginals. Practical size should be judged from the transformed effects over the observed predictor ranges rather than from raw coefficient magnitudes. Soil clay and volumetric water content may share spatial structure and can overlap with the spatial field; weekly surface pressure may overlap environmentally with humidity, temperature, and soil-moisture structure. These are plausible redundancy pathways, not demonstrated collinearity or an identified variance partition.

The existing predictive validation is descriptive and does not identify the incremental contribution of any one term. It uses positive-only Tier 1 holdouts and positive-count Tier 2 holdouts, provides no confirmed absence sample, and did not produce observation-level predictive intervals. The C-1 versus original comparison must use matched holdout records before any performance difference is interpreted; no C-1 inferiority or superiority is established here.

Existing report: /project/disease_ecology/hominivorax-geostat-c1-validation-20261121/outputs/configuration_c/c1-predictive-validation-20261123/validation_presence_background_c1-predictive-qualification-20261123-r3/c1_predictive_qualification_report_c1-predictive-qualification-20261123-r3.md (SHA-256 828d2384614cef5dc31088e862fd1b32ca397d061ad731e7d45d03937aa25f1d). Its reported decision is C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS. Tier 1 used 4,768 positive held-out detections and no confirmed negatives, so presence-background AUC, Continuous Boyce Index, and same-week availability percentiles are descriptive; binary classification metrics are not estimable. Reported area-weighted presence-background AUC was 0.9907229; area-weighted CBI was 0.9997558; mean area-weighted same-week percentile was 0.9829135. Tier 2 used 7,471 positive-count holdouts: mean observed 4.3432, mean expected 4.4197, MAE 2.0702, RMSE 3.1523, Pearson 0.7818, Spearman 0.6484, and mean expected-minus-observed bias 0.0765. Observation-level predictive intervals were unavailable.

The three added terms have not demonstrated sufficient incremental practical or predictive value to justify retention in the operational model. The original candidate therefore excludes clay, wv0010, and spressure pending a controlled comparison. This is a model-parsimony and attribution decision; it does not assert that C-1 is inferior.

## C-1 qualification record

- Formula: intercept1 + intercept2; north + road_dens + night_illum + mintemp + soilmoist + leafarea + rhum + mintemp:soilmoist + mintemp:leafarea + cattle + horses + pigs + goats + sheep + clay + wv0010 + spressure, with the existing joint binomial/negative-binomial, spatial SPDE, temporal, administrative, shared/copy-field, and cattle RW2 components.
- Fixed-effect count: 19 including two tier intercepts.
- Stage 3B status: C1_STAGE3B_QUALIFIED_WITH_LIMITATIONS; ten hyperparameters and seven random-effect components were retained.
- Stage 1: 164,767 source rows; 163,730 retained; 968 outside the analysis domain/window; 69 duplicate records; zero invalid records. It produced 3,451,435 Tier 1 rows, 2,749,320 Tier 2 rows, 4,007,808 prediction-grid rows, and 252 modeled weeks.
- Stage 2: Tier 1/Tier 2 holdouts 4,768/7,471; 2,701,046 zero-count responses excluded under the original policy; 9,555/10,920 reporting-censored rows; 29,883 active Tier 2 training rows.
- Stage 3A: mesh 13,507 vertices; 20 quarter groups; A matrices 3,451,435 x 270,140 and 2,749,320 x 270,140; 19 fixed effects including both tier intercepts; no fit executed.
- Stage 3B: 12 CPUs, 280G requested memory, 48-hour allocation; elapsed 16:56:29; peak RSS approximately 168.2 GiB; exit status 0; fit artifact 6,893,458,325 bytes.
- Environmental coverage: the approved C-1 manifest records 252 weekly pressure inputs through 2026-W44 and static SoilGrids layers; baseline dynamic covariates retain 2022-W01 through 2026-W44 coverage. The manifest's source bytes and provenance remain part of the preserved C-1 record.
- Predictive status: C1_PREDICTIVE_VALIDATION_SUPPORTED_WITH_LIMITATIONS.
- Recorded warning: INLA_EXPERIMENTAL_VB_WARNING (two occurrences); retained as provenance and not treated as fit failure.
- Limitations: positive-only validation samples; no observation-level predictive intervals; no individual-predictor attribution; SoilGrids product alias is mutable; the ERA5-Land source is in Pa while the C-1 fitted column is recorded in kPa, with exact file-level scaling provenance unresolved.

The C-1 artifacts remain at their original paths and are not modified by this report.
