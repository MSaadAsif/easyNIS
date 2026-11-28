nis_owned_temp_path <- function(prefix, parent) {
  # Keep the path canonical before creation, including for a drive root on Windows.
  paste0(sub("/$", "", parent), "/", basename(tempfile(prefix, tmpdir = parent)))
}

nis_create_owned_directory <- function(prefix, parent) {
  path <- nis_owned_temp_path(prefix, parent)
  if (dir.create(path, mode = "0700", showWarnings = FALSE)) path
}

nis_remove_owned_directory <- function(path) {
  if (dir.exists(path) && identical(normalizePath(path, winslash = "/", mustWork = TRUE), path)) {
    unlink(path, recursive = TRUE)
  }
  invisible(NULL)
}

nis_check_output_target <- function(path) {
  if (file.exists(path)) cli::cli_abort("Output {.path {path}} already exists.")
}

nis_publish_directory <- function(target, prefix, write, call = rlang::caller_call()) {
  temp <- NULL
  on.exit(if (!is.null(temp)) nis_remove_owned_directory(temp), add = TRUE)
  suspendInterrupts({
    temp <- nis_create_owned_directory(prefix, dirname(target))
  })
  if (is.null(temp)) {
    cli::cli_abort("Could not create a temporary sibling of {.path {target}}.", call = call)
  }
  write(temp)
  nis_check_output_target(target)
  if (!suppressWarnings(file.rename(temp, target))) {
    cli::cli_abort("Could not publish {.path {target}}.")
  }
  invisible(target)
}
