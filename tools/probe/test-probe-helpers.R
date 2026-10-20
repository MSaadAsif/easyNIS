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
  redact_public_diagnostic("1 cohort row has missing design fields") == "[diagnostic text redacted]",
  redact_public_diagnostic("10 cohort rows have missing design fields") == "[diagnostic text redacted]",
  quality_evidence_valid(list(commit = "synthetic", working_tree_clean = TRUE), "synthetic", TRUE),
  !quality_evidence_valid(list(commit = "synthetic", working_tree_clean = FALSE), "synthetic", TRUE),
  !quality_evidence_valid(list(commit = "other", working_tree_clean = TRUE), "synthetic", TRUE),
  is.na(coverage_percent_value(list(value = NULL))),
  is.na(coverage_percent_value(list(value = NA_real_))),
  identical(coverage_percent_value(list(value = 92)), 92))

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
  write_receipt <- function(studies) {
    jsonlite::write_json(list(commit = current_commit,
      verified_at = "2026-10-20T12:00:00Z", studies = studies), receipt_path, auto_unbox = TRUE)
    study_verification_ready(receipt_path, current_commit)
  }
  passed_studies <- lapply(c("synthetic-a", "synthetic-b", "synthetic-c"), function(id) {
    list(id = id, pass = TRUE, tolerance = 0.05)
  })
  stopifnot(write_receipt(passed_studies))
  stopifnot(!study_verification_ready(receipt_path, "different-commit"))
  jsonlite::write_json(list(commit = current_commit, studies = passed_studies), receipt_path,
    auto_unbox = TRUE)
  stopifnot(!study_verification_ready(receipt_path, current_commit))
  stopifnot(!write_receipt(passed_studies[-1L]))
  failed_studies <- passed_studies
  failed_studies[[2L]]$pass <- FALSE
  stopifnot(!write_receipt(failed_studies))
  duplicate_studies <- passed_studies
  duplicate_studies[[3L]]$id <- duplicate_studies[[2L]]$id
  stopifnot(!write_receipt(duplicate_studies))
  vague_studies <- passed_studies
  vague_studies[[1L]]$tolerance <- "not specified"
  stopifnot(!write_receipt(vague_studies))
  stopifnot(!write_receipt("synthetic"),
    !write_receipt(list(1, 2, 3)))

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

cat("Probe-helper tests passed.\n")
