nis_study_valid_path <- function(path) {
  is.character(path) && length(path) == 1L && !is.na(path) && nzchar(trimws(path))
}

nis_study_path_exists <- function(path) {
  link <- Sys.readlink(path)
  file.exists(path) || dir.exists(path) || (length(link) == 1L && !is.na(link) && nzchar(link))
}

nis_study_check_path <- function(path, call) {
  if (!nis_study_valid_path(path)) {
    cli::cli_abort("`path` must be one non-empty directory path.", call = call)
  }

  path <- normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
  if (nis_study_path_exists(path)) {
    cli::cli_abort("The study path already exists.", call = call)
  }
  path
}

nis_study_create_path <- function(path, call) {
  parent <- dirname(path)
  if (
    !dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  ) {
    cli::cli_abort("Could not create the parent directory for the study.", call = call)
  }
  if (nis_study_path_exists(path) || !dir.create(path, showWarnings = FALSE)) {
    cli::cli_abort("Could not create the study directory because the path is unavailable.", call = call)
  }
}

nis_study_copy_template <- function(path, call) {
  template <- system.file("templates", "nis-study", package = "easyNIS")
  if (!nzchar(template) || !dir.exists(template)) {
    cli::cli_abort("The packaged NIS study template is unavailable.", call = call)
  }

  files <- list.files(template, full.names = TRUE, no.. = TRUE)
  if (!length(files) || any(dir.exists(files)) || !all(file.copy(files, path, overwrite = FALSE))) {
    cli::cli_abort("Could not copy the packaged NIS study template.", call = call)
  }

  if (!file.rename(file.path(path, "gitignore"), file.path(path, ".gitignore"))) {
    cli::cli_abort("Could not create the study output `.gitignore`.", call = call)
  }
}

#' Create a Quarto study
#'
#' Create a Quarto project with an editable NIS analysis, methods text,
#' and a disclosure checklist. The example runs on invented discharges
#' until you supply your own data directory.
#'
#' @details Open `analysis.qmd` to edit the cohort, outcomes, and analysis.
#' Render with `quarto render analysis.qmd` from the study directory. With
#' `params.data_path` unset, the report uses [nis_example()]. Set that
#' parameter to the private directory containing your annual Parquet files.
#'
#' Review the rendered methods paragraph and checklist receipt against the
#' study protocol. Review disclosure across the finished report before
#' sharing it.
#'
#' @param path A new local directory path for the study.
#' @return The normalized path to the created study directory.
#' @family study-setup
#' @seealso [Start a Quarto study](https://msaadasif.github.io/easyNIS/articles/study-template.html),
#'   [nis_design_report()] to inspect the fitted sample and [nis_scan_outputs()]
#'   to scan the files you plan to share.
#' @export
#' @examples
#' study_path <- tempfile("nis-study-example-")
#' nis_new_study(study_path)
#' list.files(study_path, all.files = TRUE, no.. = TRUE)
nis_new_study <- function(path) {
  call <- sys.call()
  path <- nis_study_check_path(path, call)
  nis_study_create_path(path, call)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  nis_study_copy_template(path, call)
  destination <- normalizePath(path, winslash = "/", mustWork = TRUE)
  on.exit(NULL, add = FALSE)
  destination
}
