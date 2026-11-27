suppressPackageStartupMessages(library(testthat))

repo_candidates <- unique(c(getwd(), normalizePath(file.path(getwd(), ".."), mustWork = FALSE)))
repo_root <- repo_candidates[file.exists(file.path(repo_candidates, "R", "production_orchestration.R"))][[1L]]
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_validation_gates.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_refresh_release.R"), local = .GlobalEnv)

fixture_hash <- function(path) digest::digest(file = path, algo = "sha256")
fixture_write <- function(path, text = "fixture\n") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(text, path, useBytes = TRUE)
  normalizePath(path, mustWork = TRUE)
}

fixture_write_csv <- function(data, path, ...) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, path, ...)
  normalizePath(path, mustWork = TRUE)
}

make_adoption_fixture <- function(metadata_commit = NULL, record_stage1_metadata = TRUE, include_provenance_reconciliation = FALSE) {
  root <- tempfile(pattern = "refresh_adoption_fixture_")
  dir.create(root, recursive = TRUE)
  source_root <- file.path(root, "source")
  output_root <- file.path(root, "production_runs")
  observation_path <- fixture_write(file.path(root, "observations.csv"), c("date,lon,lat", "2024-01-01,-90,30", "2024-01-14,-91,31"))
  environmental_path <- fixture_write(file.path(root, "environmental-identity.yml"), "availability_endpoint: 2024-W03\n")
  formula_reference <- "R/joint_inla_spec.R::make_joint_formula with covariate_registry=null"
  commit <- paste(rep("a", 40L), collapse = "")
  report_commit <- paste(rep("b", 40L), collapse = "")
  metadata_commit <- metadata_commit %||% commit

  artifact_paths <- list(
    stage1 = file.path(source_root, "outputs/stage1/model_inputs.rds"),
    stage1_audit = file.path(source_root, "outputs/stage1/stage1_reuse_audit.csv"),
    stage2 = file.path(source_root, "outputs/stage2/joint_model_inputs.rds"),
    stage2_audit = file.path(source_root, "outputs/stage2/joint_model_preparation_audit.csv"),
    stage3a = file.path(source_root, "outputs/stage3a/joint_inla_build.rds"),
    formula_audit = file.path(source_root, "outputs/validation/formula_audit.csv"),
    fit = file.path(source_root, "outputs/stage3b/joint_model_fit.rds"),
    fit_metadata = file.path(source_root, "outputs/stage3b/joint_model_fit_metadata.rds"),
    fit_stdout = file.path(source_root, "original-refresh-fit-12345.out"),
    fit_stderr = file.path(source_root, "original-refresh-fit-12345.err"),
    fit_health = file.path(source_root, "outputs/stage3b/fit_health.csv"),
    extraction_audit = file.path(source_root, "outputs/extraction/extraction_audit.csv"),
    validation_metrics = file.path(source_root, "outputs/validation/metrics.csv"),
    validation_audit = file.path(source_root, "outputs/validation/validation_audit.csv")
  )
  fixture_write(artifact_paths$stage1, "stage1 artifact\n")
  fixture_write(artifact_paths$stage2, "stage2 artifact\n")
  fixture_write(artifact_paths$stage3a, "stage3a artifact\n")
  fixture_write(artifact_paths$fit, "fit artifact\n")
  fixture_write(artifact_paths$stage2_audit, c("stage,scope,metric,value", "Stage 2,rows,count,2"))
  fixture_write(artifact_paths$validation_metrics, "metric,value\nscore,1\n")
  fixture_write(artifact_paths$fit_stderr, "")

  stage1_checks <- c("reused_stage1_sha256", "approved_observation_checksum", "temporal_window", "original_predictor_schema")
  fixture_write_csv(data.frame(check = stage1_checks, status = "PASS", observed = "ok", expected = "ok"), artifact_paths$stage1_audit, row.names = FALSE)
  formula_checks <- c("fixed_effect_names", "fixed_effect_order", "fixed_effect_count", "no_c1_only_terms", "manifest_free_original_formula", "joint_likelihoods", "fit_not_executed", "frozen_reference_formula_regeneration")
  formula_audit <- data.frame(check = formula_checks, status = "PASS", observed = "ok", expected = "ok", stringsAsFactors = FALSE)
  formula_audit$observed[formula_audit$check == "fixed_effect_count"] <- "16"
  formula_audit$expected[formula_audit$check == "fixed_effect_count"] <- "16 including both tier intercepts"
  fixture_write_csv(formula_audit, artifact_paths$formula_audit, row.names = FALSE)
  fit_health_checks <- c("fit_artifact_exists", "likelihood_families", "fit_completion_status", "fit_internal_ok")
  fixture_write_csv(data.frame(section = "fit_health", check = fit_health_checks, status = "PASS", observed = "ok", expected = "ok"), artifact_paths$fit_health, row.names = FALSE)
  extraction_checks <- c("disjoint_exhaustive_indices", "predictor_layout", "tier_row_counts")
  fixture_write_csv(data.frame(section = "fit", check = extraction_checks, status = "PASS", observed = "ok", expected = "ok"), artifact_paths$extraction_audit, row.names = FALSE)
  validation_checks <- c("stage2_holdout_counts", "holdout_rows_are_test_points", "holdout_response_finite")
  fixture_write_csv(data.frame(section = "inputs", check = validation_checks, status = "PASS", observed = "ok", expected = "ok", blocking = TRUE), artifact_paths$validation_audit, row.names = FALSE)
  fixture_write(artifact_paths$fit_stdout, c(paste0("Original refresh Stage 3B job: 12345"), paste0("Repository: ", commit), "Fit config SHA-256: fixture"))

  identity_path <- file.path(source_root, "config/original/identity.yml")
  stage2_config_path <- file.path(source_root, "config/original/joint_model.yml")
  stage3a_config_path <- file.path(source_root, "config/original/joint_inla.yml")
  fit_config_path <- file.path(source_root, "config/original/joint_inla_fit.yml")
  dir.create(dirname(identity_path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(list(model = list(identifier = "ORIGINAL_REFRESH_W44_2026", specification_revision = "original_joint_inla_v1", frozen_specification_reference = formula_reference),
                        source = list(observation_sha256 = fixture_hash(observation_path))), identity_path)
  yaml::write_yaml(list(inputs = list(model_inputs = "outputs/stage1/model_inputs.rds"), covariate_manifest = NULL), stage2_config_path)
  yaml::write_yaml(list(inputs = list(joint_model_inputs = "outputs/stage2/joint_model_inputs.rds")), stage3a_config_path)
  yaml::write_yaml(list(inputs = list(stage3a_build = "outputs/stage3a/joint_inla_build.rds")), fit_config_path)
  artifact_paths$config_identity <- identity_path
  artifact_paths$config_stage2 <- stage2_config_path
  artifact_paths$config_stage3a <- stage3a_config_path
  artifact_paths$config_fit <- fit_config_path

  stage1_sha <- fixture_hash(artifact_paths$stage1)
  stage2_sha <- fixture_hash(artifact_paths$stage2)
  stage3a_sha <- fixture_hash(artifact_paths$stage3a)
  fit_sha <- fixture_hash(artifact_paths$fit)
  stage1_metadata_path <- if (isTRUE(record_stage1_metadata)) artifact_paths$stage1 else NA_character_
  metadata <- list(
    provenance = list(
      chain = list(
        stage1 = list(artifact_path = stage1_metadata_path),
        stage2 = list(artifact_path = artifact_paths$stage2, artifact_sha256 = stage2_sha),
        stage3a = list(artifact_path = artifact_paths$stage3a, artifact_sha256 = stage3a_sha, executed_fit = FALSE),
        stage3b = list(config_path = fit_config_path, output_fit = artifact_paths$fit)
      ),
      runtime = list(git_commit = metadata_commit)
    ),
    audit = list(
      fit_status = "success", git_commit = metadata_commit, start_timestamp = "2024-01-01T00:00:00Z", end_timestamp = "2024-01-01T00:01:00Z",
      stage1_artifact_path = stage1_metadata_path, stage2_artifact_path = artifact_paths$stage2,
      stage2_artifact_sha256 = stage2_sha, stage3a_artifact_path = artifact_paths$stage3a,
      stage3a_artifact_sha256 = stage3a_sha, stage3b_config_path = fit_config_path
    )
  )
  saveRDS(metadata, artifact_paths$fit_metadata)

  artifact_manifest_path <- file.path(root, "artifact_manifest.csv")
  inventory <- data.frame(role = names(artifact_paths), path = unname(unlist(artifact_paths)),
    sha256 = vapply(artifact_paths, fixture_hash, character(1L)),
    bytes = vapply(artifact_paths, function(path) as.numeric(file.info(path)$size), numeric(1L)),
    stringsAsFactors = FALSE)
  fixture_write_csv(inventory, artifact_manifest_path, row.names = FALSE, quote = TRUE)

  canonical_path <- file.path(root, "canonical-tests.tsv")
  utils::write.table(data.frame(test_file = "test_fixture.R", status = "PASS", exit_status = 0L),
    canonical_path, sep = "\t", quote = FALSE, row.names = FALSE)
  qualification_report <- fixture_write(file.path(root, "qualification-report.md"), "Final qualification: ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS\n")
  superseded_qualification_path <- fixture_write(file.path(root, "historical-qualification.json"), "{\"historical\":true}\n")
  qualification_path <- file.path(root, "qualification.json")
  formula_sha <- fixture_hash(artifact_paths$formula_audit)
  provenance_reconciliation_path <- NULL
  if (isTRUE(include_provenance_reconciliation)) {
    provenance_reconciliation_path <- file.path(root, "source-provenance-reconciliation.json")
    tree_id <- paste(rep("c", 40L), collapse = "")
    fixture_reconciliation <- list(
      schema_version = 1L, record_id = "fixture-source-reconciliation-v1",
      fit = list(job_id = "12345", launch_commit = commit, metadata_runtime_commit = metadata_commit,
                 metadata_audit_commit = metadata_commit, launch_commit_recorded_at = "2024-01-01T00:00:00Z",
                 metadata_commit_recorded_at = "2024-01-01T00:00:30Z", audit_start_utc = "2024-01-01T00:00:00Z",
                 audit_end_utc = "2024-01-01T00:01:00Z"),
      comparison = list(
        changed_paths = c("docs/archive/configuration-c-1-2026/assessment.md", "docs/archive/configuration-c-1-2026/summary.csv"),
        documentation_paths = "docs/archive/configuration-c-1-2026/assessment.md",
        archived_scientific_evidence_paths = "docs/archive/configuration-c-1-2026/summary.csv",
        test_only_paths = character(), executable_paths = character(), model_specification_paths = character(),
        configuration_paths = character(), runtime_setting_paths = character(),
        launch_tree_ids = list(R = tree_id, scripts = tree_id, config = tree_id, tests = tree_id),
        metadata_tree_ids = list(R = tree_id, scripts = tree_id, config = tree_id, tests = tree_id),
        fit_relevant_trees_identical = TRUE, model_behavior_changed = FALSE, executable_source_changes = 0L, test_file_changes = 0L,
        configuration_file_changes = 0L, model_definition_changes = 0L, likelihood_or_runtime_setting_changes = 0L,
        classification = "NON_EXECUTABLE_C1_ARCHIVE_ONLY"),
      metadata_discrepancy = "The W44 worktree HEAD was updated during the fit audit window by a commit adding C-1 archive reports only; the model execution commit from the Slurm launch remains authoritative.",
      decision = list(status = "RECONCILED_NON_EXECUTABLE_METADATA_DRIFT", source_identity = "launch_commit",
        governance_mode = "HGE", authorization_basis = "USER_TASK_CONDITIONAL_PROVENANCE_RECONCILIATION",
        production_activation_authorized = FALSE))
    jsonlite::write_json(fixture_reconciliation, provenance_reconciliation_path, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  }
  qualification <- list(
    evidence_schema_version = 2L,
    supersedes = list(path = superseded_qualification_path, sha256 = fixture_hash(superseded_qualification_path)),
    decision_status = "W44_PRODUCTION_PROMOTION_BLOCKED",
    review_date = "2026-11-27",
    historical_model_preservation = list(),
    active_production_snapshot = list(),
    deployment_manifest_reconciliation = list(),
    activation = list(),
    integration = list(),
    candidate_model = list(
      model_id = "ORIGINAL_REFRESH_W44_2026", proposed_production_id = "ORIGINAL_W44_2026_PRODUCTION", active_in_production = FALSE,
      qualification_status = "ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS",
      formula_identity = "original_joint_inla_v1", formula_reference = list(path = formula_reference, fixed_effect_count_including_intercepts = 16L),
      data_release = list(release_id = "2026-11-13", observations_sha256 = fixture_hash(observation_path), analysis_start_epiweek = "2024-W01", analysis_end_epiweek = "2024-W03"),
      fit = list(slurm_job_id = "12345", artifact_path = artifact_paths$fit, artifact_bytes = file.info(artifact_paths$fit)$size, artifact_sha256 = fit_sha),
      repository = list(fit_source_commit = commit, metadata_runtime_commit = metadata_commit, report_generation_commit = report_commit),
      runtime = list(environment = "fixture"),
      stages = list(list(stage = "1", path = artifact_paths$stage1, sha256 = stage1_sha),
                    list(stage = "2", path = artifact_paths$stage2, sha256 = stage2_sha),
                    list(stage = "3A", path = artifact_paths$stage3a, sha256 = stage3a_sha)),
      supporting_records = c(list(artifact_manifest = "artifact_manifest.csv", formula_audit = "source/outputs/validation/formula_audit.csv", qualification_report = "qualification-report.md"),
        if (is.null(provenance_reconciliation_path)) list() else list(source_provenance_reconciliation = provenance_reconciliation_path)),
      supporting_record_checksums = c(list(artifact_manifest_sha256 = fixture_hash(artifact_manifest_path), formula_audit_sha256 = formula_sha, qualification_report_sha256 = fixture_hash(qualification_report)),
        if (is.null(provenance_reconciliation_path)) list() else list(source_provenance_reconciliation_sha256 = fixture_hash(provenance_reconciliation_path))),
      qualification_evidence = list(fit_health_pass = 4L, fit_health_fail = 0L, extraction_pass = 3L, extraction_fail = 0L,
        validation_pass = 3L, validation_warning = 0L, validation_fail = 0L, tier1_holdouts = 10L, tier2_holdouts = 10L,
        holdout_identity_match_with_c1 = TRUE, tier1_area_weighted_pb_auc = 0.9, tier1_area_weighted_cbi = 0.9,
        tier2_mae = 1, tier2_rmse = 1, tier2_pearson = 0.9, tier2_spearman = 0.9, tier2_calibration_mean_ratio = 1,
        tier2_mae_difference_refreshed_minus_c1 = 0, tier2_mae_difference_interpretation = "fixture",
        limitations = c("fixture limitation"), fit_stderr_inla_experimental_vb_warning_occurrences = 0L,
        fit_stderr_unclassified_warning_lines = 0L, rasters_generated = FALSE, posterior_sampling_performed = FALSE)
    ),
    canonical_tests = list(summary_path = "canonical-tests.tsv", summary_sha256 = fixture_hash(canonical_path))
  )
  jsonlite::write_json(qualification, qualification_path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")

  execution_config_path <- file.path(root, "production.yml")
  yaml::write_yaml(list(project = list(output_root = output_root), input = list(observations = observation_path),
    temporal = list(start_epiweek = "2024-W01", end_rule = "last_complete_epiweek")), execution_config_path)
  request_path <- file.path(root, "refresh_request.yml")
  request <- list(
    schema_version = 1L, request_id = "fixture-w44", operation = list(mode = "adopt", requested_stages = "postfit", dispatch_authorized = FALSE),
    configuration = list(role = "candidate_execution", path = execution_config_path, sha256 = fixture_hash(execution_config_path),
      identity_id = "ORIGINAL_REFRESH_W44_2026", identity_path = identity_path, identity_sha256 = fixture_hash(identity_path)),
    model = list(candidate_id = "ORIGINAL_REFRESH_W44_2026", production_id = "ORIGINAL_W44_2026_PRODUCTION",
      specification_id = "original_joint_inla_v1", formula_identity = "original_joint_inla_v1"),
    data = list(release_id = "2026-11-13", availability_endpoint = "2024-W03", observations_path = observation_path, observations_sha256 = fixture_hash(observation_path)),
    environmental_data = list(availability_endpoint = "2024-W03", identity_path = environmental_path, identity_sha256 = fixture_hash(environmental_path)),
    covariate_registry = list(identifier = "manifest-free-original", sha256 = NULL, mode = "manifest_free_original", path = NULL),
    analysis = list(start_epiweek = "2024-W01", requested_endpoint = "2024-W03"),
    output = list(root = output_root),
    qualification = list(status = "ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS", required_gates = c("adoption", "postfit"), evidence_manifest = qualification_path, evidence_manifest_sha256 = fixture_hash(qualification_path)),
    reporting = list(temperature_mask_threshold_c = 16.0, rpi_calibration = "same_week_observation_pairs", rpi_quantile = 0.10,
      required_products = c("structural_potential_abundance_temp_masked", "rpi_dynamic_threshold", "rpi")),
    resume = NULL,
    adoption = list(artifact_manifest = artifact_manifest_path, artifact_manifest_sha256 = fixture_hash(artifact_manifest_path),
      source_fit_job_id = "12345", fit_sha256 = fit_sha, fit_source_commit = commit, report_generation_commit = report_commit,
      provenance_reconciliation = if (is.null(provenance_reconciliation_path)) NULL else list(path = provenance_reconciliation_path, sha256 = fixture_hash(provenance_reconciliation_path)),
      lineage = list(stage1_to_stage2_sha256 = stage1_sha, stage2_to_stage3a_sha256 = stage2_sha, stage3a_to_fit_sha256 = stage3a_sha))
  )
  yaml::write_yaml(request, request_path)
  list(root = root, source_root = source_root, request_path = request_path,
       request = production_release_read_request(request_path, root), inventory_path = artifact_manifest_path,
       artifact_paths = artifact_paths, qualification_path = qualification_path, execution_config_path = execution_config_path,
       observation_path = observation_path, output_root = output_root)
}

make_release_fixture <- function(root, production_id) {
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  write_path <- function(name, text = "release fixture\n") fixture_write(file.path(root, name), text)
  config <- write_path("production.yml", "candidate configuration\n")
  identity <- write_path("identity.yml", "model identity\n")
  evidence <- write_path("qualification.yml", "decision: QUALIFIED\n")
  observation_source <- write_path("observations.csv", "date,lon,lat\n2026-01-01,-90,30\n")
  environmental_identity <- write_path("environmental-identity.yml", "availability_endpoint: 2026-W01\n")
  request_archive <- write_path("refresh_request.yml", "schema_version: 1\nrequest_id: fixture\n")
  fit <- write_path("fit.rds", "fit artifact\n")
  stage1 <- write_path("stage1.rds", "stage1\n")
  stage2 <- write_path("stage2.rds", "stage2\n")
  stage3a <- write_path("stage3a.rds", "stage3a\n")
  run_manifest <- write_path("run_manifest.yml", "run_id: fixture\n")
  report_root <- file.path(root, "reporting")
  product_names <- c("structural_potential_abundance_temp_masked", "rpi_dynamic_threshold", "rpi")
  product_paths <- file.path(report_root, "objects", paste0(product_names, ".csv"))
  for (i in seq_along(product_paths)) fixture_write(product_paths[[i]], paste0("product ", i, "\n"))
  product_manifest_path <- file.path(report_root, "metadata", "manifest_fixture.csv")
  dir.create(dirname(product_manifest_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data.frame(
    logical_product_name = product_names,
    path = file.path("objects", paste0(product_names, ".csv")),
    checksum_sha256 = vapply(product_paths, fixture_hash, character(1L)),
    bytes = vapply(product_paths, function(path) as.numeric(file.info(path)$size), numeric(1L)),
    temperature_variable = c("mintemp", NA, NA), temperature_threshold_celsius = c(16, NA, NA),
    rpi_threshold_calibration = c(NA, NA, "same-week observation-paired dynamic threshold"),
    stringsAsFactors = FALSE), product_manifest_path, row.names = FALSE, na = "")
  product_manifest <- fixture_hash(product_manifest_path)
  manifest <- list(
    schema_version = 1L, status = "READY_FOR_REVIEW", candidate_id = paste0("candidate-", production_id), production_id = production_id,
    specification_id = "original_joint_inla_v1", formula_identity = "original_joint_inla_v1",
    configuration = list(role = "candidate_execution", path = config, sha256 = fixture_hash(config), identity_path = identity, identity_sha256 = fixture_hash(identity)),
    request_archive = list(path = request_archive, sha256 = fixture_hash(request_archive)),
    data = list(observations_path = observation_source, observations_sha256 = fixture_hash(observation_source)),
    environmental_data = list(identity_path = environmental_identity, identity_sha256 = fixture_hash(environmental_identity)),
    covariate_registry = list(identifier = "original_joint_inla_v1", mode = "manifest_free_original", path = NULL, sha256 = NULL),
    qualification = list(scientific_status = "QUALIFIED", evidence_manifest = evidence, evidence_manifest_sha256 = fixture_hash(evidence)),
    gates = list(prepare = "PASS", fit = "PASS", postfit = "PASS"),
    upstream_artifacts = list(stage1 = list(path = stage1, bytes = file.info(stage1)$size, sha256 = fixture_hash(stage1)),
      stage2 = list(path = stage2, bytes = file.info(stage2)$size, sha256 = fixture_hash(stage2)),
      stage3a = list(path = stage3a, bytes = file.info(stage3a)$size, sha256 = fixture_hash(stage3a))),
    fit = list(path = fit, bytes = file.info(fit)$size, sha256 = fixture_hash(fit)),
    run_manifest = list(path = run_manifest, sha256 = fixture_hash(run_manifest)),
    products = list(manifest_path = product_manifest_path, manifest_sha256 = product_manifest),
    reporting = list(temperature_mask_threshold_c = 16, rpi_calibration = "same_week_observation_pairs", required_products = product_names)
  )
  manifest_path <- file.path(root, "model-release.yml")
  yaml::write_yaml(manifest, manifest_path)
  list(manifest_path = manifest_path, config = config, production_id = production_id, product_paths = product_paths)
}

test_that("versioned refresh request modes are strict and full runs preserve Prepare-Fit-Post-fit order", {
  fixture <- make_adoption_fixture()
  request <- fixture$request
  expect_identical(production_release_validate_request(request), "adopt")

  full <- request
  full$operation$mode <- "full"
  full$operation$requested_stages <- c("prepare", "fit", "postfit")
  full["adoption"] <- list(NULL)
  full["resume"] <- list(NULL)
  expect_identical(production_release_validate_request(full), "full")
  full_plan <- production_release_plan(full)
  expect_identical(full_plan$scheduler_stages, c("prepare", "fit", "postfit"))
  expect_identical(full_plan$dependencies[["fit"]], "afterok:<prepare-job-id>")
  expect_identical(full_plan$dependencies[["postfit"]], "afterok:<fit-job-id>")

  invalid <- request
  invalid$operation$requested_stages <- c("fit", "postfit")
  expect_error(production_release_validate_request(invalid), "may not request Prepare or Fit")
  invalid <- request
  invalid$operation$mode <- "ADOPT"
  expect_error(production_release_validate_request(invalid), "operation.mode")
  invalid <- request
  invalid$analysis$requested_endpoint <- "2024-W04"
  expect_error(production_release_validate_request(invalid), "exceeds a declared observation or environmental availability endpoint")
})

test_that("an explicit requested horizon remains fixed when the source has later dates", {
  observations <- data.frame(date = c("2026-11-01", "2026-11-13"), stringsAsFactors = FALSE)
  horizon <- production_orchestration_resolve_requested_horizon(observations, "2022-W01", "2026-W44")
  expect_identical(horizon$resolved_final_complete_epiweek, "2026-W44")
  expect_identical(horizon$resolved_final_complete_week_end, "2026-11-01")
  expect_identical(horizon$raw_max_observation_date, "2026-11-13")
  expect_identical(horizon$observations_excluded_after_final_complete_week, 1L)
})

test_that("resume starts at each first incomplete stage and reuses accepted upstream stages", {
  fixture <- make_adoption_fixture()
  request <- fixture$request
  request$operation$mode <- "resume"
  request$operation$requested_stages <- c("prepare", "fit", "postfit")
  request["adoption"] <- list(NULL)
  request$resume <- list(run_id = "existing-run", manifest_path = "run_manifest.yml", manifest_sha256 = paste(rep("c", 64L), collapse = ""))
  expect_identical(production_release_validate_request(request), "resume")
  expect_identical(production_release_plan(request, list())$scheduler_stages, c("prepare", "fit", "postfit"))
  expect_identical(production_release_plan(request, list(prepare = list(status = "PASS")))$scheduler_stages, c("fit", "postfit"))
  expect_identical(production_release_plan(request, list(prepare = list(status = "PASS"), fit = list(status = "WARNING")))$scheduler_stages, "postfit")
  expect_length(production_release_plan(request, list(prepare = list(status = "PASS"), fit = list(status = "PASS"), postfit = list(status = "PASS")))$scheduler_stages, 0L)
})

test_that("adoption validates checksums, formula, stage lineage, audits, and metadata without loading a fit", {
  fixture <- make_adoption_fixture()
  result <- production_release_validate_adoption(fixture$request, fixture$root, verify_files = TRUE)
  expect_identical(result$outcome, "PASS_WITH_WARNINGS")
  expect_identical(result$fit_provenance$launch_commit, fixture$request$adoption$fit_source_commit)
  expect_true(all(c("stage1", "stage2", "stage3a", "fit", "fit_metadata") %in% names(result$artifact_inputs)))

  wrong_fit <- fixture$request
  wrong_fit$adoption$fit_sha256 <- paste(rep("0", 64L), collapse = "")
  expect_error(production_release_validate_adoption(wrong_fit, fixture$root), "Fit checksum or historical Slurm job identity")

  wrong_upstream <- fixture$request
  wrong_upstream$adoption$lineage$stage2_to_stage3a_sha256 <- paste(rep("1", 64L), collapse = "")
  expect_error(production_release_validate_adoption(wrong_upstream, fixture$root), "Declared direct stage lineage")

  wrong_formula <- fixture$request
  wrong_formula$model$formula_identity <- "different_formula"
  expect_error(production_release_validate_adoption(wrong_formula, fixture$root), "Formula identity")

  wrong_qualification <- fixture$request
  wrong_qualification$qualification$status <- "APPROVED"
  expect_error(production_release_validate_adoption(wrong_qualification, fixture$root), "qualification status does not match")

  wrong_evidence_checksum <- fixture$request
  wrong_evidence_checksum$qualification$evidence_manifest_sha256 <- paste(rep("0", 64L), collapse = "")
  expect_error(production_release_validate_adoption(wrong_evidence_checksum, fixture$root), "Qualification manifest is missing or has a different SHA-256")

  file.remove(fixture$artifact_paths$stage3a)
  expect_error(production_release_validate_adoption(fixture$request, fixture$root), "does not exist|missing")
})

test_that("fit metadata commit mismatch blocks adoption even when Slurm completed", {
  fixture <- make_adoption_fixture(metadata_commit = paste(rep("d", 40L), collapse = ""))
  expect_error(production_release_validate_adoption(fixture$request, fixture$root), "Fit source commit mismatch")
})

test_that("a checksummed non-executable provenance reconciliation preserves both fit commits", {
  metadata_commit <- paste(rep("d", 40L), collapse = "")
  fixture <- make_adoption_fixture(metadata_commit = metadata_commit, include_provenance_reconciliation = TRUE)
  result <- production_release_validate_adoption(fixture$request, fixture$root, verify_files = TRUE)
  expect_identical(result$fit_provenance$launch_commit, fixture$request$adoption$fit_source_commit)
  expect_identical(result$fit_provenance$metadata_runtime_commit, metadata_commit)
  expect_identical(result$fit_provenance$provenance_reconciliation$status, "RECONCILED_NON_EXECUTABLE_METADATA_DRIFT")
  expect_false(result$fit_provenance$provenance_reconciliation$production_activation_authorized %||% FALSE)
  expect_error(production_release_validate_source_reconciliation(
    fixture$request$adoption$provenance_reconciliation, fixture$root, "12345",
    fixture$request$adoption$fit_source_commit, metadata_commit,
    "2024-01-01T00:00:01Z", "2024-01-01T00:01:00Z"),
    "audit timestamps do not match the fit metadata")

  inconsistent_evidence <- jsonlite::fromJSON(fixture$qualification_path, simplifyVector = FALSE)
  inconsistent_evidence$candidate_model$repository$metadata_runtime_commit <- paste(rep("e", 40L), collapse = "")
  jsonlite::write_json(inconsistent_evidence, fixture$qualification_path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  inconsistent_request <- fixture$request
  inconsistent_request$qualification$evidence_manifest_sha256 <- fixture_hash(fixture$qualification_path)
  expect_error(production_release_validate_adoption(inconsistent_request, fixture$root),
    "metadata runtime commit does not match fit metadata")
})

test_that("versioned qualification JSON is strict, complete, checksummed, and preserves the historical record", {
  fixture <- make_adoption_fixture()
  evidence <- production_release_read_qualification_manifest(fixture$qualification_path, fixture$root)
  expect_identical(as.integer(evidence$evidence_schema_version), 2L)
  expect_identical(evidence$candidate_model$qualification_status, "ORIGINAL_REFRESH_W44_QUALIFIED_WITH_LIMITATIONS")

  duplicate_path <- fixture_write(file.path(fixture$root, "duplicate-keys.json"),
    c("{", "  \"candidate_model\": {", "    \"qualification_status\": \"QUALIFIED\",",
      "    \"qualification_status\": \"BLOCKED\"", "  }", "}"))
  expect_error(production_release_read_qualification_manifest(duplicate_path, fixture$root), "Duplicate map key")

  missing_status <- jsonlite::fromJSON(fixture$qualification_path, simplifyVector = FALSE)
  missing_status$candidate_model$qualification_status <- NULL
  missing_status_path <- file.path(fixture$root, "missing-status.json")
  jsonlite::write_json(missing_status, missing_status_path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  expect_error(production_release_read_qualification_manifest(missing_status_path, fixture$root), "qualification_status is missing")

  missing_evidence <- jsonlite::fromJSON(fixture$qualification_path, simplifyVector = FALSE)
  missing_evidence$candidate_model$qualification_evidence <- NULL
  missing_evidence_path <- file.path(fixture$root, "missing-evidence.json")
  jsonlite::write_json(missing_evidence, missing_evidence_path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  expect_error(production_release_read_qualification_manifest(missing_evidence_path, fixture$root), "qualification_evidence is missing")

  historical_path <- file.path(repo_root, "docs", "archive", "original-refresh-w44-2026", "original_refresh_w44_2026_production_manifest.json")
  expect_identical(fixture_hash(historical_path), "eed2d7cda3d8aa562f545b9d9e423e8d3495481d4e2f39626cd92a3da17c9786")
})

test_that("legacy fit metadata may omit Stage 1 path when the checked Stage 2 config supplies that edge", {
  fixture <- make_adoption_fixture(record_stage1_metadata = FALSE)
  result <- production_release_validate_adoption(fixture$request, fixture$root, verify_files = TRUE)
  expect_false(result$fit_provenance$stage1_metadata_reference_recorded)
  expect_identical(result$fit_provenance$stage1_link_source, "verified Stage 2 configuration input and Stage 1 audit")
  expect_match(result$limitations[[2L]], "omits the Stage 1 path")
})

test_that("production configuration compatibility reports output mismatches", {
  fixture <- make_adoption_fixture()
  compatible <- production_release_configuration_compatibility(fixture$request, fixture$root)
  expect_true(compatible$matches)
  mismatched <- fixture$request
  mismatched$output$root <- file.path(fixture$root, "different-output")
  expect_false(production_release_configuration_compatibility(mismatched, fixture$root)$matches)
})

test_that("adoption plans are post-fit only and never depend on the historical fit job", {
  fixture <- make_adoption_fixture()
  plan <- production_release_plan(fixture$request)
  expect_identical(plan$scheduler_stages, "postfit")
  expect_identical(plan$dependencies[["postfit"]], "none")
  expect_false(plan$historical_fit_is_scheduler_dependency)
  expect_identical(plan$historical_fit_job_id, "12345")
  expect_silent(production_release_assert_adoption_plan(plan))
  bad_plan <- plan
  bad_plan$scheduler_stages <- c("fit", "postfit")
  expect_error(production_release_assert_adoption_plan(bad_plan), "prohibited Prepare or Fit")
  bad_plan <- plan
  bad_plan$dependencies[["postfit"]] <- "afterok:12345"
  expect_error(production_release_assert_adoption_plan(bad_plan), "Historical fit job ID")
})

test_that("registry copy is checksum verified, immutable, idempotent, and preserves source artifacts", {
  root <- tempfile(pattern = "model_registry_fixture_")
  dir.create(root)
  source <- fixture_write(file.path(root, "source", "fit.rds"), "historical fit\n")
  source_sha <- fixture_hash(source)
  artifact <- list(fit = list(path = source, sha256 = source_sha, bytes = file.info(source)$size))
  target <- file.path(root, "registry", "model-v1")
  first <- production_release_copy_bundle(artifact, target)
  expect_false(first$reused)
  expect_identical(fixture_hash(source), source_sha)
  expect_identical(fixture_hash(first$artifacts$fit$path), source_sha)
  second <- production_release_copy_bundle(artifact, target)
  expect_true(second$reused)
  expect_identical(second$manifest_sha256, first$manifest_sha256)

  changed <- fixture_write(file.path(root, "source", "different.rds"), "different fit\n")
  changed_bundle <- list(fit = list(path = changed, sha256 = fixture_hash(changed), bytes = file.info(changed)$size))
  expect_error(production_release_copy_bundle(changed_bundle, target), "differs for artifact")
  partial_target <- file.path(root, "registry", "partial")
  partial <- list(valid = artifact$fit, missing = list(path = file.path(root, "missing.rds"), sha256 = source_sha, bytes = 1))
  expect_error(suppressWarnings(production_release_copy_bundle(partial, partial_target)), "Failed to stage model artifact")
  expect_false(dir.exists(partial_target))
  expect_identical(fixture_hash(source), source_sha)
})

test_that("release activation and rollback are atomic, compare-and-swap guarded, and append audited history", {
  skip_on_os("windows")
  root <- tempfile(pattern = "model_activation_fixture_")
  dir.create(root)
  old_release <- make_release_fixture(file.path(root, "old"), "old-model")
  new_release <- make_release_fixture(file.path(root, "new"), "new-model")
  active_path <- file.path(root, "secure-config", "active-release.yml")
  dir.create(dirname(active_path), recursive = TRUE)
  initial <- list(schema_version = 1L, generation = 1L, production_id = "old-model", candidate_id = "candidate-old-model",
    manifest_path = old_release$manifest_path, manifest_sha256 = fixture_hash(old_release$manifest_path),
    configuration_path = old_release$config, configuration_sha256 = fixture_hash(old_release$config), event_id = "bootstrap")
  production_release_atomic_yaml(initial, active_path, replace = FALSE)
  initial_state <- yaml::read_yaml(active_path)
  initial_sha <- fixture_hash(active_path)
  events <- file.path(root, "activation-events")

  activated <- production_release_activate(active_path, new_release$manifest_path, initial_state$generation, initial_sha, events)
  expect_identical(activated$production_id, "new-model")
  activation_event <- activated$event_path
  activation <- yaml::read_yaml(activation_event)
  expect_identical(activation$previous_state$production_id, "old-model")
  expect_identical(production_release_verify_active(active_path)$status, "PASS")

  active_state <- yaml::read_yaml(active_path)
  active_sha <- fixture_hash(active_path)
  rolled_back <- production_release_rollback(active_path, activation_event, active_state$generation, active_sha, events)
  expect_identical(rolled_back$production_id, "old-model")
  expect_identical(yaml::read_yaml(active_path)$generation, 3L)
  expect_identical(yaml::read_yaml(activation_event)$action, "ACTIVATED")
  expect_true(length(list.files(events, pattern = "^rollback-.*\\.yml$")) == 1L)
  expect_true(file.exists(new_release$product_paths[[1L]]))
})

test_that("activation verification failure restores the prior pointer and records failure", {
  skip_on_os("windows")
  root <- tempfile(pattern = "model_activation_failure_fixture_")
  old_release <- make_release_fixture(file.path(root, "old"), "old-model")
  new_release <- make_release_fixture(file.path(root, "new"), "new-model")
  active_path <- file.path(root, "secure-config", "active-release.yml")
  dir.create(dirname(active_path), recursive = TRUE)
  old <- list(schema_version = 1L, generation = 4L, production_id = "old-model", candidate_id = "candidate-old-model",
    manifest_path = old_release$manifest_path, manifest_sha256 = fixture_hash(old_release$manifest_path),
    configuration_path = old_release$config, configuration_sha256 = fixture_hash(old_release$config), event_id = "bootstrap")
  production_release_atomic_yaml(old, active_path, replace = FALSE)
  events <- file.path(root, "events")
  original_verifier <- production_release_verify_active
  assign("production_release_verify_active", function(...) stop("FORCED_VERIFIER_FAILURE", call. = FALSE), envir = .GlobalEnv)
  on.exit(assign("production_release_verify_active", original_verifier, envir = .GlobalEnv), add = TRUE)
  expect_error(production_release_activate(active_path, new_release$manifest_path, 4L, fixture_hash(active_path), events), "prior active release was restored")
  restored <- yaml::read_yaml(active_path)
  expect_identical(restored$production_id, "old-model")
  expect_identical(as.integer(restored$generation), 4L)
  failure_events <- list.files(events, pattern = "^activate-.*\\.yml$", full.names = TRUE)
  expect_length(failure_events, 1L)
  expect_identical(yaml::read_yaml(failure_events[[1L]])$action, "ACTIVATION_FAILED_ROLLED_BACK")
})

test_that("incomplete releases cannot activate", {
  skip_on_os("windows")
  root <- tempfile(pattern = "model_activation_incomplete_fixture_")
  old_release <- make_release_fixture(file.path(root, "old"), "old-model")
  bad_release <- make_release_fixture(file.path(root, "bad"), "bad-model")
  bad_manifest <- yaml::read_yaml(bad_release$manifest_path)
  bad_manifest$gates$postfit <- "FAIL"
  yaml::write_yaml(bad_manifest, bad_release$manifest_path)
  active_path <- file.path(root, "secure-config", "active-release.yml")
  dir.create(dirname(active_path), recursive = TRUE)
  old <- list(schema_version = 1L, generation = 1L, production_id = "old-model", candidate_id = "candidate-old-model",
    manifest_path = old_release$manifest_path, manifest_sha256 = fixture_hash(old_release$manifest_path),
    configuration_path = old_release$config, configuration_sha256 = fixture_hash(old_release$config), event_id = "bootstrap")
  production_release_atomic_yaml(old, active_path, replace = FALSE)
  expect_error(production_release_activate(active_path, bad_release$manifest_path, 1L, fixture_hash(active_path), file.path(root, "events")), "Post-fit gate")
  expect_identical(yaml::read_yaml(active_path)$production_id, "old-model")
})
