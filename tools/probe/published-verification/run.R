source("tools/probe/workspace.R")
source("tools/probe/git-evidence.R")
source("tools/probe/receipt-io.R")
source("tools/probe/study-receipts.R")
source("tools/probe/provenance.R")

local({
  root <- normalizePath(".", mustWork = TRUE)
  loop_dir <- probe_workspace(root)
  data_root <- Sys.getenv("EASYNIS_DATA")
  if (!nzchar(data_root) || !dir.exists(data_root)) {
    stop("Set EASYNIS_DATA to the local NIS Parquet directory.", call. = FALSE)
  }
  evidence <- git_evidence()
  if (!isTRUE(evidence$working_tree_clean) || !valid_nonempty_string(evidence$commit)) {
    stop("Run from a clean checkout to compare this commit.", call. = FALSE)
  }
  studies <- load_reference_studies("tools/probe/reference-studies.yml")
  stopifnot(valid_reference_studies(studies))
  ids <- vapply(studies, `[[`, character(1), "id")
  references <- read_study_json(study_reference_path(loop_dir))
  if (!valid_study_references(references, ids)) {
    stop("Provide the three published values in the local references.json file.", call. = FALSE)
  }

  run_dir <- probe_run_directory(loop_dir, "published-verification")
  private <- file.path(run_dir, "private")
  dir.create(private)
  estimates <- tryCatch(
    with_verified_source(root, function(root, package) {
      log <- file(file.path(private, "run.txt"), "wt")
      sink(log)
      sink(log, type = "message")
      on.exit({
        sink(type = "message")
        sink()
        close(log)
      })
      cat("Command: Rscript --vanilla tools/probe/published-verification/run.R\n")
      print(sessionInfo())
      cat("Commit:", evidence$commit, "\nData root:", data_root, "\n")
      options(
        easyNIS.duckdb_config = list(threads = 2L, memory_limit = "4GB", temp_directory = private),
        survey.lonely.psu = "adjust"
      )
      source(file.path(root, "tools", "probe", "published-verification", "estimands.R"), local = TRUE)
      withCallingHandlers(published_estimands(data_root), warning = function(w) {
        cat(conditionMessage(w), "\n", file = file.path(private, "diagnostics.txt"), append = TRUE)
        invokeRestart("muffleWarning")
      })
    }),
    error = function(e) {
      cat(conditionMessage(e), "\n", file = file.path(private, "diagnostics.txt"), append = TRUE)
      stop("Published verification could not complete. See the local private diagnostics.", call. = FALSE)
    }
  )
  stopifnot(identical(names(estimates), ids), identical(evidence, git_evidence()))
  results <- lapply(ids, function(id) c(list(reference = references[[id]]), estimates[[id]]))
  receipt <- list(
    package_commit_hash = evidence$commit,
    verified_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    results = stats::setNames(results, ids)
  )
  path <- study_receipt_path(loop_dir, evidence$commit)
  staged <- tempfile(tmpdir = dirname(path))
  on.exit(unlink(staged))
  jsonlite::write_json(receipt, staged, auto_unbox = TRUE, digits = NA, pretty = TRUE)
  comparison <- study_verification_results(staged, evidence$commit, studies, references)
  stopifnot(!is.null(comparison), file.rename(staged, path))
  cat(study_verification_summary(comparison), "\n")
  if (any(comparison$status != "pass")) {
    quit(status = 1L)
  }
})
