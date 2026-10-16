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
    stop("path must be one non-empty directory path.", call. = FALSE)
  }

  path <- normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
  link <- Sys.readlink(path)
  if (file.exists(path) || dir.exists(path) ||
      (length(link) == 1L && !is.na(link) && nzchar(link))) {
    stop("The study path already exists.", call. = FALSE)
  }

  parent <- dirname(path)
  if (!dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create the parent directory for the study.", call. = FALSE)
  }
  if (file.exists(path) || dir.exists(path) || !dir.create(path, showWarnings = FALSE)) {
    stop("Could not create the study directory because the path is unavailable.",
         call. = FALSE)
  }

  template <- system.file("templates", "nis-study", package = "easyNIS")
  if (!nzchar(template) || !dir.exists(template)) {
    unlink(path, recursive = TRUE)
    stop("The packaged NIS study template is unavailable.", call. = FALSE)
  }

  files <- list.files(template, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (!length(files) || any(dir.exists(files)) ||
      !all(file.copy(files, path, overwrite = FALSE))) {
    unlink(path, recursive = TRUE)
    stop("Could not copy the packaged NIS study template.", call. = FALSE)
  }

  path
}
