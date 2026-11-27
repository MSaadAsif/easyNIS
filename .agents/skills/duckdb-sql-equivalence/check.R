#!/usr/bin/env Rscript

case <- function(rows, args = list()) list(rows = rows, args = args)

mutation <- function(file, function_name, from, to) {
  list(file = file.path("R", file), function_name = function_name, from = from, to = to)
}

grid <- function(...) {
  expand.grid(..., KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
}

fixture <- function(..., draws = 128L) {
  values <- list(...)
  full <- do.call(grid, values)
  generated <- as.data.frame(lapply(values, function(x) x[sample.int(length(x), draws, replace = TRUE)]))
  rows <- rbind(full, generated)
  rows$id <- seq_len(nrow(rows))
  rows
}

duck_table <- function(con, rows) {
  duckdb::duckdb_register(con, "fixture", rows, overwrite = TRUE)
  dplyr::tbl(con, "fixture")
}

pull_columns <- function(query, columns) {
  projected <- dplyr::select(query, tidyselect::all_of(columns))
  rows <- as.data.frame(dplyr::collect(projected))
  rows[order(rows$id), , drop = FALSE]
}

split_years <- function(case) {
  years <- match(case$rows$YEAR, sort(unique(case$rows$YEAR), na.last = TRUE))
  parts <- lapply(split(case$rows, years), function(rows) {
    list(rows = rows, args = case$args)
  })
  list(left = parts, right = list(case))
}

shuffle_rows <- function(case) {
  shuffled <- case
  shuffled$rows <- case$rows[rev(seq_len(nrow(case$rows))), , drop = FALSE]
  list(left = list(shuffled), right = list(case))
}

bind_by_id <- function(outputs) {
  rows <- do.call(rbind, outputs)
  if ("id" %in% names(rows)) {
    rows <- rows[order(rows$id), , drop = FALSE]
  }
  rows
}

compare <- function(actual, expected, approximate) {
  if (!is.data.frame(actual) || !identical(names(actual), names(expected)) || nrow(actual) != nrow(expected)) {
    return(list(field = "<shape>", row = NA_integer_))
  }
  for (field in names(expected)) {
    a <- actual[[field]]
    b <- expected[[field]]
    if (identical(a, b)) {
      next
    }
    for (i in seq_along(b)) {
      same <- if (field %in% approximate) {
        identical(a[[i]], b[[i]]) ||
          (is.finite(a[[i]]) && is.finite(b[[i]]) && abs(a[[i]] - b[[i]]) <= 1e-12)
      } else {
        identical(a[[i]], b[[i]])
      }
      if (!same) return(list(field = field, row = i))
    }
    if (!identical(typeof(a), typeof(b))) return(list(field = field, row = NA_integer_))
  }
  NULL
}

check_case <- function(builder, case, con, case_id) {
  expected <- builder$reference(case$rows, case$args)
  actual <- tryCatch(
    suppressMessages(suppressWarnings(builder$sql(con, case$rows, case$args))),
    error = identity
  )
  if (inherits(actual, "error")) {
    return(list(case = case_id, error = conditionMessage(actual), expected = expected))
  }
  mismatch <- compare(actual, expected, builder$approximate)
  if (!is.null(mismatch)) c(list(case = case_id, actual = actual, expected = expected), mismatch)
}

run_builder <- function(builder, cases, con) {
  results <- lapply(seq_along(cases), function(i) check_case(builder, cases[[i]], con, i))
  Filter(Negate(is.null), results)
}

check_relation <- function(builder, relation, sample, con) {
  pair <- relation(sample)
  evaluate <- function(cases) {
    outputs <- lapply(cases, function(x) suppressMessages(suppressWarnings(builder$sql(con, x$rows, x$args))))
    combine <- if (is.null(pair$combine)) bind_by_id else pair$combine
    combine(outputs)
  }
  left <- evaluate(pair$left)
  right <- evaluate(pair$right)
  mismatch <- compare(left, right, builder$approximate)
  if (!is.null(mismatch)) c(list(input = pair, actual = left, expected = right), mismatch)
}

run_relations <- function(builder, sample, con, evidence, name) {
  found <- FALSE
  for (label in names(builder$relations)) {
    relation <- builder$relations[[label]]
    mismatch <- tryCatch(check_relation(builder, relation, sample, con), error = function(e) {
      list(input = sample, error = conditionMessage(e))
    })
    if (!is.null(mismatch)) {
      path <- file.path(evidence, paste0(name, "-relation-", label, ".rds"))
      saveRDS(mismatch, path)
      cat("RELATION FINDING", name, label, path, "\n")
      found <- TRUE
    } else {
      cat("RELATION PASS", name, label, "\n")
    }
  }
  found
}

with_mutation <- function(ns, mutation, run) {
  expressions <- as.list(parse(mutation$file, keep.source = FALSE))
  definitions <- Filter(
    function(expr) {
      is.call(expr) && identical(expr[[1L]], quote(`<-`)) && identical(expr[[2L]], as.name(mutation$function_name))
    },
    expressions
  )
  stopifnot(length(definitions) == 1L)
  body_text <- paste(deparse(definitions[[1L]][[3L]], width.cutoff = 500L), collapse = "\n")
  matches <- gregexpr(mutation$from, body_text, fixed = TRUE)[[1L]]
  if (length(matches) != 1L || matches[[1L]] == -1L) {
    stop("Stale mutation in ", mutation$function_name)
  }
  original <- get(mutation$function_name, ns, inherits = FALSE)
  replacement <- eval(parse(text = sub(mutation$from, mutation$to, body_text, fixed = TRUE)), ns)
  set_binding <- function(value) {
    unlockBinding(mutation$function_name, ns)
    assign(mutation$function_name, value, ns)
    lockBinding(mutation$function_name, ns)
  }
  on.exit(set_binding(original))
  set_binding(replacement)
  run()
}

run_mutation <- function(ns, builder, cases, baseline, con) {
  failed <- vapply(baseline, function(result) result$case, integer(1))
  with_mutation(ns, builder$mutation, function() {
    for (i in setdiff(seq_along(cases), failed)) {
      result <- check_case(builder, cases[[i]], con, i)
      if (!is.null(result$error)) {
        stop("Mutation produced an execution error: ", result$error)
      }
      if (!is.null(result)) return(result)
    }
    stop("Mutation survived on all baseline-passing cases")
  })
}

report <- function(result, cases, path) {
  saveRDS(list(input = cases[[result$case]], result = result), path)
  if (!is.null(result$error)) {
    return(paste("case", result$case, result$error))
  }
  i <- result$row
  field <- result$field
  output <- paste("case", result$case, "output row", i, "field", field)
  if (!is.na(i)) {
    output <- paste(
      output,
      "actual",
      deparse1(result$actual[[field]][[i]]),
      "expected",
      deparse1(result$expected[[field]][[i]])
    )
  }
  output
}

main <- function(args) {
  start <- proc.time()[["elapsed"]]
  mode <- if ("--mutations" %in% args) "--mutations" else "--check"
  selection <- setdiff(args, "--mutations")
  if (length(selection) > 1L || any(startsWith(selection, "-"))) {
    stop("Usage: Rscript --vanilla .agents/skills/duckdb-sql-equivalence/check.R [--mutations] [builder]")
  }
  home <- ".agents/skills/duckdb-sql-equivalence"
  evidence <- tempfile("sql-", tmpdir = "local/loop")
  dir.create(evidence, recursive = TRUE)
  log <- file.path(evidence, "run.txt")
  sink(log, split = TRUE)
  on.exit(sink(), add = TRUE)
  cat("COMMAND Rscript --vanilla", file.path(home, "check.R"), args, "\n")
  cat("MODE", mode, "\n")
  cat("EVIDENCE", evidence, "\n")
  cat("HEAD", system2("git", c("rev-parse", "HEAD"), stdout = TRUE), "\n")
  cat("WORKTREE\n", paste(system2("git", c("status", "--short"), stdout = TRUE), collapse = "\n"), "\n")
  cat("R", R.version.string, R.version$platform, "\n")
  for (pkg in c("duckdb", "DBI", "pkgload", "dplyr", "dbplyr", "survey")) {
    cat(pkg, as.character(utils::packageVersion(pkg)), "\n")
  }
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  base_options <- options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE)
  on.exit(options(base_options), add = TRUE)
  pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE)
  ns <- asNamespace("easyNIS")
  con <- DBI::dbConnect(duckdb::duckdb(), config = list(threads = "1"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  registry <- new.env(parent = environment(main))
  registry$builders <- list()
  registry$register <- function(
    name,
    cases,
    sql,
    reference,
    mutation,
    relations,
    relation_case = function(cases) cases[[1L]],
    relation_mutations = list(),
    approximate = character()
  ) {
    stopifnot(grepl("^[a-z][a-z0-9-]+$", name), !name %in% names(registry$builders))
    stopifnot(all(names(relation_mutations) %in% names(relations)))
    registry$builders[[name]] <- list(
      cases = cases,
      sql = sql,
      reference = reference,
      mutation = mutation,
      relations = relations,
      relation_case = relation_case,
      relation_mutations = relation_mutations,
      approximate = approximate
    )
  }
  registry$internal <- function(name) get(name, ns, inherits = FALSE)
  for (file in sort(list.files(file.path(home, "builders"), full.names = TRUE, pattern = "[.]R$"))) {
    sys.source(file, registry)
  }
  if (length(selection) && !selection %in% names(registry$builders)) {
    stop("Unknown builder: ", selection)
  }
  chosen <- if (length(selection)) registry$builders[selection] else registry$builders
  found <- FALSE
  for (name in names(chosen)) {
    set.seed(243L)
    builder <- chosen[[name]]
    cases <- builder$cases(con)
    baseline <- run_builder(builder, cases, con)
    cat(
      "BASELINE",
      name,
      length(cases),
      "batches,",
      sum(vapply(cases, function(x) nrow(x$rows), integer(1))),
      "input rows,",
      length(baseline),
      "failing batches\n"
    )
    for (failure in baseline) {
      path <- file.path(evidence, paste0(name, "-", failure$case, ".rds"))
      cat("FINDING", report(failure, cases, path), path, "\n")
    }
    sample <- builder$relation_case(cases)
    relation_findings <- run_relations(builder, sample, con, evidence, name)
    found <- found || relation_findings
    if (mode == "--mutations") {
      result <- run_mutation(ns, builder, cases, baseline, con)
      path <- file.path(evidence, paste0(name, "-mutation.rds"))
      cat("MUTATION CAUGHT", name, builder$mutation$function_name, report(result, cases, path), path, "\n")
      for (label in names(builder$relation_mutations)) {
        relation <- builder$relations[[label]]
        if (!is.null(check_relation(builder, relation, sample, con))) {
          stop("Baseline relation already fails: ", label)
        }
        mismatch <- with_mutation(ns, builder$relation_mutations[[label]], function() {
          check_relation(builder, relation, sample, con)
        })
        if (is.null(mismatch)) {
          stop("Mutation survived relation: ", label)
        }
        path <- file.path(evidence, paste0(name, "-relation-", label, "-mutation.rds"))
        saveRDS(mismatch, path)
        cat("RELATION MUTATION CAUGHT", name, label, path, "\n")
      }
      restored <- run_builder(builder, cases, con)
      if (!identical(baseline, restored)) {
        stop("Baseline changed after restoring ", name)
      }
      cat("BASELINE RESTORED", name, "\n")
    }
    found <- found || length(baseline) > 0L
  }
  cat("ELAPSED SECONDS", proc.time()[["elapsed"]] - start, "\n")
  cat(if (found) "RESULT FINDINGS\n" else "RESULT PASS\n")
  as.integer(found)
}

quit(status = main(commandArgs(trailingOnly = TRUE)))
