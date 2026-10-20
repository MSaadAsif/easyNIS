#!/usr/bin/env Rscript

root <- normalizePath(".", mustWork = TRUE)
source(file.path("tools", "probe", "helpers.R"))
main_repo <- find_main_repo(root)
read_main_renviron(main_repo)
loop_dir <- Sys.getenv("EASYNIS_LOOP_DIR", unset = file.path(main_repo, "local", "loop"))
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S")
run_dir <- file.path(loop_dir, stamp)
dir.create(run_dir, recursive = TRUE)
output <- file.path(run_dir, "quality.jsonl")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install jsonlite to write probe output.")
devtools::load_all(root, quiet = TRUE)
quarto_command <- Sys.which("quarto")
quarto_pandoc <- if (nzchar(quarto_command)) file.path(dirname(quarto_command), "tools") else ""
if (!nzchar(Sys.getenv("RSTUDIO_PANDOC")) && file.exists(file.path(quarto_pandoc, "pandoc.exe"))) {
  Sys.setenv(RSTUDIO_PANDOC = quarto_pandoc)
}

safe <- function(name, fn) {
  started <- proc.time()[["elapsed"]]
  warnings <- character()
  value <- tryCatch(withCallingHandlers(fn(),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }),
    error = identity)
  list(name = name, pass = !inherits(value, "error"),
    error_class = if (inherits(value, "error")) class(value)[[1L]] else "",
    error = if (inherits(value, "error")) redact_paths(conditionMessage(value)) else "",
    warnings = paste(redact_paths(warnings), collapse = " | "),
    elapsed_seconds = unname(proc.time()[["elapsed"]] - started), value = value)
}
requested_text <- Sys.getenv("EASYNIS_QUALITY_STEPS", unset = "")
requested_steps <- if (nzchar(requested_text)) strsplit(requested_text, ",", fixed = TRUE)[[1L]] else character()
run_step <- function(key, name, fn) {
  if (length(requested_steps) && !key %in% requested_steps) {
    return(list(name = name, pass = NA, error_class = "", error = "",
      warnings = "", elapsed_seconds = 0, value = "skipped_by_selection"))
  }
  safe(name, fn)
}

checks <- list()
checks[["R CMD check --as-cran"]] <- run_step("as_cran", "R CMD check --as-cran", function() {
  devtools::check(document = FALSE, args = c("--as-cran", "--no-manual"), error_on = "never")
})
checks[["lintr"]] <- run_step("lintr", "lintr", function() lintr::lint_package(root))
checks[["cyclocomp"]] <- run_step("cyclocomp", "cyclocomp_linter(15)", function() {
  lintr::lint_package(root, linters = list(cyclocomp = lintr::cyclocomp_linter(15)))
})
checks[["coverage"]] <- run_step("coverage", "covr", function() {
  covr::package_coverage(root, quiet = TRUE)
})
checks[["goodpractice"]] <- run_step("goodpractice", "goodpractice", function() {
  if (!requireNamespace("goodpractice", quietly = TRUE)) return("not installed")
  goodpractice::gp(root)
})
checks[["pkgcheck"]] <- run_step("pkgcheck", "pkgcheck", function() {
  if (!requireNamespace("pkgcheck", quietly = TRUE)) return("not installed")
  pkgcheck::pkgcheck(root)
})
checks[["pkgdown"]] <- run_step("pkgdown", "pkgdown::check_pkgdown", function() {
  if (!requireNamespace("pkgdown", quietly = TRUE)) return("not installed")
  pkgdown::check_pkgdown(root)
})

exports <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
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
exported_args <- lapply(exports, function(name) {
  tryCatch(names(formals(getExportedValue("easyNIS", name))), error = function(e) character())
})
names(exported_args) <- exports
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
records <- lapply(checks, function(x) {
  value <- x$value
  status <- if (identical(value, "skipped_by_selection")) "skipped_by_selection" else if (identical(value, "not installed")) "skipped_not_installed" else if (x$pass) "completed" else "failed"
  passed <- x$pass
  if (x$name %in% c("lintr", "cyclocomp_linter(15)")) passed <- x$pass && length(value) == 0L
  check_counts <- if (inherits(value, "rcmdcheck") ||
    is.list(value) && all(c("errors", "warnings", "notes") %in% names(value))) {
      check_result_counts(value)
    } else NULL
  if (!is.null(check_counts)) passed <- x$pass && all(check_counts == 0L)
  if (inherits(value, "coverage")) passed <- x$pass && covr::percent_coverage(value) >= 90
  if (identical(value, "not installed") || identical(value, "skipped_by_selection")) passed <- NA
  detail <- if (inherits(value, "error")) x$error else if (!is.null(check_counts))
    paste(names(check_counts), check_counts, collapse = " | ") else if (x$name %in% c("lintr", "cyclocomp_linter(15)")) {
      lint_table <- tryCatch(as.data.frame(value), error = function(e) NULL)
      if (is.data.frame(lint_table) && all(c("filename", "line_number", "column_number", "message") %in% names(lint_table))) {
        file <- gsub("^.*[/\\\\](R|tests)[/\\\\]", "\\1/", lint_table$filename, perl = TRUE)
        paste0(file, ":", lint_table$line_number, ":", lint_table$column_number,
          ": ", lint_table$message, collapse = " | ")
      } else paste(capture.output(print(value)), collapse = " | ")
    } else ""
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
    stderr = FALSE)[[1L]], error = function(e) NA_character_)
  list(step = x$name, status = status, pass = passed, error_class = x$error_class,
    result_class = paste(class(value), collapse = ","), commit = commit,
    detail = redact_paths(detail),
    warnings = x$warnings, elapsed_seconds = x$elapsed_seconds)
})
commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
  stderr = FALSE)[[1L]], error = function(e) NA_character_)
records[[length(records) + 1L]] <- list(step = "export_documentation", status = "completed",
  pass = all(examples), commit = commit, evidence = docs)
records[[length(records) + 1L]] <- list(step = "ropensci_manual_subset",
  status = if (manual_guide_pass) "completed" else "partial", pass = manual_guide_pass,
  commit = commit, evidence = checklist)
coverage_check <- checks$coverage
coverage <- coverage_check$value
if (identical(coverage, "skipped_by_selection")) {
  coverage_record <- NULL
} else if (inherits(coverage, "coverage")) {
  cov <- covr::percent_coverage(coverage)
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
    stderr = FALSE)[[1L]], error = function(e) NA_character_)
  coverage_record <- list(step = "coverage_percent", status = "completed", pass = cov >= 90,
    value = cov, commit = commit)
} else {
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
    stderr = FALSE)[[1L]], error = function(e) NA_character_)
  coverage_record <- list(step = "coverage_percent", status = "failed", pass = FALSE,
    error_class = coverage_check$error_class, commit = commit)
}
if (!is.null(coverage_record)) records[[length(records) + 1L]] <- coverage_record
lines <- vapply(records, jsonlite::toJSON, character(1), auto_unbox = TRUE, null = "null", na = "null")
writeLines(lines, output, useBytes = TRUE)
cat(sprintf("Quality results written to %s\n", output))
print(docs)
print(checklist)
