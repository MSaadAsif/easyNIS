#!/usr/bin/env Rscript

source(".agents/skills/verify/runner.R")

expected_rows <- function(n, hospitals, stratum, threshold, secondary) {
  reasons <- rep("visible", length(n))
  reasons[n <= threshold] <- "count"
  if (!is.null(hospitals)) {
    reasons[reasons == "visible" & hospitals %in% c(0L, 1L)] <- "hospital"
  }
  if (secondary) {
    for (group in split(seq_along(n), stratum)) {
      visible <- group[reasons[group] == "visible"]
      if (length(group) - length(visible) != 1L) next
      positive <- visible[n[visible] > 0L]
      preferred <- positive[order(n[positive], positive)]
      if (length(preferred)) reasons[preferred[1L]] <- "secondary"
    }
  }
  reasons
}

expand_cases <- function(size, with_hospitals) {
  # Each row number in the Cartesian product selects one allowed (n, hospitals) pair.
  domain <- expand.grid(n = 0:3, hospitals = if (with_hospitals) 0:2 else NA_integer_)
  index <- as.matrix(expand.grid(rep(list(seq_len(nrow(domain))), size)))
  list(n = matrix(domain$n[index], nrow(index)),
    hospitals = if (with_hospitals) matrix(domain$hospitals[index], nrow(index)))
}

check_batch <- function(cases, indices, stratum, threshold, secondary, evidence) {
  size <- length(stratum)
  hospitals <- cases$hospitals
  counts <- cases$n
  input <- data.frame(
    case = rep(indices, each = size), stratum = rep(stratum, length(indices)),
    n = as.vector(t(counts[indices, , drop = FALSE])),
    estimate = rep(seq_len(size) * 11, length(indices))
  )
  if (!is.null(hospitals)) input$hospitals <- as.vector(t(hospitals[indices, , drop = FALSE]))
  reasons <- as.vector(vapply(indices, function(i) {
    expected_rows(counts[i, ], if (!is.null(hospitals)) hospitals[i, ], stratum,
      threshold, secondary)
  }, character(size)))
  actual <- easyNIS::nis_suppress(input, threshold = threshold, count_col = n,
    hospital_col = tidyselect::any_of("hospitals"), weighted_cols = estimate,
    by = c(case, stratum), secondary = secondary)

  expected <- input
  replacements <- c(count = paste0("\u2264", threshold), hospital = "<2 hospitals",
    secondary = "Masked")
  masked <- reasons != "visible"
  for (column in intersect(c("n", "hospitals", "estimate"), names(input))) {
    expected[[column]] <- as.character(input[[column]])
    expected[[column]][masked] <- unname(replacements[reasons[masked]])
  }
  if (identical(actual, expected)) return(invisible(NULL))

  differing <- if (identical(dim(actual), dim(expected)) &&
      identical(names(actual), names(expected))) {
    vapply(seq_len(nrow(input)), function(i) {
      !identical(actual[i, , drop = FALSE], expected[i, , drop = FALSE])
    }, logical(1))
  } else {
    rep(FALSE, nrow(input))
  }
  if (any(differing)) {
    case <- input$case[which(differing)[1L]]
    rows <- input$case == case
    witness <- list(threshold = threshold, secondary = secondary, input = input[rows, ],
      expected = expected[rows, ], actual = actual[rows, ])
  } else {
    witness <- list(threshold = threshold, secondary = secondary, input = input,
      expected = expected, actual = actual)
  }
  print(witness)
  dput(witness, file = file.path(evidence, "counterexample.R"))
  dput(input, file = file.path(evidence, "batch-input.R"))
  stop("Disclosure counterexample. Read counterexample.R for input, expected, and actual output.")
}

check_disclosure <- function(scratch, evidence) {
  partitions <- list(
    list(1L),
    list(c(1L, 1L), c(1L, 2L)),
    list(c(1L, 1L, 1L), c(1L, 1L, 2L), c(1L, 2L, 1L), c(1L, 2L, 2L), c(1L, 2L, 3L))
  )
  checked <- 0L
  for (size in seq_along(partitions)) {
    for (with_hospitals in c(FALSE, TRUE)) {
      cases <- expand_cases(size, with_hospitals)
      ids <- seq_len(nrow(cases$n))
      batches <- split(ids, (ids - 1L) %/% 256L)
      for (stratum in partitions[[size]]) {
        for (threshold in 0:3) {
          for (secondary in c(FALSE, TRUE)) {
            for (batch in batches) {
              check_batch(cases, batch, stratum, threshold, secondary, evidence)
            }
            checked <- checked + length(ids)
          }
        }
      }
    }
  }
  stopifnot(checked == 74368L)
  cat("EXHAUSTIVE PASS ", checked, " input tables\n", sep = "")
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) {
  stop("Usage: Rscript --vanilla .agents/skills/disclosure-suppression/check.R [scratch-source]")
}
verification_run("disclosure-suppression", check_disclosure,
  source_dir = if (length(args)) args[[1L]] else ".")
