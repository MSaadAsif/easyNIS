#!/usr/bin/env Rscript

worktree_config <- system2("git", c("config", "extensions.worktreeConfig", "true"))
if (!identical(worktree_config, 0L)) {
  stop("Could not enable worktree-specific Git configuration.", call. = FALSE)
}

hooks_path <- system2("git", c("config", "--worktree", "core.hooksPath", ".githooks"))
if (!identical(hooks_path, 0L)) {
  stop("Could not configure core.hooksPath for this worktree.", call. = FALSE)
}
message("Installed repository hooks from .githooks.")
