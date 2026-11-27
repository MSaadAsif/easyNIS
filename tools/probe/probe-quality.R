#!/usr/bin/env Rscript

root <- normalizePath(".", mustWork = TRUE)
source(file.path("tools", "probe", "probe-modules.R"))
source(file.path("tools", "probe", "provenance.R"))
source(file.path("tools", "probe", "quality-checks.R"))
source(file.path("tools", "probe", "quality-result.R"))
run_dir <- probe_run_directory(probe_workspace(root), "quality")
output <- file.path(run_dir, "quality.jsonl")
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Install jsonlite to write probe output.")
}
run_evidence <- git_evidence()
quarto_command <- Sys.which("quarto")
quarto_pandoc <- if (nzchar(quarto_command)) file.path(dirname(quarto_command), "tools") else ""
if (!nzchar(Sys.getenv("RSTUDIO_PANDOC")) && file.exists(file.path(quarto_pandoc, "pandoc.exe"))) {
  Sys.setenv(RSTUDIO_PANDOC = quarto_pandoc)
}

requested_text <- Sys.getenv("EASYNIS_QUALITY_STEPS", unset = "")
requested_steps <- if (nzchar(requested_text)) strsplit(requested_text, ",", fixed = TRUE)[[1L]] else character()
checks <- run_quality_checks(root, requested_steps)

export_docs <- exported_example_status(root)
exports <- export_docs$exports
examples <- export_docs$has_examples
docs <- list(
  exported_functions = length(exports),
  exports_with_examples = sum(examples),
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
description_fields <- stats::setNames(
  vapply(
    required_fields,
    function(field) {
      any(grepl(paste0("^", field, ":"), description_text))
    },
    logical(1)
  ),
  required_fields
)
checks[["export_arguments"]] <- capture_quality_step(quality_receipt_ids[["export_arguments"]], function() {
  with_verified_source(root, function(root, package) {
    exports <- getNamespaceExports(package)
    stats::setNames(
      lapply(exports, function(name) {
        names(formals(getExportedValue(package, name)))
      }),
      exports
    )
  })
})
exported_args <- checks$export_arguments$value
if (inherits(exported_args, "error")) {
  exported_args <- stats::setNames(rep(list(character()), length(exports)), exports)
}
exported_args <- exported_args[exports]
data_first_exceptions <- names(exported_args)[
  !vapply(
    exported_args,
    function(args) {
      length(args) > 0L && args[[1L]] %in% c(".data", "data", "x", "design", "path", "file")
    },
    logical(1)
  )
]
cli_calls <- grep("cli::cli_(abort|warn|inform|bullets)", source_text, value = TRUE)
test_files <- list.files(file.path(root, "tests/testthat"), pattern = "[.]R$", full.names = TRUE)
test_text <- paste(unlist(lapply(test_files, readLines, warn = FALSE)), collapse = "\n")
tests_per_export <- stats::setNames(
  vapply(exports, function(name) grepl(name, test_text, fixed = TRUE), logical(1)),
  exports
)
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
manual_guide_pass <- with(
  checklist,
  all(required_description_fields) &&
    description_fields &&
    news &&
    citation &&
    codemeta &&
    examples_for_every_export &&
    exports_mentioned_in_tests &&
    length(print_or_cat_source_hits) == 0L &&
    cli_calls_found > 0L &&
    nis_prefix_consistent &&
    identical(exports_without_data_first_argument, "nis_example")
)
run_evidence$working_tree_clean <- isTRUE(run_evidence$working_tree_clean) &&
  identical(run_evidence, git_evidence())
records <- lapply(checks, quality_record, evidence = run_evidence)
records[[length(records) + 1L]] <- list(
  step = quality_receipt_ids[["export_documentation"]],
  status = "completed",
  pass = all(examples),
  commit = run_evidence$commit,
  working_tree_clean = run_evidence$working_tree_clean,
  evidence = docs
)
records[[length(records) + 1L]] <- list(
  step = quality_receipt_ids[["guide"]],
  status = if (manual_guide_pass) "completed" else "partial",
  pass = manual_guide_pass,
  commit = run_evidence$commit,
  working_tree_clean = run_evidence$working_tree_clean,
  evidence = checklist
)
coverage_check <- checks$coverage
coverage_record <- coverage_percent_record(coverage_check, run_evidence, covr::percent_coverage)
if (!is.null(coverage_record)) {
  records[[length(records) + 1L]] <- coverage_record
}
lines <- vapply(records, jsonlite::toJSON, character(1), auto_unbox = TRUE, null = "null", na = "null")
writeLines(lines, output, useBytes = TRUE)
write_private_quality_diagnostics(run_dir, checks, records)
failed <- vapply(records, function(record) identical(record$pass, FALSE), logical(1))
failed_steps <- unique(vapply(records[failed], `[[`, character(1), "step"))
if (length(failed_steps)) {
  cat(paste(failed_steps, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
