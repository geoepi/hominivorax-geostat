testthat::test_that("input manifest and supplemental input registries are machine-valid", {
  manifest_path <- "docs/input-audits/2026-11-13/input-manifest.yml"
  inventory_path <- "docs/input-audits/2026-11-13/input_file_hashes.tsv"
  registry_path <- "docs/input-audits/2026-11-13/input_registry.tsv"
  weekly_counts_path <- "docs/input-audits/2026-11-13/observation_weekly_counts.tsv"

  testthat::expect_true(requireNamespace("yaml", quietly = TRUE))
  manifest <- yaml::read_yaml(manifest_path)
  required_manifest_fields <- c(
    "manifest_schema", "manifest_version", "audit_date", "repository",
    "input_hash_inventory", "input_registry", "audit_resolution",
    "template_provenance", "software_environment", "validation"
  )
  testthat::expect_true(all(required_manifest_fields %in% names(manifest)))
  testthat::expect_identical(as.integer(manifest$input_hash_inventory$records), 511L)

  inventory <- read.delim(inventory_path, stringsAsFactors = FALSE, check.names = FALSE)
  registry <- read.delim(registry_path, stringsAsFactors = FALSE, check.names = FALSE)
  testthat::expect_identical(nrow(inventory), 511L)
  testthat::expect_identical(nrow(registry), 511L)
  testthat::expect_named(registry, c("input_id", "source_id", "path", "bytes", "sha256"))
  testthat::expect_true(all(nzchar(registry$input_id)))
  testthat::expect_true(all(nzchar(registry$source_id)))
  testthat::expect_identical(length(unique(registry$input_id)), nrow(registry))
  testthat::expect_identical(length(unique(registry$path)), nrow(registry))
  testthat::expect_true(all(grepl("^[0-9a-f]{64}$", registry$sha256)))
  testthat::expect_equal(registry[, names(inventory)], inventory)

  registry_metadata <- manifest$input_registry
  testthat::expect_identical(registry_metadata$path, basename(registry_path))
  testthat::expect_identical(as.integer(registry_metadata$records), 511L)
  testthat::expect_true(grepl("^[0-9a-f]{64}$", registry_metadata$sha256))
  testthat::expect_true(grepl("^[0-9a-f]{64}$", manifest$input_hash_inventory$sha256))
  testthat::expect_true(grepl("^[0-9a-f]{64}$", manifest$input_hash_inventory$canonical_lf_sha256))

  sha256_file <- function(path) {
    input <- readBin(path, what = "raw", n = file.info(path)$size)
    normalized <- charToRaw(gsub("\r\n", "\n", rawToChar(input), fixed = TRUE))
    normalized_file <- tempfile(pattern = "manifest-sha256-")
    writeBin(normalized, normalized_file)
    on.exit(unlink(normalized_file), add = TRUE)
    sha_command <- Sys.which("sha256sum")
    if (!nzchar(sha_command) && requireNamespace("digest", quietly = TRUE)) {
      return(digest::digest(normalized, algo = "sha256", serialize = FALSE))
    }
    if (!nzchar(sha_command)) {
      testthat::skip("sha256sum and digest are unavailable for checksum validation")
    }
    output <- system2(sha_command, args = shQuote(normalizePath(normalized_file, mustWork = TRUE)), stdout = TRUE)
    status <- attr(output, "status")
    if (!is.null(status) && status != 0L) stop("sha256sum failed for ", path)
    sub("[[:space:]].*$", "", output[[1L]])
  }
  testthat::expect_identical(sha256_file(inventory_path), manifest$input_hash_inventory$canonical_lf_sha256)
  testthat::expect_identical(sha256_file(registry_path), registry_metadata$sha256)

  weekly_counts <- read.delim(weekly_counts_path, stringsAsFactors = FALSE, check.names = FALSE)
  temporal <- manifest$audit_resolution$observation_recheck
  testthat::expect_identical(nrow(weekly_counts), as.integer(temporal$weekly_count_rows))
  testthat::expect_identical(sum(weekly_counts$observation_count), as.integer(temporal$rows))
  testthat::expect_identical(sha256_file(weekly_counts_path), temporal$weekly_counts_sha256)

  source_metadata <- manifest$audit_resolution$source_metadata
  required_sources <- c("clay", "wv0010", "surface_pressure")
  testthat::expect_true(all(required_sources %in% names(source_metadata)))
  for (source in required_sources) {
    metadata <- source_metadata[[source]]
    testthat::expect_true(all(c("source_variable_id", "description", "official_units", "stored_units_status", "scale", "offset", "data_type", "nodata", "source_version_status", "provenance_status") %in% names(metadata)))
    testthat::expect_true(nzchar(metadata$source_variable_id))
    testthat::expect_true(nzchar(metadata$provenance_status))
  }
})
