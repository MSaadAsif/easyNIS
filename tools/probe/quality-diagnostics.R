check_result_counts <- function(value) {
  count <- function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0) {
      return(as.integer(x))
    }
    length(x)
  }
  c(errors = count(value$errors), warnings = count(value$warnings), notes = count(value$notes))
}

private_quality_diagnostics <- function(checks, records) {
  tool_names <- intersect(c("goodpractice", "pkgcheck"), names(checks))
  failed <- tool_names[vapply(
    tool_names,
    function(name) {
      matching_records <- Filter(function(record) identical(record$step, name), records)
      length(matching_records) > 0L &&
        any(vapply(
          matching_records,
          function(record) {
            identical(record$pass, FALSE)
          },
          logical(1)
        ))
    },
    logical(1)
  )]
  stats::setNames(
    lapply(failed, function(name) {
      warnings <- checks[[name]]$warning_conditions
      if (is.null(warnings)) {
        warnings <- list()
      }
      list(result = checks[[name]]$value, warnings = warnings)
    }),
    failed
  )
}

capture_quality_step <- function(name, fn) {
  started <- proc.time()[["elapsed"]]
  warnings <- list()
  value <- tryCatch(
    withCallingHandlers(fn(), warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }),
    error = identity
  )
  list(
    name = name,
    pass = !inherits(value, "error"),
    error_class = if (inherits(value, "error")) class(value)[[1L]] else "",
    error = if (inherits(value, "error")) "diagnostic text redacted" else "",
    warning_conditions = warnings,
    warnings = if (length(warnings)) "warning(s) captured" else "",
    elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
    value = value
  )
}

goodpractice_prep_failed <- function(prep_values) {
  any(vapply(prep_values, inherits, logical(1), "try-error"))
}

goodpractice_check_status <- function(checks) {
  statuses <- lapply(checks, function(check) {
    if (is.list(check) && "status" %in% names(check)) check$status else check
  })
  if (any(vapply(statuses, function(status) identical(status, FALSE), logical(1)))) {
    return(FALSE)
  }
  if (any(vapply(statuses, function(status) length(status) != 1L || is.na(status), logical(1)))) {
    return(NA)
  }
  TRUE
}

goodpractice_pass <- function(value) {
  if (!inherits(value, "goodPractice") || !is.list(value$checks) || !length(value$checks)) {
    return(NA)
  }
  prep_values <- value[setdiff(names(value), "checks")]
  if (goodpractice_prep_failed(prep_values)) {
    return(FALSE)
  }
  status <- goodpractice_check_status(value$checks)
  if (!isTRUE(status)) {
    return(status)
  }
  failed <- tryCatch(goodpractice::failed_checks(value), error = function(e) NULL)
  if (is.null(failed)) {
    return(NA)
  }
  !length(failed)
}

quality_public_detail <- function(name, passed) {
  if (name %in% c("goodpractice", "pkgcheck") && identical(passed, FALSE)) {
    return("check failures present")
  }
  ""
}

quality_public_diagnostic_counts <- function(value, warning_conditions = list()) {
  goodpractice_result <- if (inherits(value, "pkgcheck")) {
    value$goodpractice
  } else if (inherits(value, "goodPractice")) {
    value
  } else {
    NULL
  }
  checks <- goodpractice_result$checks
  failed_checks <- if (is.list(checks)) {
    sum(vapply(
      checks,
      function(check) {
        is.list(check) && identical(check$status, FALSE)
      },
      logical(1)
    ))
  } else {
    0L
  }
  rcmdcheck <- goodpractice_result$rcmdcheck
  rcmdcheck_errors <- if (inherits(rcmdcheck, "try-error")) {
    1L
  } else if (is.list(rcmdcheck)) {
    length(rcmdcheck$errors)
  } else {
    0L
  }
  list(
    failed_checks = as.integer(failed_checks),
    rcmdcheck_errors = as.integer(rcmdcheck_errors),
    captured_warnings = as.integer(length(warning_conditions))
  )
}

quality_receipt_record <- function(x, evidence, status, passed, detail) {
  diagnostic_counts <- quality_public_diagnostic_counts(x$value, x$warning_conditions)
  c(
    list(
      step = x$name,
      status = status,
      pass = passed,
      error_class = x$error_class,
      result_class = paste(class(x$value), collapse = ","),
      commit = evidence$commit,
      working_tree_clean = evidence$working_tree_clean,
      detail = detail,
      warnings = x$warnings,
      elapsed_seconds = x$elapsed_seconds
    ),
    diagnostic_counts
  )
}

write_private_quality_diagnostics <- function(run_dir, checks, records) {
  diagnostics <- private_quality_diagnostics(checks, records)
  if (!length(diagnostics)) {
    return(NULL)
  }
  private_dir <- file.path(run_dir, "private")
  tryCatch(
    {
      if (!dir.exists(private_dir) && !suppressWarnings(dir.create(private_dir, recursive = TRUE))) {
        stop("directory creation failed", call. = FALSE)
      }
      output <- file.path(private_dir, "quality-diagnostics.rds")
      saveRDS(diagnostics, output)
      output
    },
    error = function(error) {
      warning("Could not save private quality diagnostics (", class(error)[[1L]], ").", call. = FALSE)
      NULL
    }
  )
}
