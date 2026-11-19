testthat::test_that("canonical runner detects failed assertions and unexpected errors", {
  script <- normalizePath("tests/run_tests.R", mustWork = TRUE)
  rscript <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  output <- suppressWarnings(system2(
    rscript,
    args = c("--vanilla", shQuote(script), "--self-test"),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L

  testthat::expect_identical(as.integer(status), 0L)
  testthat::expect_true(any(grepl("TEST_RUNNER_SELF_TEST_PASS", output, fixed = TRUE)))
})
