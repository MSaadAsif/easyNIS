source(file.path("tools", "probe", "helpers.R"))

test_paths <- c(
  "C:\\sandbox\\invented person\\nis.parquet",
  "D:/work/nis/input.parquet",
  "\\\\server\\share\\private data\\file.parquet",
  "/srv/invented nis/data.parquet"
)
redacted <- redact_paths(test_paths)
stopifnot(all(redacted == "[local path]"),
  redact_public_text("n=7 cases") == "n=[number] cases",
  redact_public_text("count=1e8, n=5L") == "count=[number], n=[number]",
  quality_evidence_valid(list(commit = "synthetic", working_tree_clean = TRUE), "synthetic", TRUE),
  !quality_evidence_valid(list(commit = "synthetic", working_tree_clean = FALSE), "synthetic", TRUE),
  !quality_evidence_valid(list(commit = "other", working_tree_clean = TRUE), "synthetic", TRUE),
  is.na(coverage_percent_value(list(value = NULL))),
  is.na(coverage_percent_value(list(value = NA_real_))),
  identical(coverage_percent_value(list(value = 92)), 92))

factor_condition <- simpleWarning("Unknown factor level 'Female' in stratum")
code_condition <- simpleError("Unexpected code value 'SYNTHETIC_CODE_ABC' in input")
known_safe_condition <- simpleWarning("The requested operation completed with a warning.")
factor_public <- safe_condition_record(factor_condition, "weighted_descriptives")
code_public <- safe_condition_record(code_condition, "comorbidity")
known_safe_public <- safe_condition_record(known_safe_condition, "survey_design")
stopifnot(identical(factor_public$message, "<redacted: unrecognized message>"),
  identical(code_public$message, "<redacted: unrecognized message>"),
  identical(known_safe_public$message, "The requested operation completed with a warning."),
  !grepl("Female", paste(factor_public, collapse = " "), fixed = TRUE),
  !grepl("SYNTHETIC_CODE_ABC", paste(code_public, collapse = " "), fixed = TRUE),
  identical(factor_public$condition_class, "simpleWarning"),
  identical(factor_public$calling_function, "weighted_descriptives"))

main_repo <- find_main_repo()
loop_root <- file.path(main_repo, "local", "loop")
resolved_loop <- resolve_loop_dir(main_repo, loop_root)
outside_loop <- tryCatch(resolve_loop_dir(main_repo, tempfile("outside-loop-")), error = identity)
stopifnot(path_is_within(resolved_loop, loop_root), inherits(outside_loop, "error"),
  is.list(load_reference_studies(file.path("tools", "probe", "reference-studies.yml"))),
  length(load_reference_studies(file.path("tools", "probe", "reference-studies.yml"))) == 0L,
  !valid_reference_studies(list()))

synthetic_fit <- stats::lm(mpg ~ cyl, data = datasets::mtcars)
private_fit_summary <- private_sanity_summary("regression", synthetic_fit)
stopifnot(is.matrix(private_fit_summary), !"data" %in% names(private_fit_summary),
  is.null(private_sanity_summary("code_transitions", data.frame(code = "synthetic"))))
synthetic_estimates <- data.frame(estimate = 1, standard_error = 0.1, label = "synthetic")
private_weighted_summary <- private_sanity_summary("weighted_descriptives", synthetic_estimates)
stopifnot(identical(names(private_weighted_summary), c("estimate", "standard_error")))

local({
  receipt_path <- tempfile(fileext = ".json")
  on.exit(unlink(receipt_path))
  current_commit <- "synthetic-commit"
  reference <- list(
    id = "synthetic-a", doi = "10.1234/synthetic-a",
    cohort_definition = "Invented fixture cohort", tolerance = 0.05,
    headline_estimates = list(list(
      id = "mortality", label = "Synthetic mortality", estimate_printed = "0.50",
      estimate = "0.50", ci_printed = "0.40 to 0.60", ci = c("0.40", "0.60")
    ))
  )
  receipt <- list(
    package_commit_hash = current_commit, study_id = reference$id,
    verified_at = "2026-10-20T12:00:00Z",
    results = list(list(
      estimate_id = "mortality", computed_estimate = 0.52, reference_value = 0.50,
      reference_ci = c(0.40, 0.60), tolerance = 0.05, comparison_result = "pass"
    ))
  )
  write_receipt <- function(value = receipt) {
    jsonlite::write_json(value, receipt_path, auto_unbox = TRUE)
    study_verification_ready(receipt_path, current_commit, reference)
  }
  stopifnot(valid_reference_study(reference), write_receipt())
  stopifnot(!study_verification_ready(receipt_path, "different-commit", reference))
  wrong_reference <- receipt
  wrong_reference$results[[1L]]$reference_value <- 0.45
  stopifnot(!write_receipt(wrong_reference))
  outside_tolerance <- receipt
  outside_tolerance$results[[1L]]$computed_estimate <- 0.7
  stopifnot(!write_receipt(outside_tolerance))
  missing_result <- receipt
  missing_result$results <- list()
  stopifnot(!write_receipt(missing_result))
  reference_studies <- lapply(letters[1:3], function(suffix) {
    study <- reference
    study$id <- paste0("synthetic-", suffix)
    study$doi <- paste0("10.1234/", study$id)
    study
  })
  stopifnot(valid_reference_studies(reference_studies),
    !valid_reference_studies(reference_studies[-3L]))
  reference_studies[[3L]]$id <- reference_studies[[2L]]$id
  stopifnot(!valid_reference_studies(reference_studies))

  empty_issues <- parse_open_issue_query("[]")
  one_issue <- parse_open_issue_query('[{"number":42}]')
  failed_query <- parse_open_issue_query(character(), status = 1L)
  stopifnot(empty_issues$ok, identical(empty_issues$count, 0L),
    one_issue$ok, identical(one_issue$count, 1L), !failed_query$ok)

  clean_check <- check_result_counts(list(errors = character(), warnings = character(), notes = character()))
  noted_check <- check_result_counts(list(errors = character(), warnings = character(), notes = c("one", "two")))
  stopifnot(all(clean_check == 0L), identical(unname(noted_check), c(0L, 0L, 2L)))
})

local({
  nested_pkgcheck_message <- "SYNTHETIC_PKG_CHECK_CONDITION_ABC"
  nested_prep_message <- "SYNTHETIC_GOODPRACTICE_PREP_CONDITION_XYZ"
  pkgcheck_condition <- simpleError(nested_pkgcheck_message)
  rcmd_error <- structure(nested_pkgcheck_message, class = "try-error",
    condition = pkgcheck_condition)

  prep_result <- capture_quality_step("goodpractice", function() {
    manual <- try(stop(simpleError(nested_prep_message)), silent = TRUE)
    warning(nested_prep_message, call. = FALSE)
    list(manual = manual)
  })
  stopifnot(length(prep_result$warning_conditions) == 1L,
    grepl(nested_prep_message, conditionMessage(prep_result$warning_conditions[[1L]]), fixed = TRUE))
  synthetic_goodpractice <- structure(list(
    manual = prep_result$value$manual,
    checks = list(manual = list(status = NA))
  ), class = c("goodPractice", "list"))
  stopifnot(length(goodpractice::failed_checks(synthetic_goodpractice)) == 0L,
    identical(goodpractice_pass(synthetic_goodpractice), FALSE),
    is.na(goodpractice_pass(structure(list(checks = list(manual = list(status = NA))),
      class = c("goodPractice", "list")))))
  mixed_statuses <- structure(list(checks = list(
    failed = list(status = FALSE), unknown = list(status = NA)
  )), class = c("goodPractice", "list"))
  stopifnot(identical(goodpractice_pass(mixed_statuses), FALSE))

  synthetic_pkgcheck <- structure(list(goodpractice = list(
    checks = list(manual = list(status = FALSE)), rcmdcheck = list(errors = rcmd_error)
  )), class = c("pkgcheck", "list"))
  checks <- list(pkgcheck = list(value = synthetic_pkgcheck, warning_conditions = list()),
    goodpractice = list(value = synthetic_goodpractice,
      warning_conditions = prep_result$warning_conditions))
  records <- list(
    list(step = "pkgcheck", status = "failed", pass = FALSE, error = "",
      detail = quality_public_detail("pkgcheck", FALSE), warnings = ""),
    list(step = "goodpractice", status = "failed", pass = FALSE, error = "",
      detail = quality_public_detail("goodpractice", FALSE), warnings = prep_result$warnings)
  )
  run_dir <- tempfile("synthetic-quality-run-")
  dir.create(run_dir)
  on.exit(unlink(run_dir, recursive = TRUE))
  private_path <- write_private_quality_diagnostics(run_dir, checks, records)
  restored <- readRDS(private_path)
  synthetic_receipt <- quality_receipt_record(list(name = "pkgcheck", value = synthetic_pkgcheck,
    warning_conditions = list(simpleWarning("synthetic warning"),
      simpleWarning("another synthetic warning")), error_class = "",
    warnings = "warning(s) captured", elapsed_seconds = 0),
    list(commit = "synthetic-commit", working_tree_clean = TRUE),
    status = "completed", passed = FALSE, detail = "check failures present")
  public_receipt <- jsonlite::toJSON(synthetic_receipt, auto_unbox = TRUE)
  stopifnot(file.exists(private_path),
    identical(basename(dirname(private_path)), "private"),
    identical(basename(private_path), "quality-diagnostics.rds"),
    inherits(restored$pkgcheck$result, "pkgcheck"),
    identical(attr(restored$pkgcheck$result$goodpractice$rcmdcheck$errors, "condition")$message,
      nested_pkgcheck_message),
    inherits(restored$goodpractice$result$manual, "try-error"),
    identical(attr(restored$goodpractice$result$manual, "condition")$message, nested_prep_message),
    identical(conditionMessage(restored$goodpractice$warnings[[1L]]),
      conditionMessage(prep_result$warning_conditions[[1L]])),
    !grepl(nested_pkgcheck_message, public_receipt, fixed = TRUE),
    !grepl(nested_prep_message, public_receipt, fixed = TRUE),
    !grepl("synthetic warning", public_receipt, fixed = TRUE),
    !grepl("another synthetic warning", public_receipt, fixed = TRUE),
    identical(records[[2L]]$detail, "check failures present"),
    identical(records[[2L]]$warnings, "warning(s) captured"),
    identical(records[[2L]]$error, ""),
    identical(synthetic_receipt$failed_checks, 1L),
    identical(synthetic_receipt$rcmdcheck_errors, 1L),
    identical(synthetic_receipt$captured_warnings, 2L),
    is.integer(synthetic_receipt$failed_checks), is.integer(synthetic_receipt$rcmdcheck_errors),
    is.integer(synthetic_receipt$captured_warnings),
    length(private_quality_diagnostics(checks, list(list(step = "pkgcheck", pass = TRUE),
      list(step = "goodpractice", pass = TRUE)))) == 0L)
  clean_run_dir <- tempfile("synthetic-clean-quality-run-")
  dir.create(clean_run_dir)
  on.exit(unlink(clean_run_dir, recursive = TRUE), add = TRUE)
  clean_records <- list(list(step = "pkgcheck", pass = TRUE))
  stopifnot(is.null(write_private_quality_diagnostics(clean_run_dir, checks, clean_records)),
    !dir.exists(file.path(clean_run_dir, "private")))

  blocked_dir <- tempfile("synthetic-private-path-")
  writeLines("synthetic", blocked_dir)
  on.exit(unlink(blocked_dir), add = TRUE)
  warnings <- character()
  failed_write <- withCallingHandlers(write_private_quality_diagnostics(blocked_dir, checks, records),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  stopifnot(is.null(failed_write), length(warnings) == 1L,
    grepl("Could not save private quality diagnostics", warnings[[1L]], fixed = TRUE))

  synthetic_error <- simpleError("synthetic top-level package check error")
  error_counts <- quality_public_diagnostic_counts(synthetic_error)
  error_records <- list(list(step = "pkgcheck", pass = FALSE))
  error_file <- write_private_quality_diagnostics(run_dir,
    list(pkgcheck = list(value = synthetic_error, warning_conditions = list())), error_records)
  stopifnot(inherits(readRDS(error_file)$pkgcheck$result, "error"),
    identical(error_counts, list(failed_checks = 0L, rcmdcheck_errors = 0L,
      captured_warnings = 0L)))
})

local({
  root <- tempfile("synthetic-package-")
  dir.create(file.path(root, "man"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  writeLines("export(example)", file.path(root, "NAMESPACE"))
  writeLines(c("\\name{example}", "\\examples{", "\\dontrun{", "example()", "}", "}"),
    file.path(root, "man", "example.Rd"))
  stopifnot(!exported_example_status(root)$has_examples[[1L]])
})

local({
  repo <- tempfile("synthetic-repo-")
  dir.create(repo)
  on.exit(unlink(repo, recursive = TRUE))
  writeLines("EASYNIS_LOOP_DIR=from-renviron", file.path(repo, ".Renviron"))
  old_value <- Sys.getenv("EASYNIS_LOOP_DIR", unset = NA_character_)
  on.exit(if (is.na(old_value)) Sys.unsetenv("EASYNIS_LOOP_DIR") else
    Sys.setenv(EASYNIS_LOOP_DIR = old_value), add = TRUE)
  Sys.setenv(EASYNIS_LOOP_DIR = "from-shell")
  read_main_renviron(repo)
  stopifnot(identical(Sys.getenv("EASYNIS_LOOP_DIR"), "from-shell"))
})

cat("Probe-helper tests passed.\n")
