# Hominivorax-geostat input and workflow audit

**Audit date:** 2026-11-18
**Observation release identifier:** 2026-11-13
**Reviewed repository commit:** cf21c04ef53158b9bcca38dad75e7f75ee9e984a
**Working branch:** feature/revised-environmental-inputs
**Change classification:** D — scientific, numerical, and operational input revision

## Executive summary

The requested files are present and readable on Atlas. The new observation CSV parses with the existing observation interface, and the new surface-pressure weekly stack has complete, internally consistent ISO-week coverage through 2026-W44. The two added SoilGrids rasters are readable and align with each other.

The release is not ready for preprocessing or model fitting. The configured production horizon resolves from the new observations through 2026-W45, while the environmental stacks end at 2026-W44. There are 300 observations after the final covered environmental week. In addition, every weekly environmental sidecar records a template SHA256 that differs from the currently configured template file. Matching geometry does not resolve that byte-level support-mask provenance discrepancy.

The new environmental variables are not represented throughout the model interface. Readers can ingest generic file paths, but source aliases, transformations, provenance products, model design columns, formula terms, coefficient extraction, and reporting remain partly hard-coded to the current schema. Units and scaling for the new soil layers are undocumented; their scientific roles and transformations are also unspecified. No source/configuration registration, model formula, transformation, or production artifact was changed. Those decisions are separated below for resolution before implementation.

## Repository and operational baseline

- The GitHub-canonical repository was synchronized to commit cf21c04ef53158b9bcca38dad75e7f75ee9e984a using the documented GitHub-to-Atlas fast-forward workflow.
- The local feature branch is feature/revised-environmental-inputs. Atlas main is clean at the reviewed commit; no source-only edits were copied to Atlas.
- Production configuration is private and outside the Git repository. Its SHA256 is recorded in the manifest. The production config points to the 2026-10-17 observation file and resolves the end using last_complete_epiweek. It names the current four dynamic and seven static model inputs.
- The private preprocessing stage configuration has a different observation path, whose data end on 2026-07-31 (2026-W31). The production orchestrator replaces the stage observation path with the production-level input, so the current production path uses the 2026-10-17 file through 2026-W39. The mismatch is documented; neither private file was edited.
- The repository has no package DESCRIPTION or documented canonical test aggregator. The release procedures say to run relevant R tests. The exact source inputs, configs, software versions, and per-file checksums are in input-manifest.yml and input_file_hashes.tsv.

## Input integrity and raster metadata

Hashes and byte counts for the revised sources and their comparison/configuration artifacts are in input_file_hashes.tsv (511 records). The inventory includes the observation release and predecessor, the two private configuration files by checksum only, the two new static rasters, all 252 new weekly TIFFs and their 252 JSON sidecars, and the currently configured template raster. The four pre-existing weekly stacks were audited for week coverage and sidecar template provenance, but their individual file hashes are not enumerated in this revised-source inventory. Private configuration contents and observation records were not copied into the repository.

### Static SoilGrids inputs

| Source | Size | SHA256 | Raster and missing-value metadata | Declared units |
|---|---:|---|---|---|
| clay_0-5cm_mean_1000.tif | 191,530,251 bytes | 20f699cc64686bb5696e395f709232e5957ea3c6a4b39f6676517a502033f424 | One-band Int16; NoData -32768; no scale or offset | None |
| wv0010_0-5cm_mean_1000.tif | 160,551,981 bytes | 0786fa27fa1870b3d7737dca566972adec8a3e0f0a95230f6fec35af0a12d39c | One-band Int16; NoData -32768; no scale or offset | Raster metadata contains Mapped_units=10-3cm3cm-3 |

Both rasters have 39,812 columns by 14,509 rows at 1,000 m by 1,000 m, with extent x [-19,949,750, 19,862,250] and y [-6,148,000, 8,361,000]. Their CRS is declared as Homolosine with proj=igh, datum WGS84, and metre units; the WKT has no authority identifier. GDAL reports only a fuzzy ESRI:54052 match, which is not treated as an authoritative CRS declaration. The two static layers share geometry. Both differ in grid and CRS from the configured study-area template. The preprocessing reader projects target coordinates into each source raster for extraction; this does not resample the source or establish grid alignment with the template.

Do not infer clay units, scale, or offset. Preserve the wv0010 unit string exactly as metadata; no conversion has been authorized.

### Weekly environmental inputs

The new surface-pressure source directory contains 252 TIFFs and 252 JSON sidecars for every ISO week from 2022-W01 through 2026-W44. There are no missing or duplicate week identifiers, malformed filenames, unmatched sidecars, or gaps. Each sidecar week_id matches its filename; each selected-date list has the seven calendar dates for its ISO week; each output_sha256 matches the raster bytes. Sidecars report weekly_statistic=mean, aggregation_algorithm_version=weekly-v3-support-mask, and source_family_id=era5land_daily_mean_utc06.

The TIFFs are one-band Float32 rasters with band description mean and NaN NoData. Neither raster metadata nor sidecars declare a measurement unit, scale, or offset. The grid is 293 by 202 cells, with approximate resolution 24.995018926 km by 24.943655964 km; extent x [-4361.4108818, 2962.1296637] and y [-2202.9997156, 2835.6187891]. The CRS is custom Albers Equal Area, with datum WGS84 and units km; no recognized EPSG authority is declared. The first and last pressure rasters compare geometrically equal to the currently configured template.

The four pre-existing dynamic input stacks and the new pressure stack each report 252 complete ISO weeks from 2022-W01 to 2026-W44. The pressure stack is the new source; the other four are the configured minimum-temperature, soil-moisture, low leaf-area, and relative-humidity inputs.

### Template provenance discrepancy

All 1,260 weekly sidecars across the five environmental stacks record template_sha256 4be01f0ecaff35216a72eb8f27e791311af90d35b5a4fff1e46a74edb6dc633b. The configured template file, study_area_raster.tif, hashes to d968ebe17486bde29eb68dcfae3617c8fe0932c5cad256b843c3c2aafc973a66. No candidate raster in the current spatial_domain directory matched the sidecar hash.

This is a recorded provenance mismatch, not proof that either template is the wrong one. Pressure geometry matches the current template, but geometry equality cannot establish that the support mask bytes and provenance are equivalent. The historic template or its authoritative path must be identified, or the environmental products must be regenerated against the confirmed canonical template, before a production run.

## Observation schema and temporal audit

The new source is combined_clean_obs_2026-11-13.csv (7,304,653 bytes; SHA256 8fd21f9db11db3df20596fe7ad0b4cbbc8b895fbaad6f702c847ed5a05dd19fc). It has columns date, host, lon, and lat, with 167,078 rows. All fields are populated; dates parse, and coordinate parsing and range checks pass. Date strings range from 2022-02-10 through 2026-11-13. Coordinates range from longitude -111.812103 to -77.403 and latitude 7.2174 to 33.847694. The CSV has no CRS declaration; current preprocessing assigns EPSG:4326 to longitude and latitude.

The filename release date is 2026-11-13; the actual maximum record date is also 2026-11-13, which falls in ISO week 2026-W46. With the production rule last_complete_epiweek, the model endpoint resolves to 2026-W45, ending 2026-11-08. The environmental stacks end one week earlier, at 2026-W44. Exactly 300 observations fall after the W44 endpoint. The pipeline's complete dynamic coverage gate therefore blocks this input combination. No carry-forward or silent horizon truncation was applied.

The preceding production observation file is named combined_clean_obs_2026-10-17_through_2026-W39.csv, but its actual maximum date is 2026-09-27 (2026-W39). It contains 158,739 rows and has a leading unnamed column. The new file has 8,339 more rows and ends 47 days after the predecessor's actual maximum date. The private preprocessing-only input points to a third observation file ending 2026-07-31 (W31), but production orchestration currently overrides it with the production-level source.

## Workflow dependency inventory

The repository separates preprocessing, model preparation, INLA assembly/fitting, and postprocessing. The input schema is not driven by one canonical covariate registry; declarations are duplicated across configuration defaults, transformations, provenance, fixed-effect construction, extraction, and reporting.

| Workflow stage | Main interfaces | Current schema constraints relevant to this release |
|---|---|---|
| Configuration and production orchestration | R/preprocessing_config.R; R/production_orchestration.R; config/preprocessing.example.yml; config/production.example.yml; private production.yml and preprocessing.yml | Path lists are configured, but absent names default to four dynamic and seven static names. The orchestrator rewrites Stage 1 observations from production input. |
| Observation and spatial preprocessing | R/preprocessing_observations.R; R/preprocessing_spatial.R; R/preprocessing_temporal.R; R/preprocessing_pipeline.R | CSV coordinates are assigned the configured/input CRS. Pipeline maps only minimum_temperature to mintemp, soil_moisture to soilmoist, leaf_area_low to leafarea, and relative_humidity to rhum. Tier 1 requires road_density and night_illumination. |
| Raster discovery and extraction | R/preprocessing_covariates.R | Generic weekly index recognizes .tif/.grd and year/week labels, detects duplicate or missing weeks, and extracts dynamic and static layers by coordinate. This generic reader does not supply model aliases, units, transformations, or provenance product identifiers. |
| Transformation and Stage 1 output | R/preprocessing_transformations.R; R/preprocessing_outputs.R | Transformation metadata is hard-coded for four dynamic and seven static variables. Dynamics are standardized; static inputs use log1p/imputation rules. Required dynamic fields and the configured-template hash are recorded in output metadata. |
| Upstream source provenance | R/cds_upstream_provenance.R; docs/developer/upstream-cds-provenance.md | Required product/alias map covers four current dynamic products. The new pressure source is not included. Sidecar template SHA is retained, but not compared with the current configured template. |
| Model preparation and features | R/joint_model_preparation.R; R/joint_model_features.R; R/joint_model_config.R; config/joint_model.example.yml | Livestock variables and derived RW2 features are explicitly enumerated; environmental covariate transformations feed later design columns. |
| INLA fixed effects and assembly | R/joint_inla_effects.R; R/joint_inla_spec.R; R/joint_inla_build.R; R/joint_inla_preflight.R; config/joint_inla.example.yml; config/joint_inla_fit.example.yml | Fixed-effect mapping, names, formulas, interactions, and expected design columns encode the existing model terms. Preflight checks columns and finite values, not their scientific definitions. |
| Coefficient extraction and spatial projection | R/joint_inla_extract.R; R/joint_inla_project.R; R/joint_inla_rasterize.R; scripts/extract_joint_inla_results.R; scripts/run_joint_inla_projection.R; scripts/run_joint_inla_rasterization.R | Extraction and projection follow the assembled formula/design matrix. The extraction QA currently expects a fixed-effect count of 16. New effects would require matching metadata and projection behavior. |
| Postfit reporting and plots | R/postfit_reporting.R; R/plot_bivariate_response.R; scripts/run_postfit_reporting.R; config/postfit_reporting.example.yml; docs/developer/reporting-schema.md | Term labels/source notes enumerate current covariates; the structural temperature mask uses mintemp, and cattle source metadata is explicit. Tables and figures need a schema update if model terms change. |
| Production execution and acceptance | R/production_validation_gates.R; scripts/run_pipeline.R; scripts/run_pipeline_atlas.sh; scripts/submit_full_pipeline.sh; scripts/run_joint_inla_atlas.sh; scripts/run_postfit_reporting_atlas.sh; docs/developer/production-validation.md; docs/developer/production-orchestration.md | Existing gates enforce required covariate presence/finiteness and provenance contracts. Atlas wrappers and staged production validation remain authoritative. |
| Fixtures, diagnostics, and examples | scripts/create_preprocessing_demo_inputs.R; scripts/compare_spatial_support.R; config/preprocessing.demo.yml; tests/test_covariate_diagnostics.R; tests/test_joint_model_preparation.R; tests/test_cds_upstream_provenance.R | Demo generation, diagnostics, and examples repeat the current variable lists and aliases. |

The inventory also includes README.md, docs/data-and-preprocessing.md, docs/production-workflow.md, docs/model-specification.md, docs/developer/stage1-contract.md, stage2-contract.md, stage3a-contract.md, stage3b-contract.md, extraction-contract.md, and post-fit reporting documentation. Documentation should be revised when the new schema and scientific choices are approved.

## Configuration and software changes

This audit adds only the reviewable audit artifacts: repository-input-audit.md, input-manifest.yml, and input_file_hashes.tsv. It does not change source code, version-controlled runtime configuration, private production configuration, environmental data, production outputs, model artifacts, or archived validation results.

The generic readers are reusable, but production registration is incomplete. A future implementation will need to update the canonical covariate metadata and all downstream consumers listed above; update serialization and provenance; maintain model/design/extraction compatibility; update examples and synthetic fixtures; and add regression coverage for malformed or missing inputs, calendar parsing, schema consistency, coefficient metadata, artifact provenance, and archived model specifications. No archived-model-specification backward-compatibility test was found in the current test tree. No tests were weakened.

## Validation performed

The audit was classified D because it concerns scientific inputs, temporal coverage, spatial support, and production provenance. The following focused R scripts were run on Atlas against the synchronized reviewed commit using synthetic fixtures where applicable:

- tests/test_covariate_diagnostics.R
- tests/test_cds_upstream_provenance.R
- tests/test_production_orchestration.R
- tests/test_preprocessing_temporal_thinning.R
- tests/test_joint_model_preparation.R
- tests/test_joint_inla_fit_config.R
- tests/test_joint_inla_assembly.R
- tests/test_joint_inla_extract.R
- tests/test_joint_inla_project.R
- tests/test_postfit_reporting.R
- tests/test_postfit_acceptance.R

All commands returned exit code 0. The CDS provenance test printed its expected rejection case before sbatch. INLA assembly emitted an inla.mesh.2d deprecation message. The postfit-reporting test printed its pass banner and then an error from deferred_run(env): could not find function deferred_run, despite exit code 0; treat that test as not fully clean. No repository-wide runner is documented, so no alternate test runner or package check was substituted.

Runtime observed on Atlas: R 4.4.3, INLA 25.9.19, Matrix 1.7.0, terra 1.7.78, sf 1.0.21, yaml 2.3.8, readr 2.1.5, dplyr 1.1.4, stringr 1.5.1, lubridate 1.9.3, GDAL 3.8.5, Python 3.9.21. The loaded module report and sf runtime reported different GEOS/PROJ versions (module report: GEOS 3.14.0 and PROJ 9.7.0; sf_extSoftVersion: GEOS 3.12.1 and PROJ 9.2.1). This discrepancy was recorded and not changed.

No production preprocessing, full production dry run, model fitting, or HPC production workflow was submitted. The W45 environmental coverage gap and unresolved template provenance are blocking conditions for those steps.

Local static review completed: the checksum inventory has 511 file records; all recorded hashes are lowercase 64-character SHA256 digests and file paths are unique. Source IDs intentionally repeat for weekly file groups. git diff --cached --check passed after removing trailing whitespace from the metadata block.

The YAML manifest was reviewed as text but was not parsed locally because no YAML parser is installed in the workspace. This is an explicit unverified artifact check.

## Decisions required before implementation

1. **Temporal endpoint:** refresh all environmental sources through at least W45, or approve an explicitly bounded model horizon through W44. The current production rule only expresses last_complete_epiweek; do not silently alter it or drop 300 W45 observations.
2. **Template provenance:** identify and verify the template whose hash is recorded in the weekly sidecars, or authorize regenerating all five weekly stacks against the confirmed canonical template.
3. **Scientific registration:** state whether clay, wv0010, and surface pressure are to be source-only, additive model predictors, or replacements for existing variables. Define any units, scale conversion, transformation, interactions, missing-data policy, and expected model interpretation. The audit makes no assumptions about these.
4. **Observation release/configuration:** confirm that the 2026-11-13 source supersedes the W39 production input and whether the stale W31 preprocessing path should be corrected in private configuration. No private config has been modified.

Until these decisions are resolved, the revised sources are inventoried but not registered for production model use. No new fit or published product was created or overwritten.
