#!/usr/bin/env Rscript

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "cds_upstream_provenance.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_validation_gates.R"), local = .GlobalEnv)

args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  inline <- args[startsWith(args, paste0("--", name, "="))]
  if (length(inline)) return(sub(paste0("^--", name, "="), "", inline[[1L]]))
  hit <- which(args == paste0("--", name))
  if (length(hit) && hit[[1L]] < length(args)) return(args[[hit[[1L]] + 1L]])
  default
}
flag <- function(name) paste0("--", name) %in% args
eq <- function(name, value) paste0("--", name, "=", value)

mode <- tolower(option("mode", "submit"))
config_path <- option("config")
if (is.null(config_path)) stop("Usage: run_pipeline.R --mode submit|stage|direct --config PATH [options]", call. = FALSE)
config_path <- production_orchestration_resolve_path(config_path, getwd())
run_id_arg <- option("run-id")
run_root_arg <- option("run-root")
stage_arg <- option("stage")
from_arg <- option("from")
through_arg <- option("through", "postfit")
resume_arg <- option("resume")
fit_job_id_arg <- option("fit-job-id", Sys.getenv("PIPELINE_FIT_JOB_ID", unset = "not-under-scheduler"))
if (is.null(resume_arg) && flag("resume")) resume_arg <- run_id_arg
if (!is.null(resume_arg) && is.null(run_id_arg)) run_id_arg <- resume_arg
if (flag("resume") && is.null(run_id_arg)) stop("--resume requires --run-id for the existing run to resume.", call. = FALSE)

print_contract <- function(contract, dry = FALSE) {
  cat(if (dry) "DRY RUN — no jobs submitted\n" else "Production run submitted\n")
  cat("Run ID: ", contract$run_id, "\n", sep = "")
  cat("Config: ", contract$config$path, "\nSHA256: ", contract$config$sha256, "\n", sep = "")
  cat("Git commit: ", contract$repository$git_commit, "\nBranch: ", contract$repository$branch, "\n", sep = "")
  cat("Input: ", contract$input$observations, "\nSHA256: ", contract$input$sha256, "\n", sep = "")
  cat("Resolved horizon: ", contract$horizon$configured_start_epiweek, " → ", contract$horizon$resolved_final_complete_epiweek,
      " (", contract$horizon$modeled_weeks, " weeks)\n", sep = "")
  cat("Output root: ", contract$run_root, "\n", sep = "")
  if (!is.null(contract$upstream_provenance)) {
    upstream <- contract$upstream_provenance$cds_datagrab
    cat("CDS provenance: ", upstream$coverage_certificate$status, " through ", upstream$coverage_certificate$validated_through, "\n", sep = "")
    cat("CDS portfolio: ", upstream$coverage_certificate$portfolio_run_id, "\n", sep = "")
    cat("CDS fingerprint: ", upstream$overall_fingerprint, "\n", sep = "")
  }
}

run_command <- function(script, command_args) {
  rscript <- Sys.getenv("RSCRIPT_BIN", unset = "Rscript")
  status <- system2(rscript, c("--vanilla", script, command_args))
  if (!identical(as.integer(status), 0L)) stop("Pipeline command failed (status ", status, "): ", script, call. = FALSE)
  invisible(TRUE)
}

rehydrate_contract <- function(contract) {
  production_orchestration_assert_resume_repository(contract, repo_root)
  chime_execution <- production_orchestration_rehydrate_chime_execution_id(contract)
  contract <- chime_execution$contract
  cfg <- production_orchestration_read_config(config_path, repo_root)
  if (!is.null(contract$config$sha256) && !identical(as.character(contract$config$sha256), production_orchestration_hash_file(config_path))) stop("Resume config SHA does not match the run manifest.", call. = FALSE)
  if (!is.null(contract$input$sha256) && !identical(as.character(contract$input$sha256), production_orchestration_hash_file(cfg$input$observations))) stop("Resume observation-source SHA does not match the run manifest.", call. = FALSE)
  contract$settings <- list(cfg = cfg, stages = production_orchestration_read_stage_configs(cfg))
  generated <- contract$generated_configs
  if (is.null(generated)) generated <- list()
  if (!length(generated) || any(!file.exists(unlist(generated, use.names = FALSE)))) {
    contract <- production_orchestration_write_stage_configs(contract)
  } else {
    names(generated) <- sub("\\.yml$", "", basename(unlist(generated, use.names = FALSE)))
    if ("joint_inla_fit" %in% names(generated)) names(generated)[names(generated) == "joint_inla_fit"] <- "fit"
    contract$generated_configs <- generated
  }
  if (isTRUE(chime_execution$bound)) production_orchestration_write_manifest(contract)
  contract
}

load_or_create_contract <- function() {
  if (!is.null(resume_arg)) {
    if (is.null(run_id_arg)) run_id_arg <<- resume_arg
    cfg <- production_orchestration_read_config(config_path, repo_root)
    candidate_root <- run_root_arg %||% file.path(cfg$project$output_root, resume_arg)
    manifest <- file.path(candidate_root, "metadata", "run_manifest.yml")
    if (!file.exists(manifest)) stop("Cannot resume without a run manifest: ", manifest, call. = FALSE)
    return(rehydrate_contract(production_orchestration_read_manifest(manifest)))
  }
  production_orchestration_contract(config_path, repo_root, run_id = run_id_arg, run_root = run_root_arg)
}

prepare_contract <- function(contract, write_files = TRUE) {
  if (write_files) {
    dirs <- unlist(contract$paths, use.names = FALSE)
    invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
    if (is.null(contract$generated_configs)) contract <- production_orchestration_write_stage_configs(contract)
    if (cds_upstream_provenance_configured(contract)) {
      contract <- production_orchestration_attach_cds_provenance(contract, write_files = TRUE)
    }
    production_orchestration_write_manifest(contract)
  }
  contract
}

status_map <- function(contract) {
  out <- list()
  for (stage in c("prepare", "fit", "postfit")) {
    path <- file.path(contract$paths$metadata, paste0("status_", stage, ".yml"))
    if (file.exists(path)) out[[stage]] <- production_orchestration_read_manifest(path)
  }
  out
}

record_gate <- function(contract, result) {
  result <- production_gate_write(result, contract$paths$metadata, result$gate)
  gate_field <- paste0(result$gate, "_gate_status")
  contract[[gate_field]] <- result$outcome
  contract$gate_results[[result$gate]] <- list(
    outcome = result$outcome, warning_count = result$warning_count,
    failure_count = result$failure_count, csv = result$csv_path, rds = result$rds_path
  )
  contract$warning_count <- sum(vapply(contract$gate_results, function(x) as.integer(x$warning_count %||% 0L), integer(1L)))
  outcomes <- vapply(contract$gate_results, function(x) as.character(x$outcome), character(1L))
  contract$overall_status <- if (any(outcomes == "FAIL")) "FAIL" else if (any(outcomes == "PASS_WITH_WARNINGS")) "PASS_WITH_WARNINGS" else "PASS"
  production_orchestration_write_manifest(contract)
  production_gate_print(result)
  if (identical(result$outcome, "FAIL")) stop(toupper(result$gate), " gate failed; review ", result$csv_path, call. = FALSE)
  contract
}

stage_prepare <- function(contract) {
  start <- Sys.time()
  production_orchestration_write_status(contract, "prepare", "RUNNING", start_time = start, input_artifact = contract$input$observations)
  tryCatch({
    run_command(file.path(repo_root, "scripts", "run_preprocessing.R"), c("--config", contract$generated_configs$preprocessing, "--repo-root", repo_root))
    run_command(file.path(repo_root, "scripts", "prepare_joint_model.R"), c("--config", contract$generated_configs$joint_model, "--output", contract$paths$stage2))
    run_command(file.path(repo_root, "scripts", "build_joint_inla.R"), c("--config", contract$generated_configs$joint_inla, "--output", contract$paths$stage3a))
    run_command(file.path(repo_root, "scripts", "run_joint_inla.R"), c("--config", contract$generated_configs$fit, "--output", contract$paths$preflight, "--dry-run"))
    contract$dynamic_dimensions <- production_orchestration_dimension_contract(file.path(contract$paths$stage2, "joint_model_inputs.rds"), file.path(contract$paths$stage3a, "joint_inla_build.rds"))
    contract <- record_gate(contract, production_gate_prepare(contract))
    production_orchestration_write_status(contract, "prepare", if (identical(contract$prepare_gate_status, "PASS_WITH_WARNINGS")) "WARNING" else "PASS", start_time = start, input_artifact = contract$input$observations, output_artifact = file.path(contract$paths$stage3a, "joint_inla_build.rds"))
    invisible(contract)
  }, error = function(error) {
    production_orchestration_write_status(contract, "prepare", "FAIL", start_time = start, input_artifact = contract$input$observations, error = error)
    stop(error)
  })
}

stage_fit <- function(contract) {
  start <- Sys.time()
  production_orchestration_write_status(contract, "fit", "RUNNING", start_time = start, input_artifact = file.path(contract$paths$stage3a, "joint_inla_build.rds"))
  tryCatch({
    run_command(file.path(repo_root, "scripts", "run_joint_inla.R"), c("--config", contract$generated_configs$fit, "--output", contract$paths$stage3b))
    run_command(file.path(repo_root, "scripts", "check_joint_inla_fit_health.R"), c(
      eq("repo-root", repo_root), eq("fit", file.path(contract$paths$stage3b, "joint_model_fit.rds")),
      eq("build", file.path(contract$paths$stage3a, "joint_inla_build.rds")),
      eq("stage2", file.path(contract$paths$stage2, "joint_model_inputs.rds")),
      eq("output-dir", contract$paths$fit_health), eq("run-id", contract$run_id)
    ))
    contract <- record_gate(contract, production_gate_fit(contract))
    production_orchestration_write_status(contract, "fit", if (identical(contract$fit_gate_status, "PASS_WITH_WARNINGS")) "WARNING" else "PASS", start_time = start, input_artifact = file.path(contract$paths$stage3a, "joint_inla_build.rds"), output_artifact = file.path(contract$paths$stage3b, "joint_model_fit.rds"))
    invisible(contract)
  }, error = function(error) {
    production_orchestration_write_status(contract, "fit", "FAIL", start_time = start, input_artifact = file.path(contract$paths$stage3a, "joint_inla_build.rds"), error = error)
    stop(error)
  })
}

stage_postfit <- function(contract, fit_job_id = "not-under-scheduler") {
  start <- Sys.time()
  production_orchestration_write_status(contract, "postfit", "RUNNING", start_time = start, input_artifact = file.path(contract$paths$stage3b, "joint_model_fit.rds"))
  tryCatch({
    dims <- contract$dynamic_dimensions %||% production_orchestration_dimension_contract(file.path(contract$paths$stage2, "joint_model_inputs.rds"), file.path(contract$paths$stage3a, "joint_inla_build.rds"))
    fit <- file.path(contract$paths$stage3b, "joint_model_fit.rds")
    build <- file.path(contract$paths$stage3a, "joint_inla_build.rds")
    stage2 <- file.path(contract$paths$stage2, "joint_model_inputs.rds")
    holdout <- file.path(contract$paths$extraction, paste0("holdout_predictions_", contract$run_id, ".csv"))
    run_command(file.path(repo_root, "scripts", "extract_joint_inla_results.R"), c(
      eq("repo-root", repo_root), eq("build", build), eq("fit", fit), eq("stage2", stage2),
      eq("output-dir", contract$paths$extraction), eq("run-id", contract$run_id)
    ))
    run_command(file.path(repo_root, "scripts", "run_joint_inla_validation.R"), c(
      eq("repo-root", repo_root), eq("acceptance-mode", "production"), eq("build", build), eq("fit", fit),
      eq("holdout", holdout), eq("stage2", stage2), eq("output-dir", contract$paths$validation),
      eq("run-id", contract$run_id), eq("source-fit-job", fit_job_id)
    ))
    run_command(file.path(repo_root, "scripts", "run_joint_inla_projection.R"), c(
      eq("repo-root", repo_root), eq("build", build), eq("fit", fit), eq("stage2", stage2),
      eq("run-id", contract$run_id), eq("output-dir", contract$paths$projection),
      eq("expected-rows", dims$prediction_rows), eq("expected-weeks", dims$modeled_weeks),
      eq("expected-groups", dims$groups$quarter_groups)
    ))
    run_command(file.path(repo_root, "scripts", "run_joint_inla_rasterization.R"), c(
      "--repo-root", repo_root, "--phase2-output", contract$paths$projection, "--stage2-artifact", stage2,
      "--output", contract$paths$raster, "--run-id", contract$run_id,
      "--expected-weeks", dims$modeled_weeks, "--expected-rows", dims$prediction_rows, "--no-diagnostics"
    ))
    temperature_threshold <- contract$settings$cfg$reporting$temperature_mask$threshold_c %||% 14.5
    run_command(file.path(repo_root, "scripts", "run_structural_surface_diagnostics.R"), c(
      "--fit", fit, "--build", build, "--stage2", stage2, "--phase2", contract$paths$projection,
      "--phase3", contract$paths$raster, "--observations", contract$input$observations,
      "--output-root", contract$paths$structural, "--run-id", contract$run_id,
      "--expected-weeks", dims$modeled_weeks, "--expected-cells", dims$supported_cells,
      "--coordinate-source", "lonlat", "--source-crs", "EPSG:4326",
      "--temperature-variable", "mintemp", "--temperature-threshold", temperature_threshold
    ))
    masked_args <- c(
      "--stage2", stage2, "--structural-root", contract$paths$structural, "--observations", contract$input$observations,
      "--output-root", contract$paths$masked, "--run-id", contract$run_id, "--threshold-celsius", temperature_threshold,
      "--expected-weeks", dims$modeled_weeks, "--expected-cells", dims$supported_cells,
      "--coordinate-source", "lonlat", "--source-crs", "EPSG:4326"
    )
    canonical_root <- contract$settings$cfg$reporting$canonical_report_root
    if (!is.null(canonical_root) && nzchar(as.character(canonical_root))) {
      masked_args <- c(masked_args, "--canonical-report-root", production_orchestration_resolve_path(canonical_root, dirname(contract$config$path)))
    }
    run_command(file.path(repo_root, "scripts", "run_masked_structural_rpi_diagnostics.R"), masked_args)
    reporting_args <- c(
      "--repo-root", repo_root, "--run-id", contract$run_id, "--output-root", contract$paths$reporting,
      "--fit", fit, "--build", build, "--stage2", stage2, "--phase2", contract$paths$projection,
      "--phase3-root", contract$paths$raster, "--observation-input", contract$input$observations,
      "--rpi-observations", contract$input$observations, "--rpi-coordinate-source", "lonlat", "--rpi-coordinate-crs", "EPSG:4326",
      "--structural-root", contract$paths$structural, "--masked-structural-root", contract$paths$masked,
      "--expected-weeks", dims$modeled_weeks, "--expected-cells", dims$supported_cells,
      "--expected-start-week", dims$horizon_start, "--expected-end-week", dims$horizon_end,
      "--temperature-threshold", temperature_threshold, "--fit-job-id", fit_job_id,
      "--rpi-quantile", contract$settings$cfg$reporting$rpi$quantile %||% 0.10
    )
    run_command(file.path(repo_root, "scripts", "run_postfit_reporting.R"), reporting_args)
    threshold_path <- file.path(contract$paths$reporting, "objects", "rpi_dynamic_threshold.rds")
    if (!file.exists(threshold_path)) stop("Post-fit reporting did not emit the dynamic RPI threshold artifact.")
    threshold_artifact <- readRDS(threshold_path)
    if (is.null(threshold_artifact$threshold_value) || length(threshold_artifact$threshold_value) != 1L || !is.finite(as.numeric(threshold_artifact$threshold_value))) stop("Dynamic RPI threshold artifact is missing a finite threshold value.")
    reporting_summary_path <- file.path(contract$paths$reporting, "qa", "reporting_qa_summary.csv")
    if (!file.exists(reporting_summary_path)) stop("Post-fit reporting did not emit its QA summary.")
    reporting_summary <- utils::read.csv(reporting_summary_path, stringsAsFactors = FALSE)
    reporting_status <- toupper(as.character(reporting_summary$status[[1L]]))
    if (identical(reporting_status, "FAIL")) stop("Post-fit reporting QA reported FAIL.")
    contract$dynamic_rpi_threshold <- as.numeric(threshold_artifact$threshold_value)
    contract$final_reporting_path <- normalizePath(contract$paths$reporting, mustWork = TRUE)
    contract <- record_gate(contract, production_gate_postfit(contract, dims))
    contract$final_summary_path <- production_orchestration_write_final_summary(contract)
    production_orchestration_write_manifest(contract)
    production_orchestration_write_status(contract, "postfit", if (identical(contract$postfit_gate_status, "PASS_WITH_WARNINGS")) "WARNING" else "PASS", start_time = start, input_artifact = file.path(contract$paths$stage3b, "joint_model_fit.rds"), output_artifact = threshold_path)
    invisible(contract)
  }, error = function(error) {
    production_orchestration_write_status(contract, "postfit", "FAIL", start_time = start, input_artifact = file.path(contract$paths$stage3b, "joint_model_fit.rds"), error = error)
    stop(error)
  })
}

execute_stage <- function(contract, stage, fit_job_id = "not-under-scheduler") {
  if (stage == "prepare") return(stage_prepare(contract))
  if (stage == "fit") return(stage_fit(contract))
  if (stage == "postfit") return(stage_postfit(contract, fit_job_id))
  stop("Unsupported stage: ", stage, call. = FALSE)
}

contract <- load_or_create_contract()
if (mode %in% c("submit", "direct", "dry-run")) {
  dry <- identical(mode, "dry-run") || flag("dry-run")
  if (!dry) contract <- prepare_contract(contract, write_files = TRUE)
  if (dry && cds_upstream_provenance_configured(contract)) {
    contract <- production_orchestration_attach_cds_provenance(contract, write_files = FALSE)
  }
  through <- production_orchestration_stage_alias(through_arg)
  resume_statuses <- if (dry && is.null(resume_arg)) list() else status_map(contract)
  from <- production_orchestration_select_resume_stage(resume_statuses, from_arg, through)
  if (is.null(from)) {
    print_contract(contract, dry = dry)
    cat("All requested stages already have PASS status; nothing to run.\n")
    quit(save = "no", status = 0L)
  }
  if (dry) {
    print_contract(contract, dry = TRUE)
    for (stage in c("prepare", "fit", "postfit")) {
      if (stage == "prepare" && from != "prepare") next
      if (stage == "fit" && (through == "prepare" || !from %in% c("prepare", "fit"))) next
      if (stage == "postfit" && through != "postfit") next
      profile <- contract$scheduler[[stage]]
      dependency <- if (stage == "fit") "afterok:<prepare-job-id>" else if (stage == "postfit") "afterok:<fit-job-id>" else "none"
      cat("Job ", stage, ": account=", contract$scheduler$account, ", partition=", contract$scheduler$partition,
          ", cpus=", profile$cpus, ", mem=", profile$mem, ", time=", profile$time,
          ", dependency=", dependency, "\n", sep = "")
      stage_args <- c("--mode", "stage", "--config", config_path, "--run-id", contract$run_id, "--run-root", contract$run_root, "--stage", stage, "--repo-root", repo_root)
      cat("  command: ", production_orchestration_command_text(Sys.getenv("RSCRIPT_BIN", unset = "Rscript"), file.path(repo_root, "scripts", "run_pipeline.R"), stage_args), "\n", sep = "")
    }
    quit(save = "no", status = 0L)
  }
  if (identical(mode, "direct")) {
    for (stage in c("prepare", "fit", "postfit")) {
      if (stage == "prepare" && from != "prepare") next
      if (stage == "fit" && (through == "prepare" || !from %in% c("prepare", "fit"))) next
      if (stage == "postfit" && through != "postfit") next
      contract <- execute_stage(contract, stage, fit_job_id_arg)
    }
    print_contract(contract, dry = FALSE)
    quit(save = "no", status = 0L)
  }
  jobs <- list()
  for (stage in c("prepare", "fit", "postfit")) {
    if (stage == "prepare" && from != "prepare") next
    if (stage == "fit" && (through == "prepare" || !from %in% c("prepare", "fit"))) next
    if (stage == "postfit" && through != "postfit") next
    profile <- contract$scheduler[[stage]]
    dependency <- if (stage == "fit" && !is.null(jobs$prepare)) paste0("afterok:", jobs$prepare) else if (stage == "postfit" && !is.null(jobs$fit)) paste0("afterok:", jobs$fit) else NULL
    stage_args <- c("--mode", "stage", "--config", config_path, "--run-id", contract$run_id, "--run-root", contract$run_root, "--stage", stage, "--repo-root", repo_root)
    if (stage == "postfit") stage_args <- c(stage_args, "--fit-job-id", jobs$fit %||% fit_job_id_arg)
    wrap <- production_orchestration_command_text(Sys.getenv("RSCRIPT_BIN", unset = "Rscript"), file.path(repo_root, "scripts", "run_pipeline.R"), stage_args)
    sbatch_args <- c("--parsable", paste0("--job-name=hominivorax-", stage), paste0("--account=", contract$scheduler$account),
                     paste0("--partition=", contract$scheduler$partition), paste0("--cpus-per-task=", profile$cpus),
                     paste0("--mem=", profile$mem), paste0("--time=", profile$time),
                     paste0("--output=", file.path(contract$paths$logs, paste0(stage, "-%j.out"))),
                     paste0("--error=", file.path(contract$paths$logs, paste0(stage, "-%j.err"))),
                     if (!is.null(dependency)) paste0("--dependency=", dependency),
                     production_orchestration_sbatch_wrap_arg(wrap))
    value <- system2("sbatch", sbatch_args, stdout = TRUE, stderr = TRUE)
    if (!length(value) || !is.null(attr(value, "status"))) stop("Unable to submit ", stage, " job: ", paste(value, collapse = " "), call. = FALSE)
    jobs[[stage]] <- sub(";.*$", "", trimws(value[[length(value)]]))
    contract$job_ids[[stage]] <- jobs[[stage]]
    production_orchestration_write_manifest(contract)
  }
  print_contract(contract, dry = FALSE)
  cat("Prepare job: ", contract$job_ids$prepare, "\nFit job: ", contract$job_ids$fit, "\nPost-fit job: ", contract$job_ids$postfit, "\n", sep = "")
  quit(save = "no", status = 0L)
}

if (identical(mode, "stage")) {
  if (is.null(stage_arg) || is.null(run_root_arg) || is.null(run_id_arg)) stop("Stage mode requires --stage, --run-id, and --run-root.", call. = FALSE)
  contract <- rehydrate_contract(production_orchestration_read_manifest(file.path(run_root_arg, "metadata", "run_manifest.yml")))
  execute_stage(contract, production_orchestration_stage_alias(stage_arg), fit_job_id_arg)
  quit(save = "no", status = 0L)
}

stop("Unknown orchestration mode: ", mode, call. = FALSE)

