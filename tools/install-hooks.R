#!/usr/bin/env Rscript

hooks_path <- system2("git", c("config", "core.hooksPath", ".githooks"))
if (!identical(hooks_path, 0L)) {
  stop("Could not configure core.hooksPath for this repository.", call. = FALSE)
}
message("Installed repository hooks from .githooks.")
