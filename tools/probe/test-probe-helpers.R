source(file.path("tools", "probe", "helpers.R"))
source(file.path("tools", "probe", "provenance.R"))

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

assert_readiness_rejects_statuses <- function(run_readiness, baseline, manual) {
  for (status in c("failed", "partial", "not_verified", "", NA_character_)) {
    altered <- baseline
    altered$status <- status
    stopifnot(!run_readiness(coverage = altered)$coverage_ready)
    altered <- manual
    altered$status <- status
    stopifnot(!run_readiness(subset = altered)$pkgcheck_pass)
  }
}

assert_readiness_rejects_malformed_lines <- function(run_readiness) {
  lines <- c(
    "{\"step\":\"coverage_percent\",\"INVENTED_PRIVATE_MARKER\":",
    "{\"step\":\"coverage_percent\"}",
    paste0("{\"step\":\"coverage_percent\",\"status_extra\":\"completed\",\"pass\":true,",
      "\"value\":94,\"commit\":\"invented-head\",\"working_tree_clean\":true}"),
    paste0("{\"step\":\"coverage_percent\",\"status\":\"completed\",\"pass\":true,",
      "\"value_extra\":94,\"commit\":\"invented-head\",\"working_tree_clean\":true}"),
    paste0("{\"step\":\"coverage_percent\",\"status\":\"completed\",\"pass\":true,\"value\":94,",
      "\"commit\":{\"text\":\"INVENTED_PRIVATE_MARKER\"},\"working_tree_clean\":true}"),
    paste0("{\"step\":\"coverage_percent\",\"commit\":\"invented-head\",",
      "\"working_tree_clean\":true,\"status\":7}"),
    "{\"step\":\"coverage_percent\",\"step\":\"coverage_percent\"}",
    paste0("{\"diagnostic\":{\"step\":\"diagnostic-only\"},\"step\":\"coverage_percent\",",
      "\"status\":\"failed\",\"status\":\"completed\"}"),
    paste0("{\"diagnostic\":{\"step\":\"pkgcheck\"},\"step\":\"coverage_percent\",",
      "\"status\":\"failed\",\"status\":\"completed\"}"),
    paste0("{\"diagnostic\":{\"step\":\"diagnostic-only\"},\"step\":\"coverage_percent\",",
      "\"unfinished\":"),
    "{\"step\":\"diagnostic-only\",\"step\":\"coverage_percent\"}")
  for (line in lines) {
    result <- run_readiness(line)
    stopifnot(!result$coverage_ready, result$check_pass("cyclocomp_linter(15)"))
  }
}

quality_item_from_line <- function(line) {
  parse_line <- match.fun("parse_quality_line")
  parsed <- parse_line(line)
  if (inherits(parsed, "invalid_quality_records")) parsed[[1L]] else parsed
}

append_raw_receipt <- function(path, bytes) {
  if (!length(bytes)) return(invisible(NULL))
  connection <- file(path, open = "ab")
  on.exit(close(connection))
  writeBin(bytes, connection)
  invisible(NULL)
}

assert_reconcile_cases <- function(run_readiness, encode) {
  shape_valid <- match.fun("quality_receipt_shape_valid")
  should_apply <- match.fun("quality_evidence_should_apply")
  receipt_pairs <- list(
    completed_pass = list(status = "completed", pass = TRUE),
    completed_failure = list(status = "completed", pass = FALSE),
    failed = list(status = "failed", pass = FALSE),
    partial = list(status = "partial", pass = FALSE),
    not_verified = list(status = "not_verified", pass = NULL),
    not_verified_failure = list(status = "not_verified", pass = FALSE),
    selection_skip = list(status = "skipped_by_selection", pass = NULL),
    missing_dependency = list(status = "skipped_not_installed", pass = NULL))
  receipt_shape <- function(pair) {
    shape_valid(c(list(step = "pkgcheck", commit = "invented-head",
      working_tree_clean = TRUE), pair))
  }
  stopifnot(all(vapply(receipt_pairs, receipt_shape, logical(1))))
  invalid_pairs <- list(list(status = "completed", pass = NA),
    list(status = "partial", pass = c(FALSE, TRUE)))
  stopifnot(!any(vapply(invalid_pairs, receipt_shape, logical(1))))
  make_receipts <- function(commit, clean) {
    lapply(receipt_pairs, function(pair) {
      c(list(step = "pkgcheck", commit = commit, working_tree_clean = clean), pair)
    })
  }
  dirty_receipts <- make_receipts("invented-head", FALSE)
  clean_receipts <- make_receipts("invented-head", TRUE)
  stale_receipts <- make_receipts("invented-old", TRUE)
  stopifnot(all(vapply(dirty_receipts, shape_valid, logical(1))),
    identical(unname(vapply(dirty_receipts, should_apply, logical(1),
      current_commit = "invented-head")),
      rep(FALSE, length(receipt_pairs))),
    identical(unname(vapply(clean_receipts, should_apply, logical(1),
      current_commit = "invented-head")),
      c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE)),
    identical(unname(vapply(stale_receipts, should_apply, logical(1),
      current_commit = "invented-head")), rep(FALSE, length(receipt_pairs))))
  malformed_cases <- list(
    known_stale_partial = list(line =
      '{"step":"ropensci_manual_subset","commit":"invented-old","status":', apply = FALSE),
    malformed_current_skip = list(line = paste0(
      '{"step":"coverage_percent","commit":"invented-head",',
      '"status":"skipped_by_selection","pass":false,"working_tree_clean":true}'),
      apply = TRUE),
    ambiguous_skip_commit = list(line = paste0(
      '{"step":"coverage_percent","status":"skipped_by_selection",',
      '"pass":null,"working_tree_clean":true,"commit":"invented-head",',
      '"commit":"invented-old","unfinished":'), apply = TRUE))
  malformed_applies <- vapply(malformed_cases, function(case) {
    item <- quality_item_from_line(case$line)
    identical(should_apply(item, "invented-head"), case$apply)
  }, logical(1))
  stopifnot(all(malformed_applies))
  dirty_failures <- lapply(receipt_pairs[c("completed_failure", "failed", "partial",
    "not_verified_failure")],
    function(pair) {
      c(list(step = "ropensci_manual_subset", commit = "invented-head",
        working_tree_clean = FALSE), pair)
    })
  clean_failures <- lapply(dirty_failures, function(item) {
    item$working_tree_clean <- TRUE
    item
  })
  stopifnot(all(vapply(dirty_failures, function(item) {
    shape_valid(item) && !should_apply(item, "invented-head")
  }, logical(1))), all(vapply(clean_failures, function(item) {
    shape_valid(item) && should_apply(item, "invented-head")
  }, logical(1))))
  dirty_manual_failures <- lapply(dirty_failures, function(item) {
    run_readiness(extra = encode(item))$pkgcheck_pass
  })
  current_partial_failure <- clean_failures[["partial"]]
  stopifnot(all(unlist(dirty_manual_failures)),
    !run_readiness(extra = encode(current_partial_failure))$pkgcheck_pass)
}

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
  boolean_reference <- reference
  boolean_reference$headline_estimates[[1L]]$estimate <- TRUE
  stopifnot(!valid_reference_study(boolean_reference))
  # Values that would pass if TRUE were coerced to one.
  unit_reference <- reference
  unit_reference$headline_estimates[[1L]]$estimate <- "1.00"
  unit_reference$headline_estimates[[1L]]$ci <- c("0.00", "1.00")
  unit_receipt <- receipt
  unit_receipt$results[[1L]]$computed_estimate <- 1
  unit_receipt$results[[1L]]$reference_value <- 1
  unit_receipt$results[[1L]]$reference_ci <- c(0, 1)
  jsonlite::write_json(unit_receipt, receipt_path, auto_unbox = TRUE)
  stopifnot(study_verification_ready(receipt_path, current_commit, unit_reference))
  string_receipt <- unit_receipt
  string_receipt$results[[1L]]$computed_estimate <- "1.00"
  string_receipt$results[[1L]]$reference_value <- "1.00"
  string_receipt$results[[1L]]$reference_ci <- c("0.00", "1.00")
  jsonlite::write_json(string_receipt, receipt_path, auto_unbox = TRUE)
  stopifnot(study_verification_ready(receipt_path, current_commit, unit_reference))
  for (field in c("computed_estimate", "reference_value", "reference_ci", "tolerance")) {
    malformed <- unit_receipt
    malformed$results[[1L]][[field]] <- if (field == "reference_ci") list(FALSE, TRUE) else TRUE
    jsonlite::write_json(malformed, receipt_path, auto_unbox = TRUE)
    stopifnot(!study_verification_ready(receipt_path, current_commit, unit_reference))
  }
  for (field in c("id", "doi", "cohort_definition", "tolerance", "headline_estimates")) {
    malformed <- reference
    malformed[[field]] <- NULL
    stopifnot(!valid_reference_study(malformed))
  }
  malformed <- reference
  malformed$tolerance <- NA_real_
  stopifnot(!valid_reference_study(malformed))
  malformed_estimate <- reference
  malformed_estimate$headline_estimates[[1L]]$ci <- c("bad", "0.6")
  stopifnot(!valid_reference_study(malformed_estimate))
  malformed_estimate$headline_estimates[[1L]]$ci <- c("0.4", "0.6")
  malformed_estimate$headline_estimates[[1L]]$estimate <- NA_character_
  stopifnot(!valid_reference_study(malformed_estimate))
  for (field in c("estimate_id", "computed_estimate", "reference_value", "reference_ci",
      "tolerance", "comparison_result")) {
    malformed <- receipt
    malformed$results[[1L]][[field]] <- NULL
    stopifnot(!write_receipt(malformed))
  }
  malformed_id <- receipt
  malformed_id$results[[1L]]$estimate_id <- NA_character_
  stopifnot(!write_receipt(malformed_id))
  stopifnot(!study_verification_ready(receipt_path, "different-commit", reference))
  receipt_json <- as.character(jsonlite::toJSON(receipt, auto_unbox = TRUE))
  note_only_json <- sub('"package_commit_hash":"synthetic-commit"',
    '"package_commit_hash_note":"synthetic-commit"', receipt_json, fixed = TRUE)
  writeLines(note_only_json, receipt_path)
  stopifnot(!study_verification_ready(receipt_path, current_commit, reference))
  duplicate_estimate_json <- sub('"computed_estimate":0.52',
    '"computed_estimate":0.52,"computed_estimate":true', receipt_json, fixed = TRUE)
  writeLines(duplicate_estimate_json, receipt_path)
  stopifnot(!study_verification_ready(receipt_path, current_commit, reference))
  wrong_reference <- receipt
  wrong_reference$results[[1L]]$reference_value <- 0.45
  stopifnot(!write_receipt(wrong_reference))
  outside_tolerance <- receipt
  outside_tolerance$results[[1L]]$computed_estimate <- 0.7
  stopifnot(!write_receipt(outside_tolerance))
  at_tolerance <- receipt
  at_tolerance$results[[1L]]$computed_estimate <- 0.5625
  at_tolerance$results[[1L]]$tolerance <- 0.0625
  reference$tolerance <- 0.0625
  stopifnot(write_receipt(at_tolerance))
  reference$tolerance <- 0.05
  wrong_ci <- receipt
  wrong_ci$results[[1L]]$reference_ci <- c(0.41, 0.60)
  stopifnot(!write_receipt(wrong_ci))
  wrong_result_type <- receipt
  wrong_result_type$results <- list("not-an-object")
  stopifnot(!write_receipt(wrong_result_type))
  wrong_order <- receipt
  reference$headline_estimates[[2L]] <- list(id = "second", label = "Synthetic second",
    estimate_printed = "0.30", estimate = "0.30", ci_printed = "0.20 to 0.40",
    ci = c("0.20", "0.40"))
  wrong_order$results <- list(
    list(estimate_id = "second", computed_estimate = 0.30, reference_value = 0.30,
      reference_ci = c(0.20, 0.40), tolerance = 0.05, comparison_result = "pass"),
    receipt$results[[1L]])
  stopifnot(write_receipt(wrong_order))
  duplicate_id <- wrong_order
  duplicate_id$results[[1L]]$estimate_id <- "mortality"
  stopifnot(!write_receipt(duplicate_id))
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
  malformed_object <- parse_open_issue_query("{}")
  malformed_single_issue <- parse_open_issue_query('{"number":42}')
  failed_query <- parse_open_issue_query(character(), status = 1L)
  stopifnot(empty_issues$ok, identical(empty_issues$count, 0L),
    one_issue$ok, identical(one_issue$count, 1L),
    !malformed_object$ok, is.na(malformed_object$count),
    !malformed_single_issue$ok, is.na(malformed_single_issue$count),
    !failed_query$ok)

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
  run_prep_step <- getFromNamespace("run_prep_step", "goodpractice")

  prep_result <- capture_quality_step("goodpractice", function() {
    run_prep_step(list(), "manual", function() stop(simpleError(nested_prep_message)), silent = TRUE)
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

local({
  fixture_dir <- tempfile("invented-readiness-")
  dir.create(fixture_dir)
  on.exit(unlink(fixture_dir, recursive = TRUE))
  quality_file <- file.path(fixture_dir, "quality.jsonl")
  baseline <- list(step = "coverage_percent", status = "completed", pass = TRUE,
    value = 94, commit = "invented-head", working_tree_clean = TRUE)
  pkg <- baseline
  pkg$step <- "pkgcheck"
  manual <- baseline
  manual$step <- "ropensci_manual_subset"
  complexity <- baseline
  complexity$step <- "cyclocomp_linter(15)"
  encode <- function(item) as.character(jsonlite::toJSON(item, auto_unbox = TRUE, null = "null"))
  run_readiness <- function(extra = character(), coverage = baseline, subset = manual,
      clean = TRUE, extra_raw = raw()) {
    writeLines(c(vapply(list(coverage, pkg, subset, complexity), encode, character(1)), extra),
      quality_file)
    append_raw_receipt(quality_file, extra_raw)
    env <- new.env(parent = globalenv())
    env$source <- function(file) {
      sys.source(file, envir = env)
      env$find_main_repo <- function(...) normalizePath(".")
      env$read_main_renviron <- function(...) invisible(NULL)
      env$resolve_loop_dir <- function(...) fixture_dir
      env$git_evidence <- function(...) list(commit = "invented-head", working_tree_clean = clean)
    }
    env$system2 <- function(command, args, ...) {
      stopifnot(identical(command, "gh"))
      if (identical(args[[1L]], "issue")) return("[]")
      '[{"name":"R-CMD-check","headSha":"invented-head","status":"completed","conclusion":"success"}]'
    }
    output <- capture.output(sys.source("tools/probe/readiness.R", envir = env))
    stopifnot(nrow(env$criteria) == 8L,
      !any(grepl("INVENTED_PRIVATE_MARKER", output, fixed = TRUE)))
    env
  }
  assert_reconcile_cases(run_readiness, encode)
  ready <- run_readiness()
  stopifnot(ready$coverage_ready, ready$pkgcheck_pass,
    ready$check_pass("cyclocomp_linter(15)"), ready$ci_runs_ok, ready$issues_clean)
  nonpassing_pairs <- list(list(status = "failed", pass = TRUE),
    list(status = "partial", pass = NULL), list(status = "not_verified", pass = TRUE),
    list(status = "completed", pass = NULL))
  for (pair in nonpassing_pairs) {
    altered <- baseline
    altered$status <- pair$status
    altered["pass"] <- list(pair$pass)
    stopifnot(quality_receipt_shape_valid(altered),
      !run_readiness(coverage = altered)$coverage_ready)
  }
  exact_pass <- baseline
  exact_pass$passed <- exact_pass$pass
  exact_pass$pass <- NULL
  stopifnot(!quality_receipt_shape_valid(exact_pass))
  synthetic_hits <- c(1, 0)
  synthetic_coverage <- structure(list(hits = synthetic_hits), class = "coverage")
  synthetic_percent <- function(value) 100 * mean(value$hits > 0)
  clean_below_threshold <- coverage_percent_record(
    list(value = synthetic_coverage, error_class = ""),
    list(commit = "invented-head", working_tree_clean = TRUE),
    percent_coverage = synthetic_percent, provenance_pass_fn = provenance_pass)
  clean_below_result <- run_readiness(coverage = clean_below_threshold)
  stopifnot(identical(clean_below_threshold$status, "not_verified"),
    identical(clean_below_threshold$pass, FALSE),
    identical(clean_below_threshold$value, 50),
    identical(clean_below_result$coverage_value, 50),
    identical(clean_below_result$criteria$status[
      clean_below_result$criteria$criterion == "Test coverage >= 90%"], "not met"))
  dirty_below_threshold <- coverage_percent_record(
    list(value = synthetic_coverage, error_class = ""),
    list(commit = "invented-head", working_tree_clean = FALSE),
    percent_coverage = synthetic_percent, provenance_pass_fn = provenance_pass)
  dirty_only_result <- run_readiness(coverage = dirty_below_threshold, clean = FALSE)
  stopifnot(run_readiness(extra = encode(dirty_below_threshold))$coverage_ready,
    identical(dirty_only_result$criteria$status[
      dirty_only_result$criteria$criterion == "Test coverage >= 90%"], "not measured"))
  assert_readiness_rejects_statuses(run_readiness, baseline, manual)
  for (value in list(-1, 101, TRUE, "94", c(91, 94), NULL)) {
    altered <- baseline
    altered$value <- value
    stopifnot(!run_readiness(coverage = altered)$coverage_ready)
  }
  for (value in c(0, 90, 100)) {
    altered <- baseline
    altered$value <- value
    stopifnot(identical(run_readiness(coverage = altered)$coverage_ready, value >= 90))
  }
  malformed <- c('{"INVENTED_PRIVATE_MARKER":', '7', 'null', '[]',
    '{"step":["coverage_percent"],"commit":"invented-old"}')
  stopifnot(run_readiness(malformed)$coverage_ready)
  assert_readiness_rejects_malformed_lines(function(line) run_readiness(c(malformed, line)))
  altered <- baseline
  altered$status <- "failed"
  altered$pass <- FALSE
  stopifnot(!run_readiness(encode(altered))$coverage_ready)
  altered$status <- "skipped_by_selection"
  altered["pass"] <- list(NULL)
  stopifnot(run_readiness(encode(altered))$coverage_ready)
  invalid_skip <- altered
  invalid_skip$pass <- "invalid"
  stopifnot(!run_readiness(encode(invalid_skip))$coverage_ready)
  invalid_skip_values <- list(pass = FALSE, working_tree_clean = "true")
  for (field_name in names(invalid_skip_values)) {
    invalid_skip <- altered
    invalid_skip[[field_name]] <- invalid_skip_values[[field_name]]
    stopifnot(!run_readiness(encode(invalid_skip))$coverage_ready)
  }
  altered$status <- "failed"
  altered$commit <- "invented-old"
  stopifnot(run_readiness(encode(altered))$coverage_ready,
    !run_readiness(clean = FALSE)$coverage_ready)
  for (line in c(
      '{"diagnostic":{"commit":"invented-head"},"step":"coverage_percent","commit":"invented-old","status":"failed","status":"completed"}',
      '{"step":"coverage_percent","commit":"invented-old","unfinished":')) {
    stopifnot(run_readiness(line)$coverage_ready)
  }
  for (ending in c('"commit":', '"commit":"invented-head')) {
    line <- paste0('{"step":"coverage_percent","commit":"invented-old",', ending)
    stopifnot(!run_readiness(line)$coverage_ready)
  }
  for (flag in list(FALSE, 1, "true", NULL)) {
    altered <- baseline
    altered$working_tree_clean <- flag
    expected_ready <- identical(flag, FALSE)
    stopifnot(identical(run_readiness(encode(altered))$coverage_ready, expected_ready))
    altered <- baseline
    altered$pass <- flag
    stopifnot(!run_readiness(encode(altered))$coverage_ready)
  }
  malformed_current_commit <-
    '{"step":"coverage_percent","commit":false "invented-old"}'
  malformed_known_stale <-
    '{"step":"coverage_percent","commit":"invented-old","unfinished":'
  malformed_partial_stale <-
    '{"step":"ropensci_manual_subset","commit":"invented-old","status":'
  truncated_terminal_step <- '{"commit":"invented-head","step":"coverage_percent"'
  truncated_terminal_stale_commit <-
    '{"step":"coverage_percent","commit":"invented-old"'
  ambiguous_stale_commit <- paste0(
    '{"step":"coverage_percent","commit":"invented-old",',
    '"commit":"invented-head","unfinished":')
  ambiguous_skip_commit <- paste0(
    '{"step":"coverage_percent","status":"skipped_by_selection",',
    '"pass":null,"working_tree_clean":true,"commit":"invented-head",',
    '"commit":"invented-old","unfinished":')
  malformed_unidentifiable <-
    '{"step":["coverage_percent","pkgcheck"],"commit":"invented-head"'
  stopifnot(!run_readiness(malformed_current_commit)$coverage_ready,
    run_readiness(malformed_known_stale)$coverage_ready,
    run_readiness(malformed_partial_stale)$coverage_ready,
    !run_readiness(truncated_terminal_step)$coverage_ready,
    !run_readiness(truncated_terminal_stale_commit)$coverage_ready,
    !run_readiness(ambiguous_stale_commit)$coverage_ready,
    !run_readiness(ambiguous_skip_commit)$coverage_ready,
    run_readiness(malformed_unidentifiable)$coverage_ready)
  stale_partial <- parse_quality_line(malformed_partial_stale)[[1L]]
  ambiguous_skip <- parse_quality_line(ambiguous_skip_commit)[[1L]]
  stopifnot(!quality_evidence_should_apply(stale_partial, "invented-head"),
    is.null(ambiguous_skip$commit), quality_evidence_should_apply(ambiguous_skip, "invented-head"))
  malformed_step_result <- run_readiness(truncated_terminal_step)
  stopifnot(!malformed_step_result$coverage_ready,
    malformed_step_result$check_pass("cyclocomp_linter(15)"))
  nested_gate_diagnostic <- paste0(
    '{"step":"pkgcheck","commit":"invented-head",',
    '"diagnostic":{"step":"coverage_percent"}]}')
  nested_result <- run_readiness(nested_gate_diagnostic)
  stopifnot(nested_result$coverage_ready,
    nested_result$check_pass("cyclocomp_linter(15)"))
  array_step_one <- '{"step":["coverage_percent"],"commit":"invented-head"}'
  array_step_two <- '{"step":["coverage_percent","pkgcheck"],"commit":"invented-head"}'
  array_result <- run_readiness(c(array_step_one, array_step_two))
  stopifnot(array_result$coverage_ready, array_result$pkgcheck_pass)
  skipped_dirty <- baseline
  skipped_dirty$status <- "skipped_by_selection"
  skipped_dirty["pass"] <- list(NULL)
  skipped_dirty$working_tree_clean <- FALSE
  stopifnot(run_readiness(extra = encode(skipped_dirty))$coverage_ready)
  dirty_unverified <- baseline
  dirty_unverified$status <- "not_verified"
  dirty_unverified["pass"] <- list(NULL)
  dirty_unverified$provenance <- "nested_unverified"
  dirty_unverified$working_tree_clean <- FALSE
  dirty_unverified$value <- 100
  dirty_result <- run_readiness(extra = encode(dirty_unverified))
  stopifnot(dirty_result$coverage_ready, identical(dirty_result$coverage_value, 94))
  nul_receipt <- baseline
  nul_line <- charToRaw(encode(nul_receipt))
  nul_record <- run_readiness(extra_raw = c(nul_line, as.raw(0), charToRaw("junk\n")))
  stopifnot(!nul_record$coverage_ready)
  dirty_failure <- baseline
  dirty_failure$status <- "failed"
  dirty_failure$pass <- FALSE
  dirty_failure$working_tree_clean <- FALSE
  stopifnot(run_readiness(extra = encode(dirty_failure))$coverage_ready)
  contradictory_provenance <- baseline
  contradictory_provenance$provenance <- "nested_unverified"
  stopifnot(!run_readiness(coverage = contradictory_provenance)$coverage_ready)
})

cat("Probe-helper tests passed.\n")
