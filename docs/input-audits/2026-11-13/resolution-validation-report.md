# Input audit resolution and validation hardening

**Resolution date:** 2026-11-19

**Repository branch:** `feature/revised-environmental-inputs`

**Audit commit:** `49fd00fcd9bd0b7d3b2f4873abb1c5ef58452c88`
**Scope:** source verification, provenance, metadata, and test infrastructure. No source raster, observation CSV, private production configuration, model, or production output was changed.

## Decision summary

| Decision | Status | Evidence boundary |
|---|---|---|
| `TEMPLATE_PROVENANCE` | `TEMPLATE_PROVENANCE_UNRESOLVED` | All scanned sidecars agree on one historic binary hash. Available current and legacy candidates do not match that hash; their comparison does not identify the historical file. |
| `TEMPORAL_COVERAGE_VERIFIED` | Verified for observation snapshot `784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac` | Observation weeks and environmental coverage were independently recounted. The same path has drifted since the prior audit, and the older snapshot remains separately recorded. |
| `SOURCE_METADATA_VERIFIED` | Partial | Authoritative product units and variable identities are documented. Exact downloaded product revisions and stored-unit transformations are missing for some files, especially surface pressure. |
| `TEST_HARNESS_VALIDATED` | See validation results below | Tests run through the new isolated-process canonical runner; runner failure cases are exercised by regression tests. |
| `MANIFEST_VALIDATED` | See validation results below | YAML, required fields, unique registry IDs/paths, SHA formatting, 511-record agreement, and provenance fields are checked by an R test. |

## Template provenance investigation

All 3,024 weekly sidecars in the 12 Atlas collections scanned on 2026-11-19 record the same `template_sha256`, `4be01f0ecaff35216a72eb8f27e791311af90d35b5a4fff1e46a74edb6dc633b`. The five collections used by the existing four dynamic covariates and the new surface-pressure input account for 1,260 of those sidecars. Each collection has 252 unique weeks from 2022-W01 through 2026-W44; sidecar weeks agree with filenames, and the seven selected dates agree with each ISO week. The recorded template hash is also present in sidecars created before the November W44 refresh: observed `created_utc` samples span 2026-08-28 to 2026-11-12.

The configured Atlas template is 15,066 bytes with SHA-256 `d968ebe17486bde29eb68dcfae3617c8fe0932c5cad256b843c3c2aafc973a66`. It does not match the sidecar hash. The local legacy template and Atlas checkpoint copy are byte-identical to one another (14,528 bytes; SHA-256 `cb331565767a8f16b385684dbec23cea9247d77927c5c93edbbceb18f04517e5`) but do not match either the configured or sidecar hash.

The configured template and the available legacy/checkpoint raster have the same 202-by-293 dimensions, numeric transform, extent, resolution, origin, cell ordering, NA mask (42,427 NA cells), and cell values (every non-missing cell equals 1). They are therefore numerically equivalent as arrays on the same grid. The legacy/checkpoint file has no embedded CRS and no paired projection file, so CRS equivalence cannot be established from that file. A further CRS5070 candidate has the same cell values and mask but coordinate geometry scaled by 1,000 relative to the configured km grid; it also does not match the sidecar hash. None of the available candidates can be linked to the historic sidecar hash.

Repository history contains no tracked template raster or replacement commit that resolves the hash. Sidecars do not record a template path. For the available candidates, cell contents and numeric grid fields match while CRS metadata differs; because the file represented by the historic hash is unavailable, the hash discrepancy cannot be attributed to changed geometry/support/cell values versus CRS metadata or serialization. Binary identity is not established; candidate-array equivalence is not proof of historic support-mask provenance. The required classification is **`TEMPLATE_PROVENANCE_UNRESOLVED`**. No raster was regenerated or overwritten.

## Temporal coverage verification

The observation file at the audited path was independently reread on Atlas. Its content has changed since the 2026-11-18 audit even though its path and filename are unchanged:

| Snapshot | Bytes | SHA-256 | Rows | Column order |
|---|---:|---|---:|---|
| Prior audit snapshot (2026-11-18) | 7,304,653 | `8fd21f9db11db3df20596fe7ad0b4cbbc8b895fbaad6f702c847ed5a05dd19fc` | 167,078 | `date, host, lon, lat` |
| Independent recheck (2026-11-19) | 7,191,829 | `784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac` | 164,767 | `date, lon, lat, host` |

The newer read has 2,311 fewer rows and 112,824 fewer bytes. It has dates from 2022-02-10 (2022-W06) through 2026-11-13 (2026-W46), 246 nonzero weeks across 249 consecutive weeks, no missing required fields, no invalid dates, and no invalid coordinates. Its 249-row weekly-count table, including zero-count weeks, is preserved in [`observation_weekly_counts.tsv`](observation_weekly_counts.tsv). The CSV itself was not changed. Why the bytes changed, and which snapshot is the authorized release, remain unresolved.

All five required environmental stacks cover exactly 2022-W01 through 2026-W44 (252 weeks each), with no missing or duplicate week IDs. The filename and sidecar week IDs agree, and the selected daily dates follow the ISO Monday-through-Sunday convention.

The previously reported “300 observations beyond environmental coverage” conflated two cutoffs. In the 2026-11-19 observation snapshot:

- 911 records fall in W44, the last environment-covered week.
- 668 records fall in W45, which is within the observation-derived last-complete-week horizon ending 2026-11-08 but has no environmental rasters.
- 300 records fall in W46, after that candidate horizon and after the environmental endpoint.
- Therefore 968 records (668 + 300) follow environmental coverage at W44; **300** is the count after the candidate W45 analysis cutoff, not the total after environmental coverage.

These are separate coverage fields. Current production configuration remains pointed at the older observation file through 2026-W39, with configured coverage 2024-W01 through 2026-W39. The W45 candidate endpoint is not substituted into production configuration, and no horizon was silently shortened.

## Environmental source metadata

The official [ISRIC SoilGrids layer documentation](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html) describes clay mapped units as g/kg, with conversion factor 10 to g/100g (%), and `wv0010` as volumetric water content at 10 kPa mapped in 10⁻³ cm³ cm⁻³, with conversion factor 10 to 10⁻² cm³ cm⁻³ (%). It identifies the 0–5 cm interval as a standard SoilGrids layer and says the 1 km aggregated products are means from the 250 m products. These are authoritative product-level definitions, not proof of the exact source revision or any transformation applied to these particular TIFFs.

| Input | Product-level identity and units | Stored TIFF metadata | Source revision / processing |
|---|---|---|---|
| `clay_0-5cm_mean_1000.tif` | SoilGrids `clay`, mean, 0–5 cm; official mapped units g/kg; conventional units g/100g (%) after dividing mapped values by 10. | Int16; NoData -32768; no unit, scale, or offset tag. The exact file's stored units cannot be certified from its metadata. | The filename indicates 1 km mean product; exact download/product revision and any local processing history were not retained. Do not apply a conversion based solely on this audit. |
| `wv0010_0-5cm_mean_1000.tif` | SoilGrids `wv0010`, volumetric water content at 10 kPa, mean, 0–5 cm; mapped unit 10⁻³ cm³ cm⁻³, conventional percent representation after the documented factor-of-10 conversion. | Int16; NoData -32768; band metadata contains `Mapped_units=10-3cm3cm-3`; no scale or offset tag. No conversion was applied in this audit. | The filename indicates 1 km mean product; exact download/product revision and local processing history were not retained. |
| `era5land_surface_pressure_mean` | ERA5-Land surface pressure `sp`, parameter 134, product-level units Pa, per [ECMWF ERA5-Land parameter documentation](https://confluence.ecmwf.int/pages/viewpage.action?pageId=143037634). Source family is `era5land_daily_mean_utc06`; the weekly output is the mean over seven selected daily dates. | Float32, one band named `mean`, NoData NaN; no unit, scale, or offset tag. For W01 2022, 16,756 of 59,186 cells are finite; their measured min/mean/max/sd are 66.876854 / 94.207401 / 102.18423 / 7.6890287. Cached GDAL mean and SD metadata are -9999 and are invalid; computed values above come from the raster cells. | Exact retrieval revision and stored-unit conversion are absent from the sidecar. The values could reflect a pressure scaling step, but that is an inference and is not sufficient to assign stored units. Product-level ERA5-Land temporal/spatial characteristics are documented by [ECMWF](https://confluence.ecmwf.int/pages/viewpage.action?pageId=143037634); the exact upstream grid and conversion used for these weekly files are not recoverable from current provenance. |

The source metadata decision is **partial**, not a blanket pass. Product definitions are verified; per-file stored units, exact input revisions, and pressure scaling are unresolved. No scientific role, transformation, model term, or replacement source is approved by this audit.

## Test-harness diagnosis and repair

The earlier direct invocation of `Rscript tests/test_postfit_reporting.R` printed a success banner, then raised `could not find function "deferred_run"` during cleanup and still returned exit code 0. The test file calls `testthat::local_edition(3)` at top level. Direct script sourcing does not establish the testthat file context in which its deferred cleanup is registered; this is an invocation/lifecycle defect, not an unavailable helper, missing package, stale fixture, or incorrect source order. Running the file via `testthat::test_file()` completes cleanly.

The canonical runner now launches each test file in an isolated R child process through `testthat::test_file(..., stop_on_failure = TRUE)`. This preserves testthat lifecycle handling and causes an assertion failure or unhandled error to make that test's process nonzero. Unconditional test success banners were removed so deferred assertions cannot print a misleading PASS. The runner captures and relays stdout and stderr, writes per-test exit/status/log records, reports warnings and skips separately, and exits nonzero if any executed test fails. Its self-test injects a failed expectation and an unexpected error; `test_validation_runner.R` covers both cases through the canonical suite.

The canonical command is:

```sh
Rscript tests/run_tests.R
```

Manifest parse and inventory regression is included in `tests/test_input_manifest.R`. Its validation uses existing `yaml` plus `sha256sum` or an already-installed `digest`; no software is installed.

## INLA deprecation assessment

The warning comes from the **`INLA::inla.mesh.2d()` function**, called by the affected `tests/test_joint_inla_assembly.R`; the preprocessing source `R/preprocessing_spatial.R` also calls that function. The Atlas runtime is INLA **25.9.19**. The test completes under the installed version, so the observed warning is informational for this validation run and not a current compatibility failure. Because the API is marked deprecated, removal in a later INLA release could become a compatibility failure. No INLA upgrade or mesh specification change was made. The exact warning text and final test disposition are recorded after the canonical run in the validation results below.

## Validation results

The full test suite and manifest checks are run on Atlas through the repository's `scripts/atlas_runtime.sh` bootstrap, using the branch fetched from GitHub into a temporary validation worktree. No production preprocessing, dry-run, fit, geographic prediction, environmental regeneration, or HPC production job is part of this validation. Final per-test counts, warnings, commit SHA, and remote branch status are appended here after that run.
