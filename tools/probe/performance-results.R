performance_profiles <- list(
  minimum = list(threads = 4L, memory = "4 GiB", commit_bytes = 8e9),
  reference = list(threads = 8L, memory = "8 GiB", commit_bytes = 16e9)
)
performance_steps <- c("open_1", "open_5", "cohort", "design", "mean_by", "glm", "table", "whole_sample")
performance_repeats <- 3L

performance_complete <- function(trials) {
  expected <- expand.grid(
    profile = names(performance_profiles),
    step = performance_steps,
    repeat_id = seq_len(performance_repeats)
  )
  keys <- names(expected)
  all(keys %in% names(trials)) &&
    identical(sort(do.call(paste, trials[keys])), sort(do.call(paste, expected)))
}

performance_receipt <- function(loop_dir, git) {
  if (!isTRUE(git$working_tree_clean) || is.na(git$commit)) {
    return(NULL)
  }
  manifests <- Sys.glob(file.path(loop_dir, "*-performance-*", "performance-manifest.json"))
  for (file in manifests[order(file.info(manifests)$mtime, decreasing = TRUE)]) {
    manifest <- tryCatch(jsonlite::read_json(file), error = function(cnd) NULL)
    if (
      identical(manifest$mode, "invented") &&
        identical(manifest$commit, git$commit) &&
        isTRUE(manifest$working_tree_clean) &&
        identical(manifest$rows_per_year, 7000000L)
    ) {
      trials <- tryCatch(
        utils::read.delim(file.path(dirname(file), "trials.tsv")),
        error = function(cnd) NULL
      )
      if (file.exists(file.path(dirname(file), "summary.tsv")) && performance_complete(trials)) {
        return(trials)
      }
    }
  }
  NULL
}

performance_failure <- function(trials, budget) {
  if (is.null(trials)) {
    return("Needs a full invented run from this clean commit")
  }
  fields <- c("commit_bytes", "wall_s", "temp_bytes", "remaining_files")
  if (!all(c(fields, "repeat_id", "status") %in% names(trials))) {
    return("Invalid performance metrics")
  }
  ids <- sort(trials$repeat_id)
  if (length(ids) < 3L || !identical(ids, seq_along(ids))) {
    return("Needs at least three distinct repeats")
  }
  if (any(trials$status %in% "commit_limit")) {
    return("Process exceeded the profile peak commit ceiling")
  }
  if (any(trials$status %in% "host_capacity")) {
    return("Shared host lacked system commit headroom")
  }
  if (!all(trials$status %in% "ok")) {
    return("One or more repeats failed")
  }
  if (!all(vapply(trials[fields], function(x) is.numeric(x) && all(is.finite(x) & x >= 0), logical(1)))) {
    return("Invalid performance metrics")
  }
  failures <- c(
    "peak commit" = any(trials$commit_bytes > budget$commit_MB * 1e6),
    "wall time" = any(trials$wall_s > budget$wall_s),
    "temp disk" = any(trials$temp_bytes > budget$temp_MB * 1e6),
    "temp files left behind" = any(trials$remaining_files > 0)
  )
  if (any(failures)) {
    return(paste("Over budget:", paste(names(failures)[failures], collapse = ", ")))
  }
  NA_character_
}

performance_assess <- function(trials, steps = performance_steps) {
  budgets <- utils::read.delim(file.path("tools", "probe", "performance-budgets.tsv"))
  budgets <- budgets[budgets$step %in% steps, , drop = FALSE]
  failure <- vapply(
    seq_len(nrow(budgets)),
    function(i) {
      budget <- budgets[i, ]
      runs <- if (!is.null(trials)) {
        trials[which(trials$profile == budget$profile & trials$step == budget$step), , drop = FALSE]
      }
      performance_failure(runs, budget)
    },
    character(1)
  )
  data.frame(
    criterion = paste("9 Performance", budgets$profile, budgets$step, sep = " / "),
    status = ifelse(is.na(failure), "pass", "fail"),
    evidence = ifelse(is.na(failure), "All repeats within budget and no temporary files left", failure)
  )
}

performance_readiness <- function(loop_dir, git) {
  performance_assess(performance_receipt(loop_dir, git))
}

performance_summary <- function(trials) {
  groups <- split(trials, trials[c("profile", "step")], drop = TRUE)
  do.call(
    rbind,
    lapply(groups, function(group) {
      metrics <- c("wall_s", "process_s", "commit_bytes", "temp_bytes")
      medians <- vapply(group[metrics], stats::median, numeric(1), na.rm = TRUE)
      maxima <- vapply(
        group[metrics],
        function(x) if (any(is.finite(x))) max(x, na.rm = TRUE) else NA_real_,
        numeric(1)
      )
      data.frame(
        profile = group$profile[[1L]],
        step = group$step[[1L]],
        repeats = nrow(group),
        completed = sum(group$status == "ok"),
        commit_stops = sum(group$status == "commit_limit"),
        as.list(setNames(medians, paste0("median_", metrics))),
        as.list(setNames(maxima, paste0("max_", metrics))),
        remaining_files = max(group$remaining_files)
      )
    })
  )
}
