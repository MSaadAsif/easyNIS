find_main_repo <- function(start = ".") {
  start <- normalizePath(start, mustWork = TRUE)
  common_dir <- tryCatch(suppressWarnings(system2("git",
    c("-C", shQuote(start), "rev-parse", "--git-common-dir"), stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  status <- attr(common_dir, "status")
  if (!length(common_dir) || (length(status) && status != 0L)) {
    return(normalizePath(start, mustWork = TRUE))
  }
  common_path <- common_dir[[1L]]
  is_absolute <- grepl("^[A-Za-z]:[/\\\\]", common_path) ||
    startsWith(common_path, "/") || startsWith(common_path, "\\\\")
  if (!is_absolute) {
    common_path <- file.path(start, common_path)
  }
  dirname(normalizePath(common_path, mustWork = TRUE))
}

read_main_renviron <- function(start = ".") {
  path <- file.path(start, ".Renviron")
  if (file.exists(path)) {
    shell_environment <- Sys.getenv()
    shell_environment <- shell_environment[nzchar(shell_environment)]
    readRenviron(path)
    if (length(shell_environment)) do.call(Sys.setenv, as.list(shell_environment))
  }
  invisible(path)
}

path_is_within <- function(path, parent) {
  if (.Platform$OS.type == "windows") {
    path <- tolower(path)
    parent <- tolower(parent)
  }
  identical(path, parent) || startsWith(path, paste0(parent, "/"))
}

canonical_loop_path <- function(path) {
  if (file.exists(path) || dir.exists(path)) {
    return(normalizePath(path, winslash = "/", mustWork = TRUE))
  }
  parent <- dirname(path)
  if (identical(parent, path)) stop("Could not resolve the local loop path.", call. = FALSE)
  parent <- canonical_loop_path(parent)
  component <- basename(path)
  if (component == "..") return(dirname(parent))
  if (component == ".") return(parent)
  file.path(parent, component)
}

resolve_loop_dir <- function(main_repo, requested = Sys.getenv("EASYNIS_LOOP_DIR", unset = "")) {
  main_repo <- normalizePath(main_repo, winslash = "/", mustWork = TRUE)
  expected_root <- file.path(main_repo, "local", "loop")
  if (!nzchar(requested)) requested <- expected_root
  if (!grepl("^(?:[A-Za-z]:[/\\\\]|/|\\\\\\\\)", requested)) {
    requested <- file.path(main_repo, requested)
  }
  candidate <- canonical_loop_path(requested)
  check_location <- function(path) {
    if (!path_is_within(path, expected_root)) {
      stop("EASYNIS_LOOP_DIR must resolve inside the main checkout's ignored local loop directory.",
        call. = FALSE)
    }
    relative <- substring(path, nchar(main_repo) + 2L)
    ignored <- suppressWarnings(system2("git",
      c("-C", shQuote(main_repo), "check-ignore", "--quiet", "--", shQuote(relative)),
      stdout = FALSE, stderr = FALSE))
    if (!identical(ignored, 0L)) {
      stop("The local loop output directory must be ignored by Git.", call. = FALSE)
    }
  }
  check_location(candidate)
  if (!dir.exists(candidate) && !dir.create(candidate, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create the local loop output directory.", call. = FALSE)
  }
  candidate <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  check_location(candidate)
  candidate
}

probe_workspace <- function(root = ".") {
  main_repo <- find_main_repo(root)
  read_main_renviron(main_repo)
  resolve_loop_dir(main_repo)
}

probe_run_directory <- function(loop_dir, producer) {
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%S")
  path <- tempfile(paste0(stamp, "-", producer, "-"), tmpdir = loop_dir)
  if (!dir.create(path)) stop("Could not create a probe run directory.", call. = FALSE)
  path
}
