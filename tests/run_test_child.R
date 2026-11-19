args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: run_test_child.R <test-file>")
}

if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("The Atlas test runtime requires the testthat package.")
}

test_file <- normalizePath(args[[1L]], mustWork = TRUE)
testthat::test_file(
  test_file,
  reporter = "summary",
  stop_on_failure = TRUE
)
