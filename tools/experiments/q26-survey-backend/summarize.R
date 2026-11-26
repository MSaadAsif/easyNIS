run <- commandArgs(trailingOnly = TRUE)[[1L]]
trials <- read.delim(file.path(run, "metrics.tsv"), check.names = FALSE)
build_file <- file.path(run, "construction.tsv")
split_construction <- file.exists(build_file)
if (split_construction) builds <- read.delim(build_file)
tolerance <- 1e-6

result <- function(row) {
  path <- file.path(run, sprintf("%s-%s-%d", row$call, row$path, row[["repeat"]]),
    "statistics.rds")
  readRDS(path)
}

relative_difference <- function(x, y) {
  if (anyDuplicated(x$term) || !setequal(x$term, y$term)) {
    return(c(estimate = Inf, se = Inf))
  }
  y <- y[match(x$term, y$term), ]
  delta <- function(a, b) max(abs(a - b) / pmax(abs(a), abs(b), .Machine$double.eps))
  c(estimate = delta(x$estimate, y$estimate), se = delta(x$se, y$se))
}

measurements <- lapply(unique(trials$call), function(task) {
  pair <- trials[trials$call == task, , drop = FALSE]
  successes <- pair[pair$status == "ok", , drop = FALSE]
  differences <- c(estimate = NA_real_, se = NA_real_)
  agreement <- "unavailable"
  if (task != "table" && length(unique(successes$path)) == 2L) {
    results <- lapply(split(successes, successes$path), function(rows) {
      lapply(seq_len(nrow(rows)), function(i) result(rows[i, ]))
    })
    deltas <- lapply(results$dbi, function(x) {
      vapply(results$placeholder, function(y) relative_difference(x, y), numeric(2))
    })
    differences <- apply(do.call(cbind, deltas), 1L, max)
    agreement <- if (all(differences <= tolerance)) "pass" else "fail"
  }
  do.call(rbind, lapply(split(pair, pair$path), function(rows) {
    median_or_na <- function(x) if (all(is.na(x))) NA_real_ else median(x, na.rm = TRUE)
    build <- if (split_construction) builds[match(rows$design_key[[1L]], builds$design_key), ] else rows
    build_time <- median_or_na(build$build_s)
    build_peak <- max(build$build_peak_bytes)
    if (split_construction && build$status != "ok") build_peak <- build$peak_bytes
    call_peak <- max(rows$peak_bytes)
    combined_peak <- max(build_peak, call_peak)
    call_time <- median_or_na(rows$call_s)
    data.frame(profile = rows$profile[[1L]], call = task, path = rows$path[[1L]],
      runs = nrow(rows), status = paste(unique(rows$status), collapse = "/"),
      build_s = build_time, call_s = call_time,
      load_s = if (split_construction && rows$stage[[1L]] == "load") median_or_na(rows$build_s) else NA_real_,
      total_s = if (split_construction) build_time + call_time else
        median_or_na(rows$build_s + rows$call_s),
      process_s = median(rows$process_s),
      build_peak_GB = build_peak / 1e9,
      peak_GB = call_peak / 1e9,
      combined_peak_GB = combined_peak / 1e9,
      within_8GB = if (combined_peak > 8e9) "no" else
        if (all(rows$status == "ok")) "yes" else "unavailable",
      temp_peak_bytes = max(rows$temp_peak_bytes, build$temp_peak_bytes),
      residual_bytes = max(rows$residual_bytes, build$residual_bytes),
      relative_estimate = differences[[1L]], relative_se = differences[[2L]],
      agreement = agreement)
  }))
})

summary <- do.call(rbind, measurements)
write.table(summary, file.path(run, "summary.tsv"), sep = "\t", row.names = FALSE,
  quote = FALSE)

# An independent verb on the same design must reproduce the survey domain estimate.
crosscheck <- lapply(c("dbi", "placeholder"), function(path) {
  x <- trials[trials$call == "srvyr" & trials$path == path & trials$status == "ok", ]
  y <- trials[trials$call == "adult_by" & trials$path == path & trials$status == "ok", ]
  delta <- if (nrow(x) && nrow(y)) relative_difference(result(x[1L, ]), result(y[1L, ])) else
    c(estimate = NA_real_, se = NA_real_)
  data.frame(path = path, relative_estimate = delta[[1L]], relative_se = delta[[2L]],
    agreement = if (anyNA(delta)) "unavailable" else
      if (all(delta <= tolerance)) "pass" else "fail")
})
write.table(do.call(rbind, crosscheck), file.path(run, "srvyr-vs-survey.tsv"),
  sep = "\t", row.names = FALSE, quote = FALSE)
