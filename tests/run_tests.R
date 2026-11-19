args <- commandArgs(trailingOnly = TRUE)

usage <- function() {
  cat(
    "Usage: Rscript tests/run_tests.R [--log-dir PATH] [--skip FILE[,FILE...]]\n",
    "       Rscript tests/run_tests.R --self-test\n",
    "FILE names are basenames such as test_postfit_reporting.R.\n",
    sep = ""
  )
}

parse_args <- function(args) {
  parsed <- list(self_test = FALSE, log_dir = NULL, skip = character())
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--self-test")) {
      parsed$self_test <- TRUE
      i <- i + 1L
    } else if (identical(arg, "--log-dir")) {
      if (i == length(args)) stop("--log-dir requires a path.", call. = FALSE)
      parsed$log_dir <- args[[i + 1L]]
      i <- i + 2L
    } else if (identical(arg, "--skip")) {
      if (i == length(args)) stop("--skip requires one or more file names.", call. = FALSE)
      parsed$skip <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]
      parsed$skip <- trimws(parsed$skip[nzchar(trimws(parsed$skip))])
      i <- i + 2L
    } else if (arg %in% c("--help", "-h")) {
      usage()
      quit(save = "no", status = 0L)
    } else {
      stop("Unknown argument: ", arg, "\n", call. = FALSE)
    }
  }
  parsed
}

options(warn = 1L)
config <- parse_args(args)
script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
script_path <- normalizePath(script_path, mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
test_dir <- file.path(repo_root, "tests")
child_script <- file.path(test_dir, "run_test_child.R")
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
if (!file.exists(rscript)) stop("Cannot locate the current Rscript executable.", call. = FALSE)

if (is.null(config$log_dir)) {
  run_dir <- tempfile(pattern = "hge-test-run-")
} else {
  log_root <- normalizePath(config$log_dir, mustWork = FALSE)
  if (!dir.exists(log_root) && !dir.create(log_root, recursive = TRUE, showWarnings = FALSE)) {
    stop("Cannot create log directory: ", log_root, call. = FALSE)
  }
  run_dir <- tempfile(pattern = "run-", tmpdir = log_root)
}
if (!dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)) {
  stop("Cannot create run directory: ", run_dir, call. = FALSE)
}

setwd(repo_root)

run_child <- function(file, label, relay = TRUE) {
  safe_label <- gsub("[^A-Za-z0-9_.-]", "_", label)
  stdout_path <- file.path(run_dir, paste0(safe_label, ".stdout.log"))
  stderr_path <- file.path(run_dir, paste0(safe_label, ".stderr.log"))
  started <- Sys.time()
  status <- tryCatch(
    suppressWarnings(system2(
      rscript,
      args = c("--vanilla", shQuote(child_script), shQuote(normalizePath(file, mustWork = TRUE))),
      stdout = stdout_path,
      stderr = stderr_path,
      wait = TRUE
    )),
    error = function(e) {
      writeLines(conditionMessage(e), stderr_path, useBytes = TRUE)
      127L
    }
  )
  if (is.null(status)) status <- 0L
  status <- as.integer(status)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  stdout_lines <- if (file.exists(stdout_path)) readLines(stdout_path, warn = FALSE) else character()
  stderr_lines <- if (file.exists(stderr_path)) readLines(stderr_path, warn = FALSE) else character()
  all_lines <- c(stdout_lines, stderr_lines)
  warning_lines <- grep("^Warning([ :]|$)", all_lines, ignore.case = TRUE, value = TRUE)
  skip_lines <- grep("skip", all_lines, ignore.case = TRUE, value = TRUE)
  result_status <- if (status != 0L) {
    "FAIL"
  } else if (length(warning_lines)) {
    "WARN"
  } else {
    "PASS"
  }

  if (relay) {
    cat("\n--- ", label, " (", result_status, ", exit ", status, ") stdout ---\n", sep = "")
    if (length(stdout_lines)) cat(stdout_lines, sep = "\n")
    if (length(stdout_lines)) cat("\n")
    if (length(stderr_lines)) {
      cat("--- ", label, " stderr ---\n", sep = "")
      cat(stderr_lines, sep = "\n")
      cat("\n")
    }
  }

  list(
    test_file = label,
    status = result_status,
    exit_status = status,
    warning_lines = length(warning_lines),
    skipped_lines = length(skip_lines),
    duration_seconds = round(elapsed, 3),
    stdout_log = stdout_path,
    stderr_log = stderr_path,
    stdout = stdout_lines,
    stderr = stderr_lines
  )
}

write_summary <- function(results) {
  columns <- c(
    "test_file", "status", "exit_status", "warning_lines", "skipped_lines",
    "duration_seconds", "stdout_log", "stderr_log"
  )
  summary <- as.data.frame(lapply(columns, function(column) {
    vapply(results, function(result) {
      value <- result[[column]]
      if (is.null(value) || length(value) == 0L || is.na(value)) "" else as.character(value)
    }, character(1L))
  }), stringsAsFactors = FALSE)
  names(summary) <- columns
  summary_path <- file.path(run_dir, "summary.tsv")
  write.table(summary, file = summary_path, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  summary
}

print_summary <- function(results, summary) {
  statuses <- vapply(results, `[[`, character(1L), "status")
  cat("\nValidation summary: executed=", sum(statuses != "SKIPPED"),
      " skipped=", sum(statuses == "SKIPPED"),
      " passed=", sum(statuses == "PASS"),
      " warned=", sum(statuses == "WARN"),
      " failed=", sum(statuses == "FAIL"), "\n", sep = "")
  cat("Per-test results: ", file.path(run_dir, "summary.tsv"), "\n", sep = "")
  cat("Captured logs: ", run_dir, "\n", sep = "")
  if (nrow(summary)) {
    print(summary[, c("test_file", "status", "exit_status", "warning_lines", "skipped_lines")], row.names = FALSE)
  }
}

if (config$self_test) {
  fixture_dir <- file.path(run_dir, "self-test-fixtures")
  if (!dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Cannot create self-test fixtures.", call. = FALSE)
  }
  assertion_file <- file.path(fixture_dir, "test_intentional_assertion_failure.R")
  error_file <- file.path(fixture_dir, "test_intentional_unexpected_error.R")
  root_file <- file.path(fixture_dir, "test_project_root_working_directory.R")
  writeLines(c(
    "testthat::test_that('intentional assertion failure is detected', {",
    "  testthat::expect_true(FALSE)",
    "})"
  ), assertion_file, useBytes = TRUE)
  writeLines(c(
    "testthat::test_that('intentional unexpected error is detected', {",
    "  stop('INTENTIONAL_RUNNER_UNEXPECTED_ERROR')",
    "})"
  ), error_file, useBytes = TRUE)
  writeLines(c(
    "testthat::test_that('project-root working directory is retained', {",
    "  testthat::expect_true(file.exists('tests/run_tests.R'))",
    "})"
  ), root_file, useBytes = TRUE)

  assertion_result <- run_child(assertion_file, "selftest_assertion_failure", relay = FALSE)
  error_result <- run_child(error_file, "selftest_unexpected_error", relay = FALSE)
  root_result <- run_child(root_file, "selftest_project_root", relay = FALSE)
  assertion_text <- paste(c(assertion_result$stdout, assertion_result$stderr), collapse = "\n")
  error_text <- paste(c(error_result$stdout, error_result$stderr), collapse = "\n")
  if (assertion_result$exit_status == 0L || !grepl("Failure", assertion_text, fixed = TRUE)) {
    stop("The runner did not detect the intentional assertion failure; see self-test logs.", call. = FALSE)
  }
  if (error_result$exit_status == 0L || !grepl("INTENTIONAL_RUNNER_UNEXPECTED_ERROR", error_text, fixed = TRUE)) {
    stop("The runner did not detect the intentional unexpected error; see self-test logs.", call. = FALSE)
  }
  if (root_result$exit_status != 0L) {
    stop("The runner did not retain the repository-root working directory; see self-test logs.", call. = FALSE)
  }
  cat("TEST_RUNNER_SELF_TEST_PASS: failure propagation and repository-root context verified.\n")
  cat("Self-test logs: ", run_dir, "\n", sep = "")
  quit(save = "no", status = 0L)
}

test_files <- sort(list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE))
if (!length(test_files)) stop("No tests/test_*.R files were found.", call. = FALSE)
test_names <- basename(test_files)
unknown_skips <- setdiff(config$skip, test_names)
if (length(unknown_skips)) {
  stop("Unknown --skip file(s): ", paste(unknown_skips, collapse = ", "), call. = FALSE)
}

results <- vector("list", length(test_files))
for (i in seq_along(test_files)) {
  label <- test_names[[i]]
  if (label %in% config$skip) {
    results[[i]] <- list(
      test_file = label, status = "SKIPPED", exit_status = NA_integer_,
      warning_lines = 0L, skipped_lines = 0L, duration_seconds = 0,
      stdout_log = "", stderr_log = ""
    )
    cat("\n--- ", label, " (SKIPPED by --skip) ---\n", sep = "")
  } else {
    cat("\nRunning ", label, "\n", sep = "")
    results[[i]] <- run_child(test_files[[i]], label)
  }
}

summary <- write_summary(results)
print_summary(results, summary)
if (any(vapply(results, function(result) identical(result$status, "FAIL"), logical(1L)))) {
  quit(save = "no", status = 1L)
}
quit(save = "no", status = 0L)
