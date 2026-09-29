suppressPackageStartupMessages(library(testthat))

repo_root <- normalizePath(file.path(getwd()), mustWork = TRUE)
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "cds_upstream_provenance.R"), local = .GlobalEnv)

make_cds_fixture <- function() {
  root <- file.path(tempdir(), paste0("cds_provenance_", as.integer(Sys.time()), "_", sample.int(1000000L, 1L)))
  data_root <- file.path(root, "cds-datagrab-output", "data", "production")
  products <- unname(cds_upstream_provenance_required_products)
  paths <- setNames(file.path(data_root, products, "weekly"), names(cds_upstream_provenance_required_products))
  invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))
  weeks <- c("2024-W01", "2024-W02")
  for (model_covariate in names(paths)) {
    product_id <- unname(cds_upstream_provenance_required_products[[model_covariate]])
    for (week in weeks) {
      prefix <- switch(product_id, era5_mintemp = "mintemp", era5_soilmoist = "soilmoist", era5_lai_low = "lai_low", agera5_relhum_min = "relhum_min")
      raster <- file.path(paths[[model_covariate]], paste0(prefix, "_", week, ".tif"))
      file.create(raster)
      jsonlite::write_json(list(
        variable_id = product_id, week_id = week, input_fingerprint = paste0("input-", model_covariate),
        output_sha256 = paste(rep(substr(product_id, 1L, 1L), 64L), collapse = ""),
        source_family_id = paste0("family-", product_id), source_request_hashes = c(paste0("request-", product_id)),
        aggregation_algorithm_version = "weekly-test", weekly_statistic = "mean", template_sha256 = paste(rep("a", 64L), collapse = "")
      ), paste0(raster, ".json"), auto_unbox = TRUE, pretty = TRUE)
    }
  }
  portfolio_root <- file.path(root, "cds-datagrab-output", "runs", "production", "_portfolio", "20260101T000000Z_portfolio")
  dir.create(portfolio_root, recursive = TRUE, showWarnings = FALSE)
  product_records <- setNames(lapply(products, function(product_id) list(
    product_id = product_id, status = "success", weekly_expected = 2L, weekly_present = 2L, weekly_missing = list()
  )), products)
  jsonlite::write_json(list(
    run_id = "20260101T000000Z_portfolio", status = "success", requested_through = "2024-01-14",
    product_ids = products, source_workflow_ids = setNames(as.list(products), products), products = product_records,
    completed_at = "2026-01-01T00:00:00Z"
  ), file.path(portfolio_root, "portfolio_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  contract <- list(
    settings = list(cfg = list(), stages = list(preprocessing = list(dynamic_covariates = paths))),
    horizon = list(modeled_week_labels = weeks, resolved_final_complete_epiweek = "2024-W02"),
    paths = list(stage1 = file.path(root, "run", "stage1"), metadata = file.path(root, "run", "metadata"))
  )
  list(root = root, contract = contract, paths = paths, weeks = weeks)
}

test_that("CDS provenance resolves all required products and remains deterministic", {
  fixture <- make_cds_fixture()
  first <- production_orchestration_attach_cds_provenance(fixture$contract, write_files = TRUE)
  second <- production_orchestration_attach_cds_provenance(fixture$contract, write_files = FALSE)
  alternate <- fixture$contract
  alternate$paths$stage1 <- file.path(fixture$root, "another-run", "stage1")
  third <- production_orchestration_attach_cds_provenance(alternate, write_files = FALSE)
  first_cds <- first$upstream_provenance$cds_datagrab
  second_cds <- second$upstream_provenance$cds_datagrab
  third_cds <- third$upstream_provenance$cds_datagrab
  expect_equal(nrow(read.csv(first_cds$detail_artifact$path, stringsAsFactors = FALSE)), 8L)
  expect_identical(first_cds$overall_fingerprint, second_cds$overall_fingerprint)
  expect_identical(first_cds$overall_fingerprint, third_cds$overall_fingerprint)
  expect_identical(first_cds$coverage_certificate$status, "PASS")
  expect_identical(first_cds$coverage_certificate$validated_through, "2024-W02")
  expect_true(file.exists(first_cds$coverage_certificate$path))
  rows <- read.csv(first_cds$detail_artifact$path, stringsAsFactors = FALSE)
  expect_identical(rows$epiweek, rep(fixture$weeks, 4L))
  expect_true(all(nchar(rows$sidecar_sha256) == 64L))
  expect_true(all(rows$source_family_id != ""))
  expect_true(all(grepl("request-", rows$source_request_hashes, fixed = TRUE)))
})

test_that("CDS provenance rejects missing, malformed, wrong, and duplicate inputs", {
  cases <- list(
    missing_sidecar = function(fixture) unlink(paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json")),
    malformed_sidecar = function(fixture) writeLines("not-json", paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json")),
    wrong_product = function(fixture) {
      path <- paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json")
      sidecar <- jsonlite::read_json(path, simplifyVector = FALSE); sidecar$variable_id <- "wrong-product"; jsonlite::write_json(sidecar, path, auto_unbox = TRUE)
    },
    wrong_week = function(fixture) {
      path <- paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json")
      sidecar <- jsonlite::read_json(path, simplifyVector = FALSE); sidecar$week_id <- "2024-W03"; jsonlite::write_json(sidecar, path, auto_unbox = TRUE)
    },
    missing_output_sha = function(fixture) {
      path <- paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json")
      sidecar <- jsonlite::read_json(path, simplifyVector = FALSE); sidecar$output_sha256 <- "short"; jsonlite::write_json(sidecar, path, auto_unbox = TRUE)
    }
  )
  for (name in names(cases)) {
    fixture <- make_cds_fixture()
    force(cases[[name]])(fixture)
    expect_error(cds_upstream_provenance_build(fixture$contract), "CDS", info = name)
  }
  fixture <- make_cds_fixture()
  duplicate <- file.path(fixture$paths[[1L]], "mintemp_2024-W01_duplicate.tif")
  file.create(duplicate)
  file.copy(paste0(list.files(fixture$paths[[1L]], pattern = "\\.tif$", full.names = TRUE)[[1L]], ".json"), paste0(duplicate, ".json"))
  expect_error(cds_upstream_provenance_build(fixture$contract), "Duplicate CDS weekly raster", info = "duplicate")
})

test_that("coverage certificate and compact manifest/summary serialization are preserved", {
  fixture <- make_cds_fixture()
  contract <- production_orchestration_attach_cds_provenance(fixture$contract, write_files = TRUE)
  contract$run_id <- "serialization"
  contract$repository <- list(git_commit = "test-commit")
  contract$config <- list(path = "test-production.yml", sha256 = "config-sha")
  contract$input <- list(observations = "observations.csv", sha256 = "observations-sha")
  dir.create(contract$paths$metadata, recursive = TRUE, showWarnings = FALSE)
  manifest_path <- production_orchestration_write_manifest(contract)
  summary_path <- production_orchestration_write_final_summary(contract)
  manifest <- production_orchestration_read_manifest(manifest_path)
  summary <- yaml::read_yaml(summary_path)
  expect_identical(manifest$upstream_provenance$cds_datagrab$coverage_certificate$status, "PASS")
  expect_identical(summary$upstream_provenance$cds_datagrab$overall_fingerprint, contract$upstream_provenance$cds_datagrab$overall_fingerprint)
  expect_identical(yaml::read_yaml(contract$upstream_provenance$cds_datagrab$coverage_certificate$path)$status, "PASS")
})

test_that("an unsuccessful, incomplete, or incomplete-product portfolio cannot certify coverage", {
  cases <- list(
    unsuccessful = function(portfolio) { portfolio$status <- "failed"; portfolio },
    insufficient = function(portfolio) { portfolio$requested_through <- "2024-01-07"; portfolio },
    missing_product = function(portfolio) { portfolio$products$era5_lai_low <- NULL; portfolio }
  )
  for (name in names(cases)) {
    fixture <- make_cds_fixture()
    manifest_path <- list.files(file.path(fixture$root, "cds-datagrab-output", "runs"), pattern = "portfolio_manifest\\.json$", recursive = TRUE, full.names = TRUE)[[1L]]
    portfolio <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
    portfolio <- force(cases[[name]])(portfolio)
    jsonlite::write_json(portfolio, manifest_path, auto_unbox = TRUE, pretty = TRUE)
    expect_error(cds_upstream_provenance_build(fixture$contract), "No successful CDS portfolio", info = name)
  }
})

cat("CDS upstream provenance tests passed\n")
