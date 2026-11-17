# Install in a fresh library using R CMD INSTALL, independently of parent state.
# The callback runs only after the effective namespace path has been verified.
with_verified_source <- function(root, fn) {
  callr::r(function(root, fn) {
    library <- tempfile("quality-library-")
    dir.create(library)
    on.exit(unlink(library, recursive = TRUE), add = TRUE)
    package <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Package")[[1L]]
    callr::rcmd("INSTALL", c(paste0("--library=", library), root),
      user_profile = FALSE, system_profile = FALSE, fail_on_status = TRUE)
    expected <- file.path(library, package)
    if (!file.exists(file.path(expected, "DESCRIPTION"))) stop("Installation missing")
    .libPaths(c(library, .libPaths()))
    namespace <- loadNamespace(package, lib.loc = library)
    effective <- getNamespaceInfo(namespace, "path")
    if (!identical(normalizePath(effective), normalizePath(expected))) {
      stop("Effective namespace does not match the isolated installation")
    }
    fn(root, package)
  }, list(normalizePath(root, mustWork = TRUE), fn),
    user_profile = FALSE, system_profile = FALSE)
}

# Outer namespace verification cannot attest to installations made by nested tools.
provenance_pass <- function(passed, provenance) {
  if (identical(passed, FALSE)) return(FALSE)
  if (identical(provenance, "nested_unverified")) return(NA)
  passed
}

namespace_complexity_pass <- function(value) {
  if (!is.data.frame(value) || !is.numeric(value$cyclocomp) || !nrow(value) ||
      any(!is.finite(value$cyclocomp))) return(NA)
  all(value$cyclocomp <= 15)
}

quality_provenance <- function(name) {
  if (name %in% c("R CMD check --as-cran", "covr", "goodpractice", "pkgcheck")) {
    return("nested_unverified")
  }
  if (name %in% c("installed_namespace_complexity", "export_arguments")) {
    return("isolated_namespace_verified")
  }
  "source_inspection"
}
