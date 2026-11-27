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

stop("Unknown action: ", action, ". Supported actions are verify-active, reconcile, activate, rollback.", call. = FALSE)
