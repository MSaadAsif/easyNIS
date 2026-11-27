# Run after capture.R <evidence> prday-fixture 2.
options(easyNIS.duckdb_config = list(threads = "2", memory_limit = "2GB"))
pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)

design_gate <- function(root) {
  input <- easyNIS::nis_open(file.path(root, "invented"), check_release = FALSE)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(input), shutdown = TRUE), add = TRUE)
  years <- 2017:2021
  id <- 0:49999
  age <- 18 + id %% 80
  hospital <- id %% 1000L + 1L
  stratum <- id %% 20 + 1
  weight <- 5 + (id %% 11) / 20
  psu <- tapply(ifelse(age >= 40, weight, 0), list(hospital, stratum), sum)
  se <- sqrt(sum(apply(psu, 2L, function(x) {
    x <- x[!is.na(x)]
    length(x) * stats::var(x)
  })))
  selected <- id %% 200 == 0
  placeholders <- setdiff(unique(hospital), unique(hospital[selected]))
  clock <- function() proc.time()[["elapsed"]]

  ns <- asNamespace("dbplyr")
  render <- get("sql_render", ns)
  render_seconds <- 0
  depth <- 0L
  set_render <- function(fn) {
    unlockBinding("sql_render", ns)
    assign("sql_render", fn, ns)
    lockBinding("sql_render", ns)
  }
  on.exit(set_render(render), add = TRUE)
  set_render(function(...) {
    start <- clock()
    depth <<- depth + 1L
    on.exit({
      depth <<- depth - 1L
    })
    result <- render(...)
    if (depth == 1L) {
      render_seconds <<- render_seconds + clock() - start
    }
    result
  })
  timed <- function(expr) {
    start <- clock()
    render_seconds <<- 0
    value <- force(expr)
    list(value = value, time = c(wall = clock() - start, render = render_seconds))
  }

  receipts <- lapply(seq_len(3L), function(run) {
    design <- timed(easyNIS::nis_design(input, KEY_NIS %% 200L == 0L, keep = c(AGE, LOS, I10_DX1)))
    report <- easyNIS::nis_design_report(design$value)
    stopifnot(report$input_n == length(id) * length(years), report$cohort_n == sum(selected) * length(years))
    total <- as.numeric(survey::svytotal(~AGE, design$value))
    stopifnot(isTRUE(all.equal(total, sum(age[selected] * weight[selected]) * length(years))))

    annual <- timed(easyNIS::nis_annual_totals(input, AGE >= 40L))
    stopifnot(
      identical(annual$value$YEAR, years),
      all(annual$value$n == sum(age >= 40)),
      all(annual$value$hospitals == length(unique(hospital[age >= 40]))),
      all(abs(annual$value$discharges - sum(weight[age >= 40])) < 1e-8),
      all(abs(annual$value$discharges_se - se) < 1e-8)
    )

    dest <- tempfile("design-gate-", tmpdir = root)
    export <- timed(easyNIS::nis_write_cohort(input, KEY_NIS %% 200L == 0L, dest, keep = KEY_NIS))
    saved <- easyNIS::nis_open(dest)
    out <- dplyr::collect(saved)
    DBI::dbDisconnect(dbplyr::remote_con(saved), shutdown = TRUE)
    unlink(dest, recursive = TRUE)
    for (year in years) {
      patients <- out[out$YEAR == year & out$.in_cohort, ]
      empty <- out[out$YEAR == year & !out$.in_cohort, ]
      stopifnot(identical(sort(patients$KEY_NIS), id[selected]), identical(sort(empty$HOSP_NIS), placeholders))
      stopifnot(all(is.na(empty$KEY_NIS)), all(empty$DISCWT == 5))
    }
    rbind(design = design$time, annual = annual$time, export = export$time)
  })
  times <- simplify2array(receipts)
  print(times)
  medians <- apply(times, c(1L, 2L), stats::median)
  print(medians)
  if (any(medians[, "wall"] > 5) || any(medians[, "render"] > 2.5)) {
    stop("Design, annual totals, or cohort export exceeded its wall or SQL rendering budget.")
  }
  cat("Verified design total and report, five annual totals and SEs, and every exported patient and placeholder.\n")
}

design_gate(commandArgs(TRUE)[[1L]])
