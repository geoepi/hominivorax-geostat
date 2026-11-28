repo_root <- normalizePath(".", mustWork = TRUE)
source(file.path(repo_root, "R", "load_preprocessing.R"))
load_preprocessing(repo_root)
testthat::local_edition(3)

make_observation_fixture <- function() {
  root <- tempfile("observation-checksum-gate-")
  dir.create(root, recursive = TRUE)
  observation_path <- file.path(root, "observations.csv")
  writeBin(charToRaw("abc"), observation_path)
  manifest_path <- file.path(root, "manifest.yml")
  writeLines("fixture: observation-checksum-gate", manifest_path)
  list(
    root = root,
    observation_path = observation_path,
    manifest_path = manifest_path,
    manifest_identity = "id=configuration_c; version=C-1; schema=fixture/v1; manifest_version=1",
    expected_sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
}

testthat::test_that("observation checksum gate accepts matching bytes", {
  fixture <- make_observation_fixture()
  result <- verify_observation_source_identity(
    fixture$observation_path, fixture$expected_sha256,
    fixture$observation_path, fixture$manifest_path, fixture$manifest_identity
  )
  testthat::expect_identical(result$classification, "OBSERVATION_SOURCE_IDENTITY_VERIFIED")
  testthat::expect_identical(result$expected_sha256, fixture$expected_sha256)
  testthat::expect_identical(result$observed_sha256, fixture$expected_sha256)
  testthat::expect_identical(result$resolved_source_path, normalizePath(fixture$observation_path, winslash = "/"))
})

testthat::test_that("observation checksum gate reports a changed source digest", {
  fixture <- make_observation_fixture()
  wrong_sha256 <- paste0("0", substring(fixture$expected_sha256, 2L))
  testthat::expect_error(
    verify_observation_source_identity(
      fixture$observation_path, wrong_sha256,
      fixture$observation_path, fixture$manifest_path, fixture$manifest_identity
    ),
    "OBSERVATION_SOURCE_IDENTITY_MISMATCH.*expected SHA-256=.*observed SHA-256=.*manifest identity="
  )
})

testthat::test_that("observation checksum gate identifies a resolved path defect", {
  fixture <- make_observation_fixture()
  wrong_path <- file.path(fixture$root, "other-observations.csv")
  writeBin(charToRaw("different"), wrong_path)
  testthat::expect_error(
    verify_observation_source_identity(
      wrong_path, fixture$expected_sha256,
      fixture$observation_path, fixture$manifest_path, fixture$manifest_identity
    ),
    "RUNTIME_CONFIGURATION_DEFECT.*resolved source path=.*expected SHA-256=.*observed SHA-256=NOT_COMPUTED.*manifest identity="
  )
})

testthat::test_that("malformed manifest checksums include manifest identity diagnostics", {
  manifest_path <- file.path(repo_root, "docs", "input-audits", "2026-11-13", "configuration-c-input-manifest.yml")
  registry <- yaml::read_yaml(manifest_path)
  registry$observations$sha256 <- "not-a-sha256"
  testthat::expect_error(
    validate_covariate_registry(registry, manifest_path = manifest_path),
    "MALFORMED_MANIFEST_SHA256.*expected SHA-256=not-a-sha256.*observed SHA-256=NOT_COMPUTED.*manifest identity=id=configuration_c"
  )
})

testthat::test_that("missing observation sources fail closed with diagnostics", {
  fixture <- make_observation_fixture()
  missing_path <- file.path(fixture$root, "missing-observations.csv")
  testthat::expect_error(
    verify_observation_source_identity(
      missing_path, fixture$expected_sha256,
      missing_path, fixture$manifest_path, fixture$manifest_identity
    ),
    "MISSING_OBSERVATION_SOURCE.*resolved source path=.*expected SHA-256=.*observed SHA-256=NOT_COMPUTED.*manifest identity="
  )
})
