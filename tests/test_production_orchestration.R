suppressPackageStartupMessages(library(testthat))

repo_candidates <- unique(c(getwd(), normalizePath(file.path(getwd(), ".."), mustWork = FALSE)))
repo_root <- repo_candidates[file.exists(file.path(repo_candidates, "R", "production_orchestration.R"))][[1L]]
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_validation_gates.R"), local = .GlobalEnv)

make_stage2_fixture <- function(path, quarter_groups = 8L, noncontiguous = FALSE) {
  n_weeks <- quarter_groups * 2L
  weeks <- data.frame(
    epiyear = rep(2024L, n_weeks), epiweek = seq_len(n_weeks), time_index = seq_len(n_weeks),
    timestep_2wk = rep(seq_len(ceiling(n_weeks / 2)), each = 2L)[seq_len(n_weeks)],
    quarter_index = rep(seq_len(quarter_groups), each = 2L),
    sixmo_index = rep(seq_len(max(1L, ceiling(quarter_groups / 2))), length.out = n_weeks),
    year_index = 1L, stringsAsFactors = FALSE
  )
  if (noncontiguous) weeks$quarter_index[weeks$quarter_index == quarter_groups] <- quarter_groups + 1L
  grid <- do.call(rbind, lapply(seq_len(n_weeks), function(i) data.frame(
    epiyear = weeks$epiyear[[i]], epiweek = weeks$epiweek[[i]], time_index = i,
    cell_id = 1:2, x = c(0, 1), y = c(0, 1), quarter_index = weeks$quarter_index[[i]],
    stringsAsFactors = FALSE
  )))
  saveRDS(list(prediction_grid = grid, temporal_mapping = weeks), path)
  invisible(path)
}

with_chime_execution_id <- function(value, code) {
  previous <- Sys.getenv("CHIME_EXECUTION_ID", unset = NA_character_)
  on.exit({
    if (is.na(previous)) Sys.unsetenv("CHIME_EXECUTION_ID") else Sys.setenv(CHIME_EXECUTION_ID = previous)
  }, add = TRUE)
  if (is.null(value)) Sys.unsetenv("CHIME_EXECUTION_ID") else Sys.setenv(CHIME_EXECUTION_ID = value)
  force(code)
}

make_production_contract_fixture <- function(repo_root) {
  root <- file.path(tempdir(), paste0("production_orchestration_chime_", as.integer(Sys.time()), "_", sample.int(1000000L, 1L)))
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  observations_path <- file.path(root, "observations.csv")
  utils::write.csv(data.frame(
    date = as.character(as.Date(c("2024-01-01", "2024-01-14"))),
    lon = c(-90, -91), lat = c(30, 31)
  ), observations_path, row.names = FALSE)
  config_path <- file.path(root, "production.yml")
  yaml::write_yaml(list(
    project = list(output_root = file.path(root, "runs")),
    input = list(observations = observations_path),
    temporal = list(start_epiweek = "2024-W01", end_rule = "last_complete_epiweek"),
    stage_configs = list(
      preprocessing = file.path(repo_root, "config", "preprocessing.example.yml"),
      joint_model = file.path(repo_root, "config", "joint_model.example.yml"),
      joint_inla = file.path(repo_root, "config", "joint_inla.example.yml"),
      fit = file.path(repo_root, "config", "joint_inla_fit.example.yml")
    )
  ), config_path)
  list(root = root, config_path = config_path)
}

test_that("horizon resolves the last complete epiweek from current observations", {
  observations <- data.frame(date = as.character(as.Date(c("2024-01-01", "2024-01-14", "2024-01-22"))))
  horizon <- production_orchestration_resolve_horizon(observations, "2024-W01")
  expect_identical(horizon$resolved_final_complete_epiweek, "2024-W03")
  expect_identical(horizon$modeled_weeks, 3L)
  expect_identical(horizon$observations_excluded_after_final_complete_week, 1L)
})

test_that("dynamic dimension contract accepts historical 8-group and full-horizon 11-group structures", {
  for (groups in c(8L, 11L)) {
    path <- file.path(tempdir(), paste0("stage2_", groups, ".rds"))
    make_stage2_fixture(path, groups)
    contract <- production_orchestration_dimension_contract(path)
    expect_identical(contract$groups$quarter_groups, groups)
    expect_identical(contract$groups$levels$quarter, seq_len(groups))
    expect_identical(contract$prediction_rows, contract$modeled_weeks * contract$supported_cells)
  }
})

test_that("dynamic dimension contract rejects noncontiguous group levels", {
  path <- file.path(tempdir(), "stage2_noncontiguous.rds")
  make_stage2_fixture(path, 11L, noncontiguous = TRUE)
  expect_error(production_orchestration_dimension_contract(path), "not positive and contiguous")
})

test_that("production config generation preserves source residency and writes run-specific paths", {
  root <- file.path(tempdir(), "production_orchestration_fixture")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  observations_path <- file.path(root, "observations.csv")
  utils::write.csv(data.frame(date = as.character(as.Date(c("2024-01-01", "2024-01-14"))), lon = c(-90, -91), lat = c(30, 31)), observations_path, row.names = FALSE)
  config_path <- file.path(root, "production.yml")
  yaml::write_yaml(list(
    project = list(output_root = file.path(root, "runs")),
    input = list(observations = observations_path),
    temporal = list(start_epiweek = "2024-W01", end_rule = "last_complete_epiweek"),
    stage_configs = list(
      preprocessing = file.path(repo_root, "config", "preprocessing.example.yml"),
      joint_model = file.path(repo_root, "config", "joint_model.example.yml"),
      joint_inla = file.path(repo_root, "config", "joint_inla.example.yml"),
      fit = file.path(repo_root, "config", "joint_inla_fit.example.yml")
    )
  ), config_path)
  contract <- production_orchestration_contract(config_path, repo_root, run_id = "test_run")
  dir.create(contract$paths$stage1, recursive = TRUE, showWarnings = FALSE)
  contract <- production_orchestration_write_stage_configs(contract)
  generated <- lapply(contract$generated_configs, yaml::read_yaml)
  expect_identical(normalizePath(generated$preprocessing$inputs$observations), normalizePath(observations_path))
  expect_identical(normalizePath(generated$preprocessing$project$output_directory), normalizePath(contract$paths$stage1, mustWork = FALSE))
  expect_true(all(vapply(generated, function(cfg) !any(grepl("2024-01-01", capture.output(str(cfg))), na.rm = TRUE), logical(1L))))
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  dry_run <- system2(rscript, c("--vanilla", file.path(repo_root, "scripts", "run_pipeline.R"), "--mode", "dry-run", "--config", config_path), stdout = TRUE, stderr = TRUE)
  expect_true(any(grepl("DRY RUN", dry_run, fixed = TRUE)))
  expect_true(any(grepl("dependency=afterok:<prepare-job-id>", dry_run, fixed = TRUE)))
  expect_false(file.exists(file.path(root, "runs", "test_run", "observations.csv")))
})

test_that("CHIME execution correlation is optional and persists in the run manifest", {
  fixture <- make_production_contract_fixture(repo_root)
  uncorrelated <- with_chime_execution_id(NULL, production_orchestration_contract(fixture$config_path, repo_root, run_id = "uncorrelated"))
  expect_true(is.na(uncorrelated$chime_execution_id))
  dir.create(uncorrelated$paths$metadata, recursive = TRUE, showWarnings = FALSE)
  production_orchestration_write_manifest(uncorrelated)
  uncorrelated_manifest <- production_orchestration_read_manifest(file.path(uncorrelated$paths$metadata, "run_manifest.yml"))
  expect_true(is.null(uncorrelated_manifest$chime_execution_id) || is.na(uncorrelated_manifest$chime_execution_id))

  correlated <- with_chime_execution_id("  test-execution-123  ", production_orchestration_contract(fixture$config_path, repo_root, run_id = "correlated"))
  expect_identical(correlated$chime_execution_id, "test-execution-123")
  dir.create(correlated$paths$metadata, recursive = TRUE, showWarnings = FALSE)
  production_orchestration_write_manifest(correlated)
  correlated_manifest <- production_orchestration_read_manifest(file.path(correlated$paths$metadata, "run_manifest.yml"))
  expect_identical(correlated_manifest$chime_execution_id, "test-execution-123")
})

test_that("CHIME execution correlation survives rehydration and handles resume conflicts", {
  preserved <- production_orchestration_rehydrate_chime_execution_id(list(chime_execution_id = "stored-id"), NA_character_)
  expect_identical(preserved$contract$chime_execution_id, "stored-id")
  expect_false(preserved$bound)

  same <- production_orchestration_rehydrate_chime_execution_id(list(chime_execution_id = "stored-id"), " stored-id ")
  expect_identical(same$contract$chime_execution_id, "stored-id")
  expect_false(same$bound)

  added <- production_orchestration_rehydrate_chime_execution_id(list(), " new-id ")
  expect_identical(added$contract$chime_execution_id, "new-id")
  expect_true(added$bound)

  expect_error(
    production_orchestration_rehydrate_chime_execution_id(list(chime_execution_id = "stored-id"), "different-id"),
    "CHIME execution ID conflict on resume"
  )
})

test_that("resume requires the recorded repository commit to match the current checkout", {
  current <- production_orchestration_git_commit(repo_root)
  expect_true(nzchar(current))
  expect_silent(production_orchestration_assert_resume_repository(list(repository = list(git_commit = current)), repo_root))
  expect_error(
    production_orchestration_assert_resume_repository(list(repository = list(git_commit = paste0(current, "-different"))), repo_root),
    "Resume repository SHA does not match"
  )
  expect_error(
    production_orchestration_assert_resume_repository(list(repository = list(git_commit = NA_character_)), repo_root),
    "does not record a repository git commit"
  )
})

test_that("production summary includes the persisted CHIME execution ID", {
  fixture <- make_production_contract_fixture(repo_root)
  contract <- with_chime_execution_id("test-execution-123", production_orchestration_contract(fixture$config_path, repo_root, run_id = "summary"))
  contract$dynamic_dimensions <- list(modeled_weeks = 2L, supported_cells = 2L, prediction_rows = 4L)
  dir.create(contract$paths$metadata, recursive = TRUE, showWarnings = FALSE)
  summary_path <- production_orchestration_write_final_summary(contract)
  summary <- yaml::read_yaml(summary_path)
  expect_identical(summary$chime_execution_id, "test-execution-123")
})

test_that("historical manifests without CHIME execution correlation remain readable", {
  path <- file.path(tempdir(), paste0("legacy_manifest_", sample.int(1000000L, 1L), ".yml"))
  yaml::write_yaml(list(run_id = "legacy-run", overall_status = "PASS"), path)
  manifest <- production_orchestration_read_manifest(path)
  expect_identical(manifest$run_id, "legacy-run")
  expect_true(is.null(manifest$chime_execution_id))
  expect_true(is.na(production_orchestration_resolve_chime_execution_id(manifest$chime_execution_id, NA_character_)$value))
})

test_that("CHIME execution correlation does not alter scientific or operational contract fields", {
  fixture <- make_production_contract_fixture(repo_root)
  baseline <- with_chime_execution_id(NULL, production_orchestration_contract(fixture$config_path, repo_root, run_id = "invariance"))
  correlated <- with_chime_execution_id("test-execution-123", production_orchestration_contract(fixture$config_path, repo_root, run_id = "invariance"))
  for (field in c("run_id", "repository", "config", "input", "horizon", "scheduler", "paths")) {
    expect_identical(correlated[[field]], baseline[[field]])
  }
})

test_that("resume selection skips passed stages and supports explicit stage ranges", {
  statuses <- list(prepare = list(status = "PASS"), fit = list(status = "FAIL"))
  expect_identical(production_orchestration_select_resume_stage(statuses, through = "postfit"), "fit")
  expect_identical(production_orchestration_select_resume_stage(list(prepare = list(status = "PASS"), fit = list(status = "PASS"), postfit = list(status = "PASS")), through = "postfit"), NULL)
  expect_identical(production_orchestration_select_resume_stage(statuses, from = "postfit", through = "postfit"), "postfit")
})

test_that("Slurm wrap commands are protected as one argument", {
  command <- production_orchestration_command_text("Rscript", "scripts/run_pipeline.R", c("--mode", "stage", "--stage", "prepare"))
  wrapped <- production_orchestration_sbatch_wrap_arg(command)
  expect_match(wrapped, "^--wrap=")
  expect_gt(nchar(wrapped), nchar(paste0("--wrap=", command)))
  expect_true(grepl("^--wrap='", wrapped) || grepl('^--wrap="', wrapped))
})

test_that("compact gate results use stable schema and failure semantics", {
  pass <- production_gate_row("fit", "fit_ok", "BLOCKING", "PASS", "fit completed")
  warning <- production_gate_row("fit", "dic", "WARNING", "WARN", "historical diagnostic changed")
  provenance <- production_gate_row("fit", "theta_source", "PROVENANCE", "INFO", "previous theta recorded")
  result <- production_gate_finalize(rbind(pass, warning, provenance))
  expect_identical(result$outcome, "PASS_WITH_WARNINGS")
  expect_identical(names(result$audit), c("gate", "check", "severity", "status", "message", "artifact", "expected", "observed"))
  expect_equal(result$warning_count, 1L)
  expect_identical(production_gate_finalize(pass)$outcome, "PASS")
  expect_identical(production_gate_finalize(production_gate_row("fit", "fit_ok", "BLOCKING", "FAIL"))$outcome, "FAIL")
})

test_that("historical diagnostics and dynamic provenance do not fail production", {
  rows <- rbind(
    production_gate_row("postfit", "historical_rpi", "WARNING", "WARN", "threshold differs from old report"),
    production_gate_row("postfit", "rpi_threshold", "BLOCKING", "PASS", "current threshold reproduces"),
    production_gate_row("postfit", "artifact_sha", "PROVENANCE", "INFO", "sha recorded")
  )
  expect_identical(production_gate_finalize(rows)$outcome, "PASS_WITH_WARNINGS")
})

test_that("missing artifacts, nonfinite required outputs, and provenance mismatch remain blocking", {
  result <- production_gate_finalize(rbind(
    production_gate_row("prepare", "missing_artifact", "BLOCKING", "FAIL", "required artifact missing"),
    production_gate_row("prepare", "finite_design", "BLOCKING", "FAIL", "required design is nonfinite"),
    production_gate_row("prepare", "parent_sha", "BLOCKING", "FAIL", "parent SHA mismatch")
  ))
  expect_identical(result$outcome, "FAIL")
  expect_equal(result$failure_count, 3L)
})

test_that("fit provenance and projection dimensions use authoritative dynamic fields", {
  metadata <- list(provenance = list(chain = list(stage3a = list(artifact_sha256 = "stage3a-sha"))))
  expect_identical(production_gate_fit_stage3a_shas(list(), metadata), "stage3a-sha")
  expect_identical(production_gate_projection_row_count(data.frame(week = 1:2, rows = c(2L, 3L))), 5L)
})

test_that("validation inventory records blocking, warning, and provenance policy", {
  inventory <- production_validation_inventory()
  expect_true(all(c("gate", "check_name", "current_location", "current_severity", "proposed_severity", "reason", "upstream_duplicate", "historical_only", "dynamic_or_hardcoded", "action") %in% names(inventory)))
  expect_true(any(inventory$check_name == "theta_compatibility" & inventory$proposed_severity == "BLOCKING"))
  expect_true(any(inventory$check_name == "dic_waic_comparison" & inventory$proposed_severity == "WARNING"))
  expect_true(any(inventory$check_name == "artifact_shas" & inventory$proposed_severity == "PROVENANCE"))
})

cat("Production orchestration tests passed\n")
