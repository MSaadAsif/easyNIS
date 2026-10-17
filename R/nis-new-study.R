#' Create a new NIS study folder
#'
#' Copy the packaged Quarto study template to a new directory. The destination
#' must not already exist.
#'
#' @param path A new local directory path for the study.
#' @return The normalized path to the created study directory.
#' @export
#' @examples
#' study_path <- file.path(tempdir(), "nis-study-example")
#' if (!dir.exists(study_path)) nis_new_study(study_path)
nis_new_study <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(trimws(path))) {
    cli::cli_abort("`path` must be one non-empty directory path.")
  }

  path <- normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
  link <- Sys.readlink(path)
  if (file.exists(path) || dir.exists(path) ||
      (length(link) == 1L && !is.na(link) && nzchar(link))) {
    cli::cli_abort("The study path already exists.")
  }

  parent <- dirname(path)
  if (!dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
    cli::cli_abort("Could not create the parent directory for the study.")
  }
  if (file.exists(path) || dir.exists(path) || !dir.create(path, showWarnings = FALSE)) {
    cli::cli_abort("Could not create the study directory because the path is unavailable.")
  }

  template <- system.file("templates", "nis-study", package = "easyNIS")
  if (!nzchar(template) || !dir.exists(template)) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("The packaged NIS study template is unavailable.")
  }

  files <- list.files(template, full.names = TRUE, no.. = TRUE)
  if (!length(files) || any(dir.exists(files)) ||
      !all(file.copy(files, path, overwrite = FALSE))) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("Could not copy the packaged NIS study template.")
  }

  if (!file.rename(file.path(path, "gitignore"), file.path(path, ".gitignore"))) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("Could not create the study output `.gitignore`.")
  }

  path
}
