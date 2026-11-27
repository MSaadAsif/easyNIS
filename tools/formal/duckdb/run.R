#!/usr/bin/env Rscript

lake_build <- function(lake, target, log) {
  output <- suppressWarnings(system2(lake, c("build", target), stdout = TRUE, stderr = TRUE))
  writeLines(output, log)
  status <- attr(output, "status")
  if (is.null(status)) 0L else status
}

check_mutation <- function(lake, evidence, name, module, from, to) {
  path <- "Mutation.lean"
  if (file.exists(path)) {
    stop("Remove the previous scratch Mutation.lean before retrying.")
  }
  source <- readLines(file.path("DuckDBProofs", paste0(module, ".lean")), encoding = "UTF-8")
  matched <- grep(from, source, fixed = TRUE)
  if (length(matched) != 1L) {
    stop("Mutation does not identify one source line: ", name)
  }
  source[matched] <- sub(from, to, source[matched], fixed = TRUE)
  on.exit(unlink(path))
  writeLines(source, path, useBytes = TRUE)
  log <- file.path(evidence, paste0(name, ".log"))
  status <- lake_build(lake, "Mutation", log)
  errors <- grep(
    "Mutation[.]lean:[0-9]+:[0-9]+:.*(unsolved goals|tactic|type mismatch|grind.*failed|omega could not prove)",
    readLines(log),
    value = TRUE
  )
  if (status == 0L || !length(errors)) {
    stop("No proof failure for ", name, ". See ", log)
  }
  cat("LEAN MUTATION CAUGHT", name, log, "\n")
}

mutations <- function(lake, evidence) {
  run <- function(name, module, from, to) check_mutation(lake, evidence, name, module, from, to)
  run("taylor-domain", "Taylor", "inside && (!removeNA || complete)", "(!removeNA || complete)")
  run("taylor-padding", "Taylor", "moments xs n a b)", "moments xs xs.length a b)")
  run("taylor-scaling", "Taylor", "some (scale * moments xs n a b)", "some (moments xs n a b)")
  run("taylor-domain-lonely", "Taylor", "if grandCenterNeeded adjust domainAdjust", "if grandCenterNeeded adjust false")
  run("taylor-grand-center", "Taylor", "if xs.isEmpty then (x, y, count)", "if xs.isEmpty then (x, y, n + count)")
  run("irls-weights", "IRLS", "weights.sum * factor p metric", "(weights.length : Rat) * factor p metric")
  run("slots-era", "Slots", "xs.filter code", "xs.filter Slot.matched")
  run("slots-day", "Slots", "(longRows xs).filterMap Slot.day", "xs.filterMap Slot.day")
  run("slots-principal", "Slots", "((longRows xs).filter fun x => !x.principal).any", "(longRows xs).any")
  run("timing-window", "Slots", "decide (0 ", "decide (1 ")
  run("timing-same-slot", "Slots", "x.outcome && start.any", "(x.outcome && !x.index) && start.any")
  run("ccsr-category", "Slots", "pair.2 == category", "pair.2 != category")
  run("lifetime-owner-198", "Lifetime", "def keepComputeRoot : Bool := true", "def keepComputeRoot : Bool := false")
  run("lifetime-drop-table", "Lifetime", "def keepLiveTable : Bool := true", "def keepLiveTable : Bool := false")
  run("lifetime-scoped-exit", "Lifetime", "def registerHandler : Bool := true", "def registerHandler : Bool := false")
  run("writer-validation", "Lifetime", "def verifyAllParts : Bool := true", "def verifyAllParts : Bool := false")
  run("writer-close", "Lifetime", "def closeBeforePublish : Bool := true", "def closeBeforePublish : Bool := false")
  run(
    "writer-stage-exit",
    "Lifetime",
    "def registerStageHandler : Bool := true",
    "def registerStageHandler : Bool := false"
  )
  run(
    "writer-db-exit",
    "Lifetime",
    "def registerDbHandler : Bool := true",
    "def registerDbHandler : Bool := false"
  )
  run(
    "writer-cleanup-order",
    "Lifetime",
    "def closeBeforeUnlink : Bool := true",
    "def closeBeforeUnlink : Bool := false"
  )
}

run_lean <- function(evidence, scratch) {
  original <- setwd("tools/formal/duckdb")
  on.exit(setwd(original))
  lake <- Sys.which("lake")
  if (!nzchar(lake)) {
    stop("Install elan and put its bin directory on PATH. See the DuckDB SQL equivalence skill.")
  }
  cat("LEAN", system2(lake, "--version", stdout = TRUE), "\n")
  log <- file.path(evidence, "lake-build.log")
  if (lake_build(lake, "DuckDBProofs", log) != 0L) {
    stop("Lake build failed. See ", log)
  }
  cat("LEAN PASS", log, "\n")
  if (scratch) {
    mutations(lake, evidence)
    log <- file.path(evidence, "lake-restored.log")
    if (lake_build(lake, "DuckDBProofs", log) != 0L) {
      stop("Restored Lake build failed. See ", log)
    }
    cat("LEAN RESTORED", log, "\n")
  }
}

main <- function(args) {
  if (length(setdiff(args, c("--mutations", "--lean-only")))) {
    stop("Usage: Rscript --vanilla tools/formal/duckdb/run.R [--mutations] [--lean-only]")
  }
  evidence <- tempfile("lean-duckdb-", tmpdir = "local/loop")
  dir.create(evidence, recursive = TRUE)
  evidence <- normalizePath(evidence, winslash = "/")
  sink(file.path(evidence, "run.txt"), split = TRUE)
  on.exit(sink())
  cat("COMMAND Rscript --vanilla tools/formal/duckdb/run.R", args, "\n")
  cat("HEAD", system2("git", c("rev-parse", "HEAD"), stdout = TRUE), "\n")
  cat("PLATFORM", R.version$platform, R.version.string, "\n")
  cat("EVIDENCE", evidence, "\n")
  scratch <- "--mutations" %in% args
  run_lean(evidence, scratch)
  if ("--lean-only" %in% args) {
    return(0L)
  }
  rscript <- file.path(R.home("bin"), "Rscript")
  script <- ".agents/skills/duckdb-sql-equivalence/check.R"
  system2(rscript, c("--vanilla", script, if (scratch) "--mutations"))
}

quit(status = main(commandArgs(trailingOnly = TRUE)))
