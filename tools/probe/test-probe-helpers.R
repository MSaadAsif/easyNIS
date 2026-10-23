source(file.path("tools", "probe", "helpers.R"))
source(file.path("tools", "probe", "quality-diagnostics.R"))

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
  redact_public_diagnostic("1 cohort row has missing design fields") == "[diagnostic text redacted]",
  redact_public_diagnostic("10 cohort rows have missing design fields") == "[diagnostic text redacted]",
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
  run_dir <- tempfile("synthetic-quality-run-")
  dir.create(run_dir)
  on.exit(unlink(run_dir, recursive = TRUE))
  synthetic_failure <- "synthetic manual generation failed because a required tool is unavailable"
  synthetic_check <- structure(list(
    goodpractice = list(
      checks = list(),
      rcmdcheck = list(
        errors = synthetic_failure,
        warnings = "synthetic warning",
        notes = character(),
        status = 1L,
        checkdir = "C:/synthetic/check"
      )
    )
  ), class = c("pkgcheck", "list"))

  private_file <- write_private_quality_diagnostics("pkgcheck", synthetic_check,
    failed = TRUE, run_dir = run_dir)
  private_text <- readLines(private_file, warn = FALSE)
  public_summary <- quality_public_diagnostic_summary(synthetic_check)
  public_receipt <- list(
    step = "pkgcheck", status = "completed", pass = FALSE,
    detail = public_summary,
    private_diagnostics = "private/pkgcheck-diagnostics.txt",
    commit = "synthetic-commit", working_tree_clean = TRUE,
    errors = 1L
  )
  public_text <- paste(capture.output(dput(public_receipt)), collapse = "\n")

  stopifnot(grepl(synthetic_failure, paste(private_text, collapse = "\n"), fixed = TRUE),
    grepl("checkdir", paste(private_text, collapse = "\n"), fixed = TRUE),
    !grepl(synthetic_failure, public_text, fixed = TRUE),
    grepl("failed_checks=0; rcmdcheck_errors=1", public_summary, fixed = TRUE),
    !grepl("synthetic", public_summary, fixed = TRUE),
    identical(public_receipt$private_diagnostics, "private/pkgcheck-diagnostics.txt"),
    identical(public_receipt$status, "completed"),
    identical(public_receipt$pass, FALSE), identical(public_receipt$errors, 1L),
    is.null(write_private_quality_diagnostics("pkgcheck", synthetic_check,
      failed = FALSE, run_dir = tempfile("no-output-"))))

  synthetic_gp <- structure(list(
    checks = list(synthetic_check = list(status = FALSE,
      positions = "synthetic source diagnostic")),
    rcmdcheck = list(errors = synthetic_failure, checkdir = "C:/synthetic/check")
  ), class = c("goodPractice", "list"))
  gp_file <- write_private_quality_diagnostics("goodpractice", synthetic_gp,
    failed = TRUE, run_dir = run_dir)
  gp_summary <- quality_public_diagnostic_summary(synthetic_gp)
  stopifnot(grepl("synthetic source diagnostic", paste(readLines(gp_file), collapse = "\n"), fixed = TRUE),
    grepl("failed_checks=1; rcmdcheck_errors=1", gp_summary, fixed = TRUE),
    !grepl("synthetic", gp_summary, fixed = TRUE))

  synthetic_error <- simpleError("synthetic package check process error")
  error_file <- write_private_quality_diagnostics("pkgcheck", synthetic_error,
    failed = TRUE, run_dir = run_dir)
  error_summary <- quality_public_diagnostic_summary(synthetic_error)
  stopifnot(grepl("synthetic package check process error",
    paste(readLines(error_file), collapse = "\n"), fixed = TRUE),
    identical(error_summary, "tool execution failed"),
    !grepl("synthetic", error_summary, fixed = TRUE))
})

cat("Probe-helper tests passed.\n")
