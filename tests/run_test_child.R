args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: run_test_child.R <test-file>")
}

if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("The Atlas test runtime requires the testthat package.")
}

test_file <- normalizePath(args[[1L]], mustWork = TRUE)
repo_root <- normalizePath(getwd(), mustWork = TRUE)
wrapper_file <- tempfile(pattern = ".test-runner-", tmpdir = repo_root, fileext = ".R")
writeLines(
  sprintf("source(%s, local = TRUE)", paste(deparse(test_file), collapse = "")),
  wrapper_file,
  useBytes = TRUE
)

tryCatch(
  testthat::test_file(
    wrapper_file,
    reporter = "summary",
    stop_on_failure = TRUE
  ),
  finally = unlink(wrapper_file)
)
