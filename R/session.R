#' Open an owned DuckDB session
#'
#' The session owns its connection. Import relations refer to temporary views
#' in that connection and become unusable after it closes. Separate in-memory
#' sessions are isolated. Persistent database files are retained after closing.
#'
#' @param path A local DuckDB database path or `":memory:"`.
#' @return An environment of class `nis_session`. Its `connection` can be used
#'   with DBI for advanced local work; do not replace it. Close with [nis_close()].
#' @export
#' @examples
#' session <- nis_open()
#' nis_close(session)
#' nis_close(session) # Closing twice is harmless.
nis_open <- function(path = ":memory:") {
  check_string(path, "path")
  session <- new.env(parent = emptyenv())
  session$connection <- DBI::dbConnect(
    duckdb::duckdb(dbdir = path, bigint = "integer64", shared_home = FALSE),
    bigint = "integer64"
  )
  session$closed <- FALSE
  session$counter <- 0L
  class(session) <- "nis_session"
  reg.finalizer(session, function(object) {
    if (!object$closed && DBI::dbIsValid(object$connection)) {
      try(DBI::dbDisconnect(object$connection), silent = TRUE)
    }
  }, onexit = TRUE)
  session
}

#' Close an owned DuckDB session
#'
#' @param session A session returned by [nis_open()].
#' @return The closed session, invisibly. No source files or database files are
#'   deleted. Repeated calls are harmless.
#' @export
nis_close <- function(session) {
  if (!inherits(session, "nis_session")) {
    stop("`session` must come from nis_open().", call. = FALSE)
  }
  if (!session$closed) {
    if (DBI::dbIsValid(session$connection)) DBI::dbDisconnect(session$connection)
    session$closed <- TRUE
    session$connection <- NULL
  }
  invisible(session)
}

check_session <- function(session) {
  if (!inherits(session, "nis_session")) {
    stop("`session` must come from nis_open().", call. = FALSE)
  }
  if (session$closed || !DBI::dbIsValid(session$connection)) {
    stop("The easyNIS session is closed. Open a new session and reimport.",
         call. = FALSE)
  }
  invisible(session)
}

check_string <- function(value, name) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(value)) {
    stop("`", name, "` must be one non-empty character string.", call. = FALSE)
  }
}

sql_name <- function(con, value) as.character(DBI::dbQuoteIdentifier(con, value))

next_view_name <- function(session) {
  session$counter <- session$counter + 1L
  paste0("easynis_", session$counter)
}
