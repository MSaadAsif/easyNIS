args <- commandArgs(trailingOnly = TRUE)
if (identical(args[[1L]], "fixture")) {
  source(file.path("tools", "probe", "performance-fixture.R"))
  performance_fixture(args[[2L]], as.integer(args[[3L]]))
  quit(status = 0L)
}

source(file.path("tools", "probe", "performance-workload.R"))
trial <- readRDS(args[[1L]])
dir <- Sys.getenv("EASYNIS_PERFORMANCE_SCRATCH")
package <- loadNamespace("easyNIS", lib.loc = trial$library)
stopifnot(identical(
  normalizePath(getNamespaceInfo(package, "path")),
  normalizePath(file.path(trial$library, "easyNIS"))
))
wall <- tryCatch(
  performance_trial(
    trial$step,
    trial$path,
    trial$years,
    trial$rows,
    trial$threads,
    trial$memory,
    dir
  ),
  error = function(cnd) {
    if (!is.na(trial$rows)) {
      message(conditionMessage(cnd))
    }
    NA_real_
  }
)
saveRDS(
  list(wall = wall, commit_bytes = unname(ps::ps_memory_info()[["peak_pagefile"]])),
  args[[2L]]
)
quit(status = as.integer(!is.finite(wall)))
