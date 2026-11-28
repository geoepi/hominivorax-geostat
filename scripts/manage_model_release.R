#!/usr/bin/env Rscript

script_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "production_orchestration.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_validation_gates.R"), local = .GlobalEnv)
source(file.path(repo_root, "R", "production_refresh_release.R"), local = .GlobalEnv)

args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  inline <- args[startsWith(args, paste0("--", name, "="))]
  if (length(inline)) return(sub(paste0("^--", name, "="), "", inline[[1L]]))
  hit <- which(args == paste0("--", name))
  if (length(hit) && hit[[1L]] < length(args)) return(args[[hit[[1L]] + 1L]])
  default
}
required <- function(name) {
  value <- option(name)
  if (is.null(value) || !nzchar(value)) stop("Missing required --", name, " argument.", call. = FALSE)
  value
}
emit <- function(result) {
  for (key in names(result)) {
    value <- result[[key]]
    if (is.null(value) || length(value) == 0L) next
    if (is.list(value)) next
    cat(key, ": ", paste(as.character(value), collapse = ","), "\n", sep = "")
  }
}

action <- tolower(required("action"))
if (action == "verify-active") {
  result <- production_release_verify_active(required("active-state"), verify_artifact = !identical(option("hash-artifact", "true"), "false"))
  cat("Read-only active release verification\n")
  emit(result)
  quit(save = "no", status = 0L)
}

if (action == "discover-active") {
  result <- production_release_discover_active(required("active-state"),
    verify_artifact = !identical(option("hash-artifact", "false"), "false"))
  cat("Read-only active release manifest discovery\n")
  emit(result[c("status", "generation", "production_id", "manifest_path", "manifest_sha256")])
  quit(save = "no", status = 0L)
}

if (action == "cleanup-report") {
  as_of <- as.Date(option("as-of", as.character(Sys.Date())))
  result <- production_release_cleanup_eligibility(required("candidate-inventory"), as_of = as_of)
  output <- required("report-output")
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(result, output, row.names = FALSE, na = "")
  cat("Read-only cleanup eligibility report written; no files were removed\n")
  cat("report_path: ", normalizePath(output, mustWork = TRUE), "\n", sep = "")
  cat("eligible_candidates: ", sum(result$retention_eligible), "\n", sep = "")
  quit(save = "no", status = 0L)
}

if (action == "register-adopted-artifacts") {
  result <- production_release_register_adoption_artifacts(required("request"), option("repo-root", repo_root))
  cat("Adopted artifacts registered atomically; dispatch disabled and no execution run created\n")
  emit(result[c("status", "request_id", "request_sha256", "registry_path", "registry_manifest", "registry_manifest_sha256", "reused_existing_registry")])
  quit(save = "no", status = 0L)
}

if (action == "register-accepted-package") {
  result <- production_release_register_accepted_package(
    required("release-manifest"), required("accepted-package"),
    required("acceptance-summary"), required("product-manifest"),
    output_path = option("output-manifest")
  )
  cat("Immutable accepted-package release manifest written; active pointer unchanged\n")
  emit(result[c("path", "sha256", "status")])
  quit(save = "no", status = 0L)
}

if (action == "reconcile") {
  result <- production_release_reconcile_deployment(required("config"), required("deployment-manifest"), option("repo-root", repo_root))
  cat("Read-only deployment reconciliation\n")
  emit(result)
  quit(save = "no", status = if (identical(result$overall_status, "MATCH")) 0L else 2L)
}

if (action == "activate") {
  result <- production_release_activate(required("active-state"), required("release-manifest"),
    as.integer(required("expected-generation")), required("expected-state-sha256"), required("event-root"))
  cat("Production release activated and independently verified\n")
  emit(result)
  quit(save = "no", status = 0L)
}

if (action == "rollback") {
  result <- production_release_rollback(required("active-state"), required("activation-event"),
    as.integer(required("expected-generation")), required("expected-state-sha256"), required("event-root"))
  cat("Production release rollback recorded and independently verified\n")
  emit(result)
  quit(save = "no", status = 0L)
}

stop("Unknown action: ", action, ". Supported actions are verify-active, discover-active, cleanup-report, register-adopted-artifacts, register-accepted-package, reconcile, activate, rollback.", call. = FALSE)
