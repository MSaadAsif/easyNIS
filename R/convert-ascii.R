nis_convert_ascii <- function(path, dir, encoding) {
  if (!is.null(encoding)) {
    cli::cli_abort("Native HCUP Core files use ASCII. Leave `encoding` unset.")
  }
  year <- nis_convert_filename_year(basename(path))
  if (!grepl("^NIS_[0-9]{4}_Core[.]asc$", basename(path), ignore.case = TRUE) || !year %in% 2012:2024) {
    cli::cli_abort("Expected an HCUP `NIS_<year>_Core.ASC` file from 2012 through 2024.")
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  layout <- nis_convert_ascii_layout(year)
  nis_convert_with_stage(dir, year, function(temp, con) {
    records <- nis_convert_ascii_count(path, layout)
    nis_convert_ascii_copy(con, path, layout, year, file.path(temp, "part-000001.parquet"), records$newline)
    records$rows
  })
}

nis_convert_ascii_layout <- function(year) {
  layouts <- utils::read.csv(
    system.file("extdata", "nis-core-layouts.csv", package = "easyNIS", mustWork = TRUE),
    colClasses = c("integer", "character", "integer", "integer", "integer", "character", "NULL")
  )
  layouts[layouts$year == year, ]
}

# Count physical records before the CSV scan. This also catches lines the
# CSV reader might skip, and allows byte errors to identify the source field.
nis_convert_ascii_count <- function(path, layout) {
  width <- sum(layout$width)
  input <- file(path, "rb")
  on.exit(close(input), add = TRUE)
  rows <- 0L
  carry <- raw()
  crlf <- NULL
  repeat {
    chunk <- readBin(input, "raw", n = 8L * 1024L * 1024L)
    if (!length(carry) && !length(chunk)) {
      break
    }
    eof <- !length(chunk)
    if (eof && utils::tail(carry, 1L) == as.raw(13L)) {
      cli::cli_abort("Invalid line ending at source row {rows + 1L}.")
    }
    bytes <- if (eof) c(carry, as.raw(10L)) else c(carry, chunk)
    ends <- which(bytes == as.raw(10L))
    last <- max(c(0L, ends))
    if (last > 0L) {
      cr <- bytes[pmax(1L, ends - 1L)] == as.raw(13L)
      crlf <- nis_convert_ascii_line_ending(crlf, cr, eof, rows)
      nis_convert_ascii_check_records(bytes[seq_len(last)], ends, cr, width, layout, rows)
    }
    carry <- utils::tail(bytes, length(bytes) - last)
    rows <- rows + length(ends)
    if (length(carry) > width + 1L) {
      cli::cli_abort("Invalid record width at source row {rows + 1L}. Expected {width} bytes.")
    }
  }
  if (!rows) {
    cli::cli_abort("Source file has no records.")
  }
  list(rows = rows, newline = if (isTRUE(crlf)) "\\r\\n" else "\\n")
}

nis_convert_ascii_line_ending <- function(expected, cr, eof, rows) {
  if (eof) {
    return(expected)
  }
  if (is.null(expected)) {
    expected <- cr[[1L]]
  }
  mismatch <- which(cr != expected)
  if (length(mismatch)) {
    cli::cli_abort("Inconsistent line ending at source row {rows + mismatch[[1L]]}.")
  }
  expected
}

nis_convert_ascii_check_records <- function(bytes, ends, cr, width, layout, rows) {
  starts <- c(0L, utils::head(ends, -1L))
  wrong <- which(ends - starts - 1L - cr != width)
  if (length(wrong)) {
    cli::cli_abort("Invalid record width at source row {rows + wrong[[1L]]}. Expected {width} bytes.")
  }
  control <- which(bytes < as.raw(32L) | bytes > as.raw(126L))
  bad <- setdiff(control, c(ends, ends[cr] - 1L))
  if (length(bad)) {
    record <- findInterval(bad[[1L]], starts)
    position <- bad[[1L]] - starts[[record]]
    column <- layout$column[[findInterval(position, layout$start)]]
    nis_convert_invalid("Invalid UTF-8 or non-ASCII byte in", column, rows + record)
  }
}

nis_convert_ascii_copy <- function(con, path, layout, year, target, newline) {
  columns <- vapply(
    seq_len(nrow(layout)),
    function(i) {
      nis_convert_ascii_field(con, layout[i, ], year)
    },
    character(1)
  )
  from <- paste0(
    "read_csv(",
    nis_parquet_paths(con, path),
    ", columns={'record':'VARCHAR'}, auto_detect=false, header=false, parallel=false,",
    " delim=chr(31), quote='', escape='', new_line=",
    DBI::dbQuoteString(con, newline),
    ")"
  )
  target <- DBI::dbQuoteString(con, target)
  DBI::dbExecute(
    con,
    paste0(
      "COPY (SELECT ",
      paste(columns, collapse = ", "),
      " FROM (SELECT record, row_number() OVER () AS source_row FROM ",
      from,
      "))",
      " TO ",
      target,
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    )
  )
}

nis_convert_ascii_field <- function(con, field, year) {
  column <- DBI::dbQuoteIdentifier(con, field$column)
  value <- paste0("substr(record, ", field$start, ", ", field$width, ")")
  if (!is.na(field$decimals)) {
    expr <- nis_convert_ascii_number(con, field, year, paste0("trim(", value, ")"))
    return(paste(expr, "AS", column))
  }
  value <- paste0("NULLIF(rtrim(", value, "), '')")
  pattern <- nis_convert_code_pattern(field$column)
  if (!is.null(pattern)) {
    valid <- nis_convert_ascii_matches(con, value, pattern)
    error <- nis_convert_ascii_error(con, "Malformed ICD code", field$column)
    value <- paste("CASE WHEN", value, "IS NULL OR", valid, "THEN", value, "ELSE", error, "END")
  }
  paste(value, "AS", column)
}

nis_convert_ascii_number <- function(con, field, year, value) {
  pattern <- if (field$decimals > 0L) "[-+]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)" else "[-+]?[0-9]+"
  valid <- nis_convert_ascii_matches(con, value, pattern)
  error <- nis_convert_ascii_error(con, "Invalid numeric value", field$column)
  parsed <- nis_convert_ascii_cast(field, value)
  if (field$column == "YEAR") {
    error <- nis_convert_ascii_error(con, paste("Expected", year), field$column)
    return(paste(
      "CASE WHEN",
      valid,
      "AND TRY_CAST(",
      value,
      "AS INTEGER) =",
      year,
      "THEN",
      parsed,
      "ELSE",
      error,
      "END"
    ))
  }
  missing <- c("", strsplit(field$missing, ";", fixed = TRUE)[[1L]])
  missing <- paste(paste(value, "=", DBI::dbQuoteString(con, missing)), collapse = " OR ")
  paste("CASE WHEN", missing, "THEN NULL WHEN", valid, "THEN", parsed, "ELSE", error, "END")
}

nis_convert_ascii_cast <- function(field, value) {
  if (field$decimals > 0L) {
    parsed <- paste0("CAST(", value, " AS DOUBLE)")
    return(paste0(
      "(CASE WHEN contains(",
      value,
      ", '.') THEN ",
      parsed,
      " ELSE ",
      parsed,
      " / ",
      10^field$decimals,
      " END)"
    ))
  }
  type <- if (field$width >= 10L) "BIGINT" else "INTEGER"
  paste0("CAST(", value, " AS ", type, ")")
}

nis_convert_ascii_matches <- function(con, value, pattern) {
  paste0("regexp_full_match(", value, ", ", DBI::dbQuoteString(con, pattern), ")")
}

nis_convert_ascii_error <- function(con, reason, column) {
  prefix <- DBI::dbQuoteString(con, paste0(reason, " in column ", column, " at source row "))
  paste0("error(", prefix, " || source_row)")
}
