#!/usr/bin/env Rscript

root <- normalizePath(".", mustWork = TRUE)
source(file.path("tools", "probe", "helpers.R"))
source(file.path("tools", "probe", "provenance.R"))
main_repo <- find_main_repo(root)
read_main_renviron(main_repo)
loop_dir <- Sys.getenv("EASYNIS_LOOP_DIR", unset = file.path(main_repo, "local", "loop"))
loop_dir <- resolve_loop_dir(main_repo, loop_dir)
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S")
run_dir <- file.path(loop_dir, stamp)
dir.create(run_dir, recursive = TRUE)
output <- file.path(run_dir, "quality.jsonl")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install jsonlite to write probe output.")
run_evidence <- git_evidence()
quarto_command <- Sys.which("quarto")
quarto_pandoc <- if (nzchar(quarto_command)) file.path(dirname(quarto_command), "tools") else ""
if (!nzchar(Sys.getenv("RSTUDIO_PANDOC")) && file.exists(file.path(quarto_pandoc, "pandoc.exe"))) {
  Sys.setenv(RSTUDIO_PANDOC = quarto_pandoc)
}

requested_text <- Sys.getenv("EASYNIS_QUALITY_STEPS", unset = "")
requested_steps <- if (nzchar(requested_text)) strsplit(requested_text, ",", fixed = TRUE)[[1L]] else character()
step_keys <- c("as_cran", "lintr", "cyclocomp", "namespace_complexity",
  "coverage", "goodpractice", "pkgcheck", "pkgdown")
unknown_steps <- setdiff(requested_steps, step_keys)
if (length(unknown_steps)) stop("Unknown EASYNIS_QUALITY_STEPS: ", paste(unknown_steps, collapse = ", "))
run_step <- function(key, name, fn) {
  if (length(requested_steps) && !key %in% requested_steps) {
    return(list(name = name, pass = NA, error_class = "", error = "",
      warnings = "", elapsed_seconds = 0, value = "skipped_by_selection"))
  }
  capture_quality_step(name, fn)
}

checks <- list()
checks[["R CMD check --as-cran"]] <- run_step("as_cran", "R CMD check --as-cran", function() {
  devtools::check(document = FALSE, args = c("--as-cran", "--no-manual"), error_on = "never")
})
checks[["lintr"]] <- run_step("lintr", "lintr", function() lintr::lint_package(root))
checks[["cyclocomp"]] <- run_step("cyclocomp", "cyclocomp_linter(15)", function() {
  lintr::lint_package(root, linters = list(cyclocomp = lintr::cyclocomp_linter(15)))
})
checks[["namespace_complexity"]] <- run_step("namespace_complexity",
  "installed_namespace_complexity", function() {
    with_verified_source(root, function(root, package) cyclocomp::cyclocomp_package(package))
  })
checks[["coverage"]] <- run_step("coverage", "covr", function() {
  covr::package_coverage(root, quiet = TRUE)
})
checks[["goodpractice"]] <- run_step("goodpractice", "goodpractice", function() {
  if (!requireNamespace("goodpractice", quietly = TRUE)) return("not installed")
  with_verified_source(root, function(root, package) goodpractice::gp(root))
})
checks[["pkgcheck"]] <- run_step("pkgcheck", "pkgcheck", function() {
  if (!requireNamespace("pkgcheck", quietly = TRUE)) return("not installed")
  with_verified_source(root, function(root, package) pkgcheck::pkgcheck(root))
})
checks[["pkgdown"]] <- run_step("pkgdown", "pkgdown::check_pkgdown", function() {
  if (!requireNamespace("pkgdown", quietly = TRUE)) return("not installed")
  pkgdown::check_pkgdown(root)
})

pkgcheck_pass <- function(value) {
  # No published aggregate pass API; retain known nested failures only.
  if (!inherits(value, "pkgcheck")) return(NA)
  if (identical(goodpractice_pass(value$goodpractice), FALSE)) return(FALSE)
  NA
}
export_docs <- exported_example_status(root)
exports <- export_docs$exports
examples <- export_docs$has_examples
docs <- list(
  exported_functions = length(exports), exports_with_examples = sum(examples),
  exports_without_examples = names(examples)[!examples],
  description_url = any(grepl("^URL:", readLines(file.path(root, "DESCRIPTION"), warn = FALSE))),
  description_bugreports = any(grepl("^BugReports:", readLines(file.path(root, "DESCRIPTION"), warn = FALSE))),
  news_file = file.exists(file.path(root, "NEWS.md")) || file.exists(file.path(root, "NEWS")),
  citation_file = file.exists(file.path(root, "inst", "CITATION")) || file.exists(file.path(root, "CITATION")),
  codemeta_file = file.exists(file.path(root, "codemeta.json")),
  tools_in_buildignore = any(startsWith(trimws(readLines(file.path(root, ".Rbuildignore"), warn = FALSE)), "^tools"))
)

source_files <- list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)
source_text <- unlist(lapply(source_files, readLines, warn = FALSE))
print_cat_hits <- grep("\\b(?:print|cat)\\s*\\(", source_text, value = TRUE, perl = TRUE)
description_text <- readLines(file.path(root, "DESCRIPTION"), warn = FALSE)
required_fields <- c("Package", "Title", "Version", "Authors@R", "Description", "License")
description_fields <- stats::setNames(vapply(required_fields, function(field) {
  any(grepl(paste0("^", field, ":"), description_text))
}, logical(1)), required_fields)
checks[["export_arguments"]] <- capture_quality_step("export_arguments", function() {
  with_verified_source(root, function(root, package) {
    exports <- getNamespaceExports(package)
    stats::setNames(lapply(exports, function(name) {
      names(formals(getExportedValue(package, name)))
    }), exports)
  })
})
exported_args <- checks$export_arguments$value
if (inherits(exported_args, "error")) exported_args <- stats::setNames(rep(list(character()), length(exports)), exports)
exported_args <- exported_args[exports]
data_first_exceptions <- names(exported_args)[!vapply(exported_args, function(args) {
  length(args) > 0L && args[[1L]] %in% c(".data", "data", "x", "design", "path", "file")
}, logical(1))]
cli_calls <- grep("cli::cli_(abort|warn|inform|bullets)", source_text, value = TRUE)
test_files <- list.files(file.path(root, "tests/testthat"), pattern = "[.]R$", full.names = TRUE)
test_text <- paste(unlist(lapply(test_files, readLines, warn = FALSE)), collapse = "\n")
tests_per_export <- stats::setNames(vapply(exports, function(name) grepl(name, test_text, fixed = TRUE), logical(1)), exports)
checklist <- list(
  description_fields = docs$description_url && docs$description_bugreports,
  required_description_fields = description_fields,
  news = docs$news_file,
  citation = docs$citation_file,
  codemeta = docs$codemeta_file,
  examples_for_every_export = all(examples),
  exports_mentioned_in_tests = all(tests_per_export),
  exports_without_test_mentions = names(tests_per_export)[!tests_per_export],
  print_or_cat_source_hits = print_cat_hits,
  cli_imported_for_messages = any(grepl("^\\s*cli,?$", description_text)),
  cli_calls_found = length(cli_calls),
  nis_prefix_consistent = all(grepl("^nis_", exports)),
  exports_without_data_first_argument = data_first_exceptions
)
manual_guide_pass <- all(description_fields) && docs$description_url &&
  docs$description_bugreports && docs$news_file && docs$citation_file &&
  docs$codemeta_file && all(examples) && all(tests_per_export) &&
  length(print_cat_hits) == 0L && length(cli_calls) > 0L &&
  all(grepl("^nis_", exports)) && identical(data_first_exceptions, "nis_example")
check_counts_for <- function(value) {
  has_counts <- is.list(value) && all(c("errors", "warnings", "notes") %in% names(value))
  if (inherits(value, "rcmdcheck") || has_counts) return(check_result_counts(value))
  NULL
}
quality_step_pass <- function(x, counts) {
  value <- x$value
  if (identical(value, "skipped_by_selection") || identical(value, "not installed")) return(NA)
  if (inherits(value, "error")) return(FALSE)
  if (x$name == "installed_namespace_complexity") return(namespace_complexity_pass(value))
  if (x$name %in% c("lintr", "cyclocomp_linter(15)")) return(x$pass && length(value) == 0L)
  if (!is.null(counts)) return(x$pass && all(counts == 0L))
  if (inherits(value, "coverage")) return(x$pass && covr::percent_coverage(value) >= 90)
  if (x$name == "goodpractice") return(goodpractice_pass(value))
  if (x$name == "pkgcheck") return(pkgcheck_pass(value))
  isTRUE(x$pass)
}
quality_step_status <- function(value, passed) {
  if (identical(value, "skipped_by_selection")) return("skipped_by_selection")
  if (identical(value, "not installed")) return("skipped_not_installed")
  if (inherits(value, "error")) return("failed")
  if (is.na(passed)) return("not_verified")
  "completed"
}
lint_detail <- function(value) {
  lint_table <- tryCatch(as.data.frame(value), error = function(e) NULL)
  columns <- c("filename", "line_number", "column_number", "message")
  if (!is.data.frame(lint_table) || !all(columns %in% names(lint_table))) {
    return(paste(capture.output(print(value)), collapse = " | "))
  }
  file <- gsub("^.*[/\\\\](R|tests)[/\\\\]", "\\1/", lint_table$filename, perl = TRUE)
  entries <- paste0(file, ":", lint_table$line_number, ":", lint_table$column_number,
    ": ", lint_table$message)
  paste(vapply(entries, redact_paths, character(1)), collapse = " | ")
}
quality_step_detail <- function(x, counts, passed) {
  value <- x$value
  if (inherits(value, "error")) return(x$error)
  if (x$name %in% c("goodpractice", "pkgcheck")) {
    return(quality_public_detail(x$name, passed))
  }
  if (!is.null(counts)) return(paste(names(counts), counts, collapse = " | "))
  if (x$name %in% c("lintr", "cyclocomp_linter(15)")) return(lint_detail(value))
  ""
}
quality_record <- function(x, evidence) {
  value <- x$value
  counts <- check_counts_for(value)
  provenance <- quality_provenance(x$name)
  passed <- provenance_pass(quality_step_pass(x, counts), provenance)
  detail <- quality_step_detail(x, counts, passed)
  if (!x$name %in% c("lintr", "cyclocomp_linter(15)")) detail <- redact_paths(detail)
  record <- quality_receipt_record(x, evidence, quality_step_status(value, passed), passed, detail)
  record$provenance <- if (inherits(value, "error")) "failed" else if (
    identical(value, "skipped_by_selection") || identical(value, "not installed")
  ) "not_measured" else provenance
  record
}
records <- lapply(checks, quality_record, evidence = run_evidence)
records[[length(records) + 1L]] <- list(step = "export_documentation", status = "completed",
  pass = all(examples), commit = run_evidence$commit,
  working_tree_clean = run_evidence$working_tree_clean, evidence = docs)
records[[length(records) + 1L]] <- list(step = "ropensci_manual_subset",
  status = if (manual_guide_pass) "completed" else "partial", pass = manual_guide_pass,
  commit = run_evidence$commit, working_tree_clean = run_evidence$working_tree_clean,
  evidence = checklist)
coverage_check <- checks$coverage
coverage <- coverage_check$value
if (identical(coverage, "skipped_by_selection")) {
  coverage_record <- NULL
} else if (inherits(coverage, "coverage")) {
  cov <- covr::percent_coverage(coverage)
  coverage_record <- list(step = "coverage_percent", status = "not_verified",
    pass = provenance_pass(cov >= 90, "nested_unverified"), provenance = "nested_unverified",
    value = cov, commit = run_evidence$commit, working_tree_clean = run_evidence$working_tree_clean)
} else {
  coverage_record <- list(step = "coverage_percent", status = "failed", pass = FALSE,
    value = NA_real_, error_class = coverage_check$error_class,
    commit = run_evidence$commit, working_tree_clean = run_evidence$working_tree_clean)
}
if (!is.null(coverage_record)) records[[length(records) + 1L]] <- coverage_record
lines <- vapply(records, jsonlite::toJSON, character(1), auto_unbox = TRUE, null = "null", na = "null")
writeLines(lines, output, useBytes = TRUE)
write_private_quality_diagnostics(run_dir, checks, records)
failed <- vapply(records, function(record) identical(record$pass, FALSE), logical(1))
failed_steps <- unique(vapply(records[failed], `[[`, character(1), "step"))
if (length(failed_steps)) {
  cat(paste(failed_steps, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
