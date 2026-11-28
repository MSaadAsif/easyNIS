# Run after capture.R <evidence> prday-fixture 2.
options(easyNIS.duckdb_config = list(threads = "2", memory_limit = "2GB"))
pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)

open_gate_trial <- function(path, reader) {
  clock <- function() proc.time()[["elapsed"]]
  start <- clock()
  warned <- FALSE
  input <- withCallingHandlers(
    easyNIS::nis_open(path, reader = reader),
    easynis_release_mismatch = function(warning) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  con <- dbplyr::remote_con(input)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  opened <- clock()
  result <- input |>
    dplyr::filter(AGE >= 40L) |>
    dplyr::group_by(YEAR) |>
    dplyr::summarise(rows = dplyr::n())
  render_start <- clock()
  sql <- dbplyr::sql_render(result)
  rendered <- clock()
  rows <- DBI::dbGetQuery(con, sql)
  elapsed <- clock() - start
  stopifnot(
    warned,
    identical(input$src$.easyNIS_release_check, "mismatch"),
    ncol(input) == 139L,
    identical(sort(rows$YEAR), 2017:2021),
    all(rows$rows == sum(18 + (0:49999 %% 80) >= 40))
  )
  c(open = opened - start, first_render = rendered - render_start, wall = elapsed)
}

path <- file.path(commandArgs(TRUE)[[1L]], "invented")
readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
for (reader in readers) {
  times <- replicate(3L, open_gate_trial(path, reader))
  medians <- apply(times, 1L, stats::median)
  cat(reader, "timing medians in seconds\n")
  print(medians)
  if (medians[["wall"]] > 2 || medians[["open"]] > 1.25 || medians[["first_render"]] > 0.20) {
    stop("Opening and querying the wide fixture exceeded its open, rendering, or total budget.")
  }
}
