quality_private_diagnostic <- function(value) {
  if (inherits(value, "error")) {
    return(list(
      error_class = class(value)[[1L]],
      error = conditionMessage(value)
    ))
  }

  goodpractice_result <- if (inherits(value, "pkgcheck")) {
    value$goodpractice
  } else if (inherits(value, "goodPractice")) {
    value
  } else {
    NULL
  }
  if (is.null(goodpractice_result)) return(NULL)

  rcmdcheck <- goodpractice_result$rcmdcheck
  rcmd_fields <- c("errors", "warnings", "notes", "status", "checkdir", "output")
  rcmd_diagnostics <- if (inherits(rcmdcheck, "try-error")) {
    list(condition = attr(rcmdcheck, "condition", exact = TRUE))
  } else if (is.list(rcmdcheck)) {
    rcmdcheck[intersect(rcmd_fields, names(rcmdcheck))]
  } else {
    NULL
  }

  checks <- goodpractice_result$checks
  failed_checks <- if (is.list(checks)) {
    checks[vapply(checks, function(check) {
      is.list(check) && identical(check$status, FALSE)
    }, logical(1))]
  } else {
    list()
  }
  if (!length(failed_checks) && !length(rcmd_diagnostics)) return(NULL)

  list(
    failed_checks = failed_checks,
    rcmdcheck = rcmd_diagnostics
  )
}

quality_public_diagnostic_summary <- function(value) {
  if (inherits(value, "error")) return("tool execution failed")

  goodpractice_result <- if (inherits(value, "pkgcheck")) {
    value$goodpractice
  } else if (inherits(value, "goodPractice")) {
    value
  } else {
    NULL
  }
  if (is.null(goodpractice_result)) return("")

  checks <- goodpractice_result$checks
  failed_checks <- if (is.list(checks)) {
    sum(vapply(checks, function(check) {
      is.list(check) && identical(check$status, FALSE)
    }, logical(1)))
  } else {
    0L
  }

  rcmdcheck <- goodpractice_result$rcmdcheck
  error_count <- if (is.list(rcmdcheck)) {
    length(rcmdcheck$errors)
  } else if (inherits(rcmdcheck, "try-error")) {
    1L
  } else {
    0L
  }
  paste0("failed_checks=", failed_checks, "; rcmdcheck_errors=", error_count)
}

write_private_quality_diagnostics <- function(step, value, failed, run_dir) {
  if (!isTRUE(failed) || !step %in% c("goodpractice", "pkgcheck")) return(NULL)

  diagnostics <- quality_private_diagnostic(value)
  if (is.null(diagnostics)) return(NULL)

  private_dir <- file.path(run_dir, "private")
  if (!dir.exists(private_dir) && !dir.create(private_dir, recursive = TRUE)) {
    stop("Could not create the private quality diagnostics directory.", call. = FALSE)
  }
  private_file <- file.path(private_dir, paste0(step, "-diagnostics.txt"))
  writeLines(capture.output(dput(diagnostics)), private_file, useBytes = TRUE)
  private_file
}
