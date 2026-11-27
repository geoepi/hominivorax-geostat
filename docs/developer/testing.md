# Test execution

Run the repository's focused R regression suite from the repository root on
the intended project environment:

```sh
Rscript tests/run_tests.R
```

The runner discovers every `tests/test_*.R` file in sorted order and launches
each in a separate R process through `testthat::test_file()`. A temporary
testthat wrapper in the repository root sources the selected script, retaining
the project's root working directory while preserving testthat cleanup for
files that use `local_edition()`. An error in one script cannot hide the status
of later scripts. The child process uses `stop_on_failure = TRUE`; a failed
expectation or unhandled error produces a nonzero per-test exit status.
Top-level success banners have been removed so the runner is the only source of
a suite-level PASS summary.

Each test's stdout and stderr are captured separately and then relayed to the
terminal. A run directory contains `summary.tsv` and the per-test logs. By
default, the run directory is created under R's temporary directory; use
`--log-dir PATH` to retain it under a chosen location. The summary records each
test file, PASS/WARN/FAIL/SKIPPED status, process exit status, warning and skip
lines, duration, and log paths. Warnings are reported separately and do not
turn a successful test into a failure. An explicitly skipped file can be
listed by basename with `--skip FILE[,FILE...]`; all other discovered tests
still run. The final process exits nonzero if any executed test fails.

Check the failure-propagation regression independently with:

```sh
Rscript tests/run_tests.R --self-test
```

This creates temporary tests containing an intentional failed expectation, an
intentional unexpected error, and a repository-root path check. Both failures
must produce nonzero child exit statuses and the root path must pass before the
self-test reports PASS. `tests/test_validation_runner.R` exercises that check
through the canonical suite.

The YAML/input inventory regression is `tests/test_input_manifest.R`. It uses
the existing `yaml` package and the system `sha256sum` utility (or an already
installed `digest` package) to parse the manifest and compare the 511-row
checksum inventory, unique-ID registry, and observation weekly-count table.
The runner does not install packages or invoke production workflows.

## Test inventory

The runner currently discovers these 37 test scripts:

- `test_analysis_domain_conservation.R`, `test_c1_predictive_qualification.R`,
  `test_cds_upstream_provenance.R`,
  `test_configuration_c_registry.R`,
  `test_compare_spatial_support_help.R`, `test_covariate_diagnostics.R`,
  `test_input_manifest.R`, `test_joint_inla_assembly.R`,
  `test_joint_inla_cli_root.R`, `test_joint_inla_extract.R`,
  `test_joint_inla_fit_cli_root.R`, `test_joint_inla_fit_config.R`,
  `test_joint_inla_fit_contract.R`, `test_joint_inla_fit_health.R`,
  `test_joint_inla_preflight.R`, `test_joint_inla_project.R`,
  `test_joint_inla_rasterize.R`, `test_joint_inla_validate.R`,
  `test_joint_model_cli_root.R`, `test_joint_model_features.R`,
  `test_joint_model_preparation.R`, `test_joint_model_responses.R`,
  `test_observation_checksum_gate.R`, `test_original_refresh_contracts.R`,
  `test_postfit_acceptance.R`, `test_postfit_reporting.R`,
  `test_prepare_joint_model_help.R`, `test_preprocessing_temporal_thinning.R`,
  `test_production_orchestration.R`, `test_production_refresh_release.R`,
  `test_reporting_baseline_repairs.R`,
  `test_spatial_support.R`, `test_standardized_observations.R`,
  `test_structural_surface_diagnostics.R`, `test_temp15_rpi_derivative.R`,
  `test_temp16_rpi_qa_figure.R`, and `test_validation_runner.R`.

`tests/run_test_child.R` is runner support code, not a discovered test.
