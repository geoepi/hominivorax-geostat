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
| `TEST_HARNESS_VALIDATED` | Passed with warnings | All 32 discovered scripts returned zero; 18 were PASS and 14 reported warnings. No test was skipped or failed. |
| `MANIFEST_VALIDATED` | Passed | The YAML and inventory regression passed against the 511-record inventory, unique registry, and weekly-count table. |

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

The Atlas runtime is INLA **25.9.19**. The final suite reported both deprecated functions in `R/preprocessing_spatial.R`:

- `INLA::inla.mesh.2d()` was deprecated in INLA 23.08.18; the warning recommends `fmesher::fm_mesh_2d_inla()`. It appears in `tests/test_joint_inla_assembly.R` and `tests/test_spatial_support.R`.
- `INLA::inla.sp2segment()` was deprecated in INLA 2023.06.06; the warning recommends `fmesher::fm_as_segm()`. It appears in `tests/test_spatial_support.R`.

Both calls still run in the installed version, so these are informational warnings for this validation and not current compatibility failures. Removal in a later INLA release could cause a compatibility failure. No INLA upgrade or mesh specification change was made.

## Validation results

The full suite was run on Atlas through the repository's `scripts/atlas_runtime.sh` bootstrap in a temporary worktree at commit `e51a99f2bed79de905657fcd4d3335973678e884`. `Rscript tests/run_tests.R` exited 0: 32 scripts executed, 18 PASS, 14 WARN, 0 skipped, and 0 FAIL. Every child process returned exit status 0. The 14 warnings include the INLA deprecations above, expected warning output from negative-path regression checks, and Atlas time-zone/runtime warnings; they were retained in the captured logs and are not test failures.

`tests/test_input_manifest.R` passed. It parsed the v2 YAML, checked required provenance fields, compared all 511 records to the unique-ID registry, checked unique paths and SHA-256 formatting, validated newline-normalized inventory and registry checksums, and verified the 249-row weekly-count table totals 164,767 observations. `tests/test_validation_runner.R` passed; its self-test verified nonzero child statuses for an intentional failed expectation and unexpected error, plus the repository-root working directory.

After the report and manifest were updated with these outcomes, a focused canonical-runner check at commit `2b1ad2e1492c5cb775f0efebdd71bed014ef0643` reran `test_input_manifest.R` and `test_validation_runner.R`: 2 executed and passed, 30 explicitly skipped for this focused check. This confirms the final manifest syntax and fields after the validation metadata was recorded; the full 32-script suite result above is from the immediately preceding source commit, which contains the same test implementation.

The full-suite logs are under `/tmp/validation-input-audit-logs-e51a99f/run-2b4ba4e137562`; the final focused logs are under `/tmp/validation-input-audit-logs-2b1ad2e/run-2b89472d420efa` on Atlas. The Atlas spatial runtime preflight passed. It also reported the previously documented GEOS compile/runtime mismatch (packages compiled with GEOS 3.12.1, runtime GEOS 3.14.0); this environment was not changed.

Validation omitted production preprocessing, production dry-run, model fitting, geographic prediction, environmental regeneration, and HPC submission because they are outside this phase's scope. No model workflow was started. The repository has no package `DESCRIPTION` or package-wide check entry point; no alternate package checker was substituted. `git diff --check` passed on the completed branch diff.

## Final input identity and metadata reconciliation (2026-11-21)

This section is an additive follow-up to the 2026-11-19 resolution. It preserves the original audit snapshot and the prior unresolved template classification as historical findings. No observation file, environmental raster, sidecar, private production configuration, or other production artifact was changed.

### Starting state and production integrity

The local checkout began on `feature/revised-environmental-inputs` at `8808382a320ed0571db1b044c1834559ed1ccc41`, clean and synchronized with `origin/feature/revised-environmental-inputs`. Atlas HGE remained at `cf21c04ef53158b9bcca38dad75e7f75ee9e984a`. Current hashes for the private production and preprocessing configurations match the manifest values (`0667d4ab…` and `8fe922db…`). The registered W44 surface-pressure GeoTIFF and sidecar still match their existing inventory checksums (`be1cb862…` and `2a7c5eea…`). Observation checksum and modification time were identical before and after reading. All Atlas inspection was read-only; temporary NetCDF members were extracted under `/tmp` and removed.

### Observation release identity

The source at the registered path was hashed immediately before and after reading. Both hashes were `784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac`; size was 7,191,829 bytes and modification time was 2026-11-19 10:06:23.592700507 -0600. The file has 164,767 rows and columns `date, lon, lat, host`, with dates 2022-02-10 through 2026-11-13. Recalculation found 249 ISO weeks from 2022-W06 through 2026-W46, 246 nonzero weeks, and 3 zero-count weeks. The 249-row weekly-count table sums to 164,767 and retains SHA-256 `34cf710666de6a523d1efb7593cceb44c028f846a4218aec843dc6144536c81d`.

| Record | SHA-256 | Bytes | Rows | Columns |
|---|---|---:|---:|---|
| Original 2026-11-18 audit manifest and checksum inventory | `8fd21f9db11db3df20596fe7ad0b4cbbc8b895fbaad6f702c847ed5a05dd19fc` | 7,304,653 | 167,078 | `date, host, lon, lat` |
| Revised v2 recheck and current source | `784168081cc1d3206f3537e8731994cbfc34be15be7c515fe06710d4ea9bdaac` | 7,191,829 | 164,767 | `date, lon, lat, host` |

The current file agrees with the revised v2 manifest, while the existing checksum inventory still identifies the original snapshot. The original hash was not found among the seven named `combined_clean_obs*` files in the project data tree. Other dated files are distinct releases; no source-release authorization, preprocessing log, or record explaining the 2,311-row and 112,824-byte reduction was found. Since the original bytes are unavailable, no week-by-week or row-level delta was reconstructed. The required classification remains **`OBSERVATION_RELEASE_CHANGED_PROVENANCE_UNRESOLVED`**.

### Template provenance closure

The sidecar hash `4be01f0ecaff35216a72eb8f27e791311af90d35b5a4fff1e46a74edb6dc633b` is now identified as the exact binary at `/project/disease_ecology/cds-datagrab/spatial_domain/study_area_raster.tif`. Git history records that binary at commit `334681b2d2b40fb5934df342fb2c7715fb337c37` (2026-07-27), before the audited sidecars were created; the deployed CDS checkout also contains the same binary. Its preceding tracked template at `088d8624323aeabddbe2bd9844cb6086c8151652` has the earlier `cb331565…` hash. Thus the historic hash is no longer an unidentified raster.

The separate comparisons are:

| Property | Finding |
|---|---|
| Binary identity | The historic sidecar SHA-256 exactly matches the tracked CDS template. The currently configured HGE template has a different SHA-256 (`d968ebe1…`). |
| Numerical equivalence | Historic and current configured templates have exactly equal cell values and NA masks. |
| Grid geometry | Dimensions, resolution, extent, and origin are exactly equal. |
| CRS equivalence | CRS definitions compare equal. Both describe the custom Albers Equal Area CRS on WGS84 with kilometre units and no EPSG authority declared. |
| Historic provenance | The version-controlled CDS raster at the matching hash predates the observed sidecar creation interval. Sidecars record the hash but not the runtime path. |

The CRS5070 candidate retains the same cell values and NA mask but has different numeric grid geometry and a different CRS. No raster was regenerated or replaced. The final classification is **`TEMPLATE_PROVENANCE_RESOLVED`** for the historic binary and its numeric/grid/CRS identity; this follow-up supersedes the prior unresolved classification without erasing that historical result.

### Surface-pressure pipeline and units

The applicable CDS source checkout is commit `a6f2ec6c7742f5b2d79cce589ff207f60966f988`. The production family configuration is `config/era5land_daily_mean_utc06_production.yml`; the family builder and archive mapping enumerate the eight product variables. Supporting code references are `R/variable_registry.R:15,24,46`, `R/era5land_family.R:194-197`, `R/era5land_archive.R:74-89`, `R/netcdf_processing.R:50-56,95-129,147-162`, `R/daily_processing.R:199-200`, and `R/weekly_aggregation.R:124-143`.

ECMWF documents ERA5-Land surface pressure as `sp` / parameter 134 in Pa ([ERA5-Land data documentation](https://confluence.ecmwf.int/pages/viewpage.action?pageId=143037634)). The local `era5land_surface_pressure_mean` specification identifies source variable `surface_pressure`, accepts NetCDF alias `sp`, expects Pa, and sets output units to kPa with `pascal_to_kilopascal`. Its numerical conversion divides by 1,000. The current production source archive headers were checked across 64 stored monthly ZIPs: all 64 readable `sp` variables declare Pa, and none has `scale_factor` or `add_offset` attributes.

There is a source-code edge case: `ncdf4::ncvar_get(..., raw_datavals=FALSE)` applies nonidentity NetCDF scale/offset attributes automatically, and `read_daily_netcdf()` then explicitly multiplies by `scale_factor` and adds `add_offset`. The [ncdf4 source documentation](https://github.com/cran/ncdf4/blob/master/R/ncdf4_priv_var.R) confirms the automatic decode. This did not double-scale any of the 64 stored source archives because their scale and offset attributes are absent. A future source with nonidentity attributes would pass through both steps and needs code review before processing.

The W44 weekly sidecar links seven daily pressure rasters. Each daily sidecar preserves `source_variable=surface_pressure`, `netcdf_alias=sp`, `source_units=Pa`, `output_units=kPa`, and `unit_conversion=pascal_to_kilopascal`. Weekly processing takes the mean of those converted daily rasters. The GeoTIFF itself is Float32, and neither the raster nor the weekly sidecar declares units, scale, or offset; the daily sidecars and code establish the weekly value units as kPa, but the weekly output is not self-describing. This determination uses explicit metadata and code lineage, not numerical value ranges.

### SoilGrids acquisition and stored units

The existing `provenance/official_manifest.tsv` provides property, filename, expected SHA-256, and source URL. Its SHA-256 is `54cb5e1743c9ac4c8d33d0d67fa65970ff101fd5a93608dc1161287bac52ab15`. For both registered files, the current raster checksum exactly matches the manifest entry and the corresponding per-property checksum record:

| File | Product identity and physical/stored mapped units | Revision and processing evidence |
|---|---|---|
| `clay_0-5cm_mean_1000.tif` | SoilGrids clay mean, 0–5 cm, 1000m product; mapped and stored units are g/kg. The GeoTIFF has no scale or offset tag. The conventional percent conversion is division by 10 and was not applied. | The exact bytes match the manifest source URL under the mutable `latest` alias. A named product revision and retrieval timestamp are unknown. ISRIC describes its 1000m products as means aggregated from 250m predictions. No local processing log was found; the file is byte-identical to the recorded official source. |
| `wv0010_0-5cm_mean_1000.tif` | SoilGrids volumetric water content at 10 kPa, mean, 0–5 cm; mapped and stored units are `10^-3 cm3 cm-3`, also confirmed by its `Mapped_units` tag. The GeoTIFF has no scale or offset tag. The conventional percent conversion is division by 10 and was not applied. | The exact bytes match the manifest source URL under the mutable `latest` alias. A named product revision and retrieval timestamp are unknown. The official 1000m product is an aggregate of mean predictions from 250m. No local processing log was found; the file is byte-identical to the recorded official source. |

The [ISRIC SoilGrids layer documentation](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html) supplies the mapped-unit definitions and conversion factors. The registered files are therefore tied to exact official source bytes, although their named revision and local acquisition/processing log remain unknown.

### Validation and remaining findings

The complete diff is category **C** because it adds executable manifest assertions; the other changes are additive audit metadata and report text. No application code, scientific parameters, data paths, or production artifacts changed. The focused canonical validation runs `tests/test_input_manifest.R` and `tests/test_cds_upstream_provenance.R` through `Rscript tests/run_tests.R`, skipping the other 30 test scripts. The full 32-script suite is not repeated because the change is confined to manifest/report content and its focused checks. Validation output and `git diff --check` status will be recorded in the final reconciliation manifest after they run.

Unresolved findings are limited to the missing historical observation snapshot and explanation/authorization for its row change; the absent named SoilGrids revision and local retrieval log; missing unit declarations on weekly pressure outputs; and the conditional duplicate scale/offset application path (no such attributes were present in the stored archives inspected). No model fitting, geographic prediction, environmental regeneration, or production artifact replacement was performed.
