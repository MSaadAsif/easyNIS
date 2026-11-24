verification_run <- function(name, action, packages = character(), source_dir = ".") {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  stopifnot(file.exists("DESCRIPTION"), dir.exists("tools/probe"))
  workspace <- new.env(parent = baseenv())
  sys.source("tools/probe/workspace.R", envir = workspace)
  loop <- workspace$resolve_loop_dir(root, file.path(root, "local", "loop"))
  evidence_root <- workspace$resolve_loop_dir(root, file.path(loop, "verification"))
  evidence <- normalizePath(workspace$probe_run_directory(evidence_root, name),
    winslash = "/", mustWork = TRUE)
  cat("EVIDENCE ", evidence, "\n", sep = "")
  transcript <- file(file.path(evidence, "run.txt"), open = "wt", encoding = "UTF-8")
  sink(transcript, split = TRUE)
  on.exit({ sink(); close(transcript) }, add = TRUE, after = TRUE)

  source_dir <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
  session_tmp <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  scratch <- tempfile("easynis-verification-", tmpdir = session_tmp)
  stopifnot(dir.create(scratch, mode = "0700"))
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  on.exit({
    gc()
    if (dir.exists(scratch)) {
      stopifnot(identical(dirname(scratch), session_tmp),
        identical(normalizePath(scratch, winslash = "/", mustWork = TRUE), scratch))
      unlink(scratch, recursive = TRUE)
    }
    if (file.exists(scratch)) stop("Verification scratch could not be removed.")
    cat("CLEANUP PASS ", scratch, "\n", sep = "")
  }, add = TRUE, after = FALSE)

  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  args <- shQuote(c(script, commandArgs(trailingOnly = TRUE)))
  cat("COMMAND Rscript --vanilla ", paste(args, collapse = " "), "\n", sep = "")
  cat("SOURCE ", source_dir, "\n", sep = "")
  cat("CHECKOUT HEAD ", system2("git", c("rev-parse", "HEAD"), stdout = TRUE), "\n", sep = "")
  cat("CHECKOUT STATUS\n")
  print(system2("git", c("status", "--porcelain"), stdout = TRUE))
  cat("R ", R.version.string, " / ", R.version$platform, "\n", sep = "")
  cat("LOCALE ", Sys.getlocale("LC_CTYPE"), "\n", sep = "")
  inputs <- c("DESCRIPTION", "NAMESPACE", paste0("R/", list.files(file.path(source_dir, "R"))))
  hashes <- tools::md5sum(file.path(source_dir, inputs))
  writeLines(paste(unname(hashes), inputs), file.path(evidence, "input-hashes.txt"))
  cat("SCRATCH ", scratch, "\n", sep = "")

  tryCatch(withCallingHandlers({
    install_verification_package(source_dir, scratch, evidence, packages)
    action(scratch, evidence)
    cat("RESULT PASS\n")
  }, message = function(condition) {
    cat("MESSAGE ", conditionMessage(condition), "\n", sep = "")
    invokeRestart("muffleMessage")
  }, warning = function(condition) {
    cat("WARNING ", conditionMessage(condition), "\n", sep = "")
  }), error = function(condition) {
    cat("RESULT FAIL ", conditionMessage(condition), "\n", sep = "")
    stop(condition)
  })
  invisible(evidence)
}

verification_dependencies <- function(source_dir, packages = character()) {
  imports_field <- read.dcf(file.path(source_dir, "DESCRIPTION"), fields = "Imports")[1L, 1L]
  imports <- trimws(sub("\\(.*", "", strsplit(imports_field, ",", fixed = TRUE)[[1L]]))
  dependencies <- unique(c(imports, packages))
  missing <- dependencies[!vapply(dependencies, function(pkg) {
    nzchar(system.file(package = pkg))
  }, logical(1))]
  if (length(missing)) stop("Install required R packages: ", paste(missing, collapse = ", "))
  vapply(dependencies, function(pkg) as.character(utils::packageVersion(pkg)), character(1))
}

install_verification_package <- function(source_dir, scratch, evidence, packages) {
  lib <- file.path(scratch, "library")
  stopifnot(dir.create(lib))
  dependencies <- verification_dependencies(source_dir, packages)
  r <- file.path(R.home("bin"), "R")
  install_log <- file.path(evidence, "install.txt")
  args <- c("CMD", "INSTALL", "--no-multiarch", "-l", shQuote(lib), shQuote(source_dir))
  cat("INSTALL ", paste(c(shQuote(r), args), collapse = " "), "\n", sep = "")
  status <- system2(r, args, stdout = install_log, stderr = install_log)
  if (status != 0L) stop("R CMD INSTALL failed. Read install.txt.")

  .libPaths(c(lib, .libPaths()))
  namespace <- loadNamespace("easyNIS", lib.loc = lib)
  installed <- normalizePath(getNamespaceInfo(namespace, "path"), winslash = "/")
  stopifnot(identical(dirname(installed), normalizePath(lib, winslash = "/")))
  cat("READY easyNIS ", as.character(utils::packageVersion("easyNIS")), "\n", sep = "")
  print(dependencies)
}
