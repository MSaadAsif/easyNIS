#' @importClassesFrom duckdb duckdb_connection duckdb_result
#' @importFrom DBI dbBind dbSendQuery
NULL

methods::setClass("nis_duckdb_connection", contains = "duckdb_connection")
methods::setClass("nis_duckdb_result", contains = "duckdb_result")

# DuckDB executes in dbSendQuery() or, for deferred parameters, dbBind().
methods::setMethod("dbSendQuery", c("nis_duckdb_connection", "character"), function(conn, statement, ...) {
  result <- nis_duckdb_translate_errors(methods::callNextMethod())
  methods::new("nis_duckdb_result", result)
})

methods::setMethod("dbBind", "nis_duckdb_result", function(res, params, ...) {
  nis_duckdb_translate_errors(methods::callNextMethod())
})

nis_duckdb_translate_errors <- function(query) {
  withCallingHandlers(query, error = function(error) {
    if (rlang::cnd_inherits(error, "easyNIS_invalid_utf8")) {
      return()
    }
    while (!is.null(error$parent)) {
      error <- error$parent
    }
    message <- strsplit(conditionMessage(error), "\n", fixed = TRUE, useBytes = TRUE)[[1L]][1L]
    encoding_error <- "^(Invalid Error: )?Invalid Input Error: Invalid string encoding found in Parquet file"
    if (!grepl(encoding_error, message, useBytes = TRUE)) {
      return()
    }

    field <- function(text, pattern) {
      match <- regmatches(text, regexec(pattern, text, perl = TRUE, useBytes = TRUE))[[1L]]
      match[2L]
    }
    file_pattern <- 'Parquet file "(.+?)"(?=:|,| \\(|$)'
    file <- field(message, file_pattern)
    details <- sub(file_pattern, "", message, perl = TRUE, useBytes = TRUE)
    details <- sub(': value ".*$', "", details, useBytes = TRUE)
    column <- field(details, '(?i)column ["\x27]([^"\x27]+)["\x27]')
    location <- paste0(
      if (!is.na(column)) " in column {.field {column}}",
      if (!is.na(file)) " in {.path {file}}"
    )
    cli::cli_abort(
      c(
        paste0("Malformed UTF-8", location, "."),
        i = paste(
          'Use {.code nis_open(reader = "arrow")} to work around this.',
          "Regenerate the Parquet file with the correct source encoding to fix it."
        )
      ),
      class = "easyNIS_invalid_utf8",
      parent = error,
      call = conditionCall(error)
    )
  })
}

nis_duckdb_connect <- function(config = list()) {
  methods::new("nis_duckdb_connection", DBI::dbConnect(duckdb::duckdb(config = config)))
}

nis_duckdb_open_data <- function() {
  config <- nis_duckdb_workload_settings(getOption("easyNIS.duckdb_config", list()))
  root <- if (is.null(config$temp_directory)) tempdir() else config$temp_directory
  if (!dir.exists(root)) {
    cli::cli_abort("The DuckDB `temp_directory` must name an existing directory.")
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  spill <- tempfile("easynis-spill-", tmpdir = root)
  if (!dir.create(spill, mode = "0700")) {
    cli::cli_abort("Could not create a private DuckDB spill directory.")
  }
  spill <- normalizePath(spill, winslash = "/", mustWork = TRUE)
  config$temp_directory <- spill
  spill_limit <- config$max_temp_directory_size
  config$max_temp_directory_size <- NULL
  con <- NULL
  release <- function() {
    on.exit(nis_remove_owned_directory(spill), add = TRUE)
    if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }
  on.exit(release(), add = TRUE)
  con <- nis_duckdb_connect(config)
  if (!is.null(spill_limit)) {
    # DuckDB 1.5.2 can report a startup cap without enforcing it during spill.
    DBI::dbExecute(con, paste("SET max_temp_directory_size =", DBI::dbQuoteString(con, spill_limit)))
  }
  on.exit(NULL, add = FALSE)
  list(con = con, release = release)
}

nis_remove_owned_directory <- function(path) {
  if (dir.exists(path) && identical(normalizePath(path, winslash = "/", mustWork = TRUE), path)) {
    unlink(path, recursive = TRUE)
  }
  invisible(NULL)
}

nis_duckdb_workload_settings <- function(config) {
  supported <- c("memory_limit", "threads", "temp_directory", "max_temp_directory_size", "preserve_insertion_order")
  keys <- names(config)
  if (!is.list(config) || length(keys) != length(config) || anyDuplicated(keys) || !all(keys %in% supported)) {
    cli::cli_abort("Option `easyNIS.duckdb_config` must be a named list of DuckDB workload settings.")
  }
  lapply(config, nis_duckdb_setting_text)
}

nis_duckdb_setting_text <- function(value) {
  if (!is.atomic(value) || length(value) != 1L || is.na(value)) {
    cli::cli_abort("Each DuckDB workload setting must have one non-missing value.")
  }
  as.character(value)
}

nis_duckdb_attach_finalizer <- function(tbl, release, owners = list()) {
  finalizer <- new.env(parent = emptyenv())
  reg.finalizer(finalizer, function(e) release(), onexit = TRUE)
  tbl$src$.easyNIS_connection_finalizer <- finalizer
  if (length(owners)) {
    tbl$src$.easyNIS_arrow_refs <- owners
  }
  tbl
}

# Parquet files produced by easyNIS that do not represent an HCUP release.
nis_non_release_metadata <- c(easyNIS_source = "non_release")

nis_duckdb_write_parquet <- function(data, path, con) {
  table <- "easyNIS_fixture"
  DBI::dbWriteTable(con, table, data, temporary = TRUE, overwrite = TRUE)
  destination <- as.character(DBI::dbQuoteString(con, normalizePath(path, winslash = "/", mustWork = FALSE)))
  key <- DBI::dbQuoteIdentifier(con, names(nis_non_release_metadata))
  value <- DBI::dbQuoteString(con, unname(nis_non_release_metadata))
  statement <- paste0(
    "COPY ",
    as.character(DBI::dbQuoteIdentifier(con, table)),
    " TO ",
    destination,
    " (FORMAT PARQUET, KV_METADATA {",
    key,
    ": ",
    value,
    "})"
  )
  DBI::dbExecute(con, statement)
  invisible(path)
}
