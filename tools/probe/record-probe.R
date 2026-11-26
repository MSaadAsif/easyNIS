new_probe_recorder <- function(run_dir) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install jsonlite to write probe findings.")
  }
  private_dir <- file.path(run_dir, "private")
  if (!dir.create(private_dir)) {
    stop("Could not create the private probe directory.")
  }
  findings_file <- file.path(run_dir, "findings.jsonl")
  if (!file.create(findings_file)) {
    stop("Could not create the probe findings file.")
  }
  failures <- character()
  private_estimates <- list()
  private_condition_details <- list()

  record <- function(step, function_name, year, fun, private_summary = NULL) {
    conditions <- list()
    capture_condition <- function(condition, kind) {
      private_condition_details[[length(private_condition_details) + 1L]] <<- list(
        step = step,
        condition_type = kind,
        condition_class = class(condition),
        calling_function = function_name,
        message = conditionMessage(condition)
      )
      conditions[[length(conditions) + 1L]] <<- safe_condition_record(condition, function_name)
      invisible(NULL)
    }
    started <- proc.time()[["elapsed"]]
    gc(reset = TRUE)
    result <- tryCatch(
      withCallingHandlers(
        {
          value <- fun()
          if (inherits(value, "error")) {
            value
          } else {
            summary <- if (!is.null(private_summary)) private_summary(value)
            list(value = value, summary = summary)
          }
        },
        warning = function(w) {
          capture_condition(w, "warning")
          invokeRestart("muffleWarning")
        },
        message = function(m) {
          capture_condition(m, "message")
          invokeRestart("muffleMessage")
        }
      ),
      error = identity
    )
    elapsed <- unname(proc.time()[["elapsed"]] - started)
    memory <- tryCatch(
      {
        peak <- gc()[, "max used"]
        cell_bytes <- if (.Machine$sizeof.pointer == 8L) 56 else 32
        (peak[["Ncells"]] * cell_bytes + peak[["Vcells"]] * .Machine$sizeof.pointer) / 1024^2
      },
      error = function(e) NA_real_
    )
    failed <- inherits(result, "error")
    if (failed) {
      capture_condition(result, "error")
    }
    finding <- list(
      step = step,
      function_name = function_name,
      year = year,
      pass = !failed,
      conditions = conditions,
      elapsed_seconds = elapsed,
      peak_r_heap_mb_estimate = as.numeric(memory)
    )
    if (failed) {
      failures <<- c(failures, step)
    }
    line <- jsonlite::toJSON(finding, auto_unbox = TRUE, null = "null", na = "null", dataframe = "rows", digits = NA)
    cat(line, "\n", file = findings_file, append = TRUE, sep = "")
    if (failed) {
      return(invisible(result))
    }
    if (!is.null(result$summary)) {
      private_estimates[[step]] <<- result$summary
    }
    invisible(result$value)
  }

  finish <- function() {
    saveRDS(private_estimates, file.path(private_dir, "sanity-checks.rds"))
    saveRDS(private_condition_details, file.path(private_dir, "condition-details.rds"))
    unique(failures)
  }
  list(record = record, finish = finish)
}

numeric_probe_summary <- function(result) {
  result[vapply(result, is.numeric, logical(1))]
}
