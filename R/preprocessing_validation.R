require_columns <- function(x, columns, label = "data") { absent <- setdiff(columns, names(x)); if (length(absent)) stop(label, " is missing required columns: ", paste(absent, collapse = ", ")); invisible(TRUE) }
assert_unique_keys <- function(x, keys, label = "data") { if (anyDuplicated(x[keys])) stop(label, " has duplicated keys: ", paste(keys, collapse = ", ")); invisible(TRUE) }
audit_row_change <- function(audit, stage, before, after, reason = NA_character_) rbind(audit, data.frame(stage = stage, before = before, after = after, excluded = before - after, reason = reason))
