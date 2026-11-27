#' Convert a NIS file to annual Parquet
#'
#' @param path Path to one annual NIS Stata (`.dta`), SAS (`.sas7bdat`),
#'   or SPSS (`.sav`) file with a numeric `YEAR` column, or one HCUP
#'   fixed-width `NIS_<year>_Core.ASC` file from 2012 through 2024.
#' @param dir Existing directory in which to create `NIS_<year>.parquet/`.
#' @param encoding Source encoding override passed to haven. The default uses
#'   the reader's format-specific encoding. Use `"latin1"` for a legacy
#'   Stata file known to use Latin-1.
#'
#' @details
#' Conversion reads bounded batches and writes zstd-compressed Parquet parts
#' in source order. All records must have the same year, which must agree
#' with the year in filenames starting with `NIS_<year>`. Invalid UTF-8 or
#' malformed ICD slot values stop conversion. Blank codes and HCUP's
#' `invl` and `incn` codes are accepted.
#'
#' Populated code slots must match the release's coding era. For 2015,
#' provide the discharge quarter or the corresponding diagnosis and procedure
#' version column. Later SAS and SPSS batches can require rescanning the source
#' from the beginning. This keeps memory bounded but increases conversion time
#' as the file grows.
#'
#' Native Core files use HCUP's published SAS layouts, including the 2019
#' and 2020 V2 layouts. HCUP numeric missing codes become Parquet nulls.
#' Character fields lose their right padding and blank fields become nulls.
#' Use a consistent LF or CRLF line ending throughout the file.
#' The 2015 native Core file contains no diagnosis or procedure slots.
#' The Core converter does not join the separate 2015 diagnosis and
#' procedure groups or other supplementary HCUP files.
#'
#' The annual directory is published after validation and is never
#' overwritten. [nis_open()] checks converted data against the HCUP annual
#' release statistics by default.
#'
#' @return The path of the annual Parquet directory, invisibly.
#' @family data-access
#' @export
#' @examples
#' if (requireNamespace("haven", quietly = TRUE)) {
#'   dir <- tempfile()
#'   dir.create(dir)
#'   path <- file.path(dir, "NIS_2020.dta")
#'   haven::write_dta(data.frame(YEAR = 2020L, I10_DX1 = "I509"), path)
#'   nis_convert(path, dir)
#'   nis_open(dir, check_release = FALSE)
#' }
nis_convert <- function(path, dir, encoding = NULL) {
  nis_convert_check_paths(path, dir)
  if (tolower(tools::file_ext(path)) == "asc") {
    return(nis_convert_ascii(path, dir, encoding))
  }
  read <- nis_convert_haven_reader(path, encoding)
  first <- read(0L)
  year <- nis_convert_source_year(first, basename(path))
  nis_convert_with_stage(dir, year, function(temp, con) {
    nis_convert_write_batches(read, first, year, temp, con)
  })
}

nis_convert_with_stage <- function(dir, year, write) {
  stage <- nis_convert_stage(dir, year)
  on.exit(nis_remove_owned_directory(stage$temp), add = TRUE)
  db <- nis_duckdb_open_data()
  on.exit(db$release(), add = TRUE, after = FALSE)
  DBI::dbExecute(db$con, "SET preserve_insertion_order = true")
  rows <- write(stage$temp, db$con)
  nis_convert_check_count(db$con, stage$temp, rows)
  db$release()
  nis_convert_publish(stage)
}

nis_convert_check_paths <- function(path, dir) {
  if (!rlang::is_string(path) || !file.exists(path) || dir.exists(path)) {
    cli::cli_abort("`path` must name an existing file.")
  }
  if (!rlang::is_string(dir) || !dir.exists(dir)) {
    cli::cli_abort("`dir` must name an existing directory.")
  }
}

nis_convert_haven_reader <- function(path, encoding) {
  format <- tolower(tools::file_ext(path))
  if (!format %in% c("dta", "sas7bdat", "sav")) {
    cli::cli_abort("Supported source extensions are `.dta`, `.sas7bdat`, `.sav`, and `.asc`.")
  }
  rlang::check_installed("haven", reason = "to convert statistical data files.")
  reader <- switch(
    format,
    dta = haven::read_dta,
    sas7bdat = haven::read_sas,
    sav = function(...) haven::read_sav(..., user_na = TRUE)
  )
  read <- function(offset, size, input_encoding = encoding) {
    reader(path, encoding = input_encoding, skip = offset, n_max = size, .name_repair = "minimal")
  }
  function(offset, size = 100000L) {
    tryCatch(
      read(offset, size),
      error = function(error) nis_convert_read_error(error, read, path, encoding, offset, size)
    )
  }
}

nis_convert_read_error <- function(error, read, path, encoding, offset, size) {
  if (!nis_convert_decode_error(error)) {
    cli::cli_abort("Could not read source batch starting at row {offset + 1L}.", parent = error)
  }
  probe <- function(offset, size, ...) tryCatch(read(offset, size, ...), error = identity)
  bytes <- probe(offset, size, "latin1")
  if (!is.data.frame(bytes) || !nrow(bytes)) {
    cli::cli_abort("Could not decode source batch starting at row {offset + 1L}.", parent = error)
  }
  begin <- 1L
  end <- nrow(bytes)
  while (begin < end) {
    middle <- (begin + end) %/% 2L
    if (nis_convert_decode_error(probe(offset, middle))) end <- middle else begin <- middle + 1L
  }
  row <- offset + begin
  if (is.null(encoding)) {
    encoding <- tryCatch(nis_convert_declared_encoding(path), error = function(error) NULL)
  }
  columns <- nis_convert_undecodable_columns(bytes[begin, , drop = FALSE], encoding)
  if (length(columns)) {
    label <- if (length(columns) == 1L) "column" else "columns"
    cli::cli_abort("Malformed source encoding in {label} {.field {columns}} at source row {row}.", parent = error)
  }
  cli::cli_abort("Could not decode source row {row}.", parent = error)
}

nis_convert_decode_error <- function(error) {
  inherits(error, "error") && grepl("(invalid|incomplete) byte sequence", conditionMessage(error))
}

nis_convert_undecodable_columns <- function(data, encoding) {
  if (is.null(encoding)) {
    return(character())
  }
  text <- data[vapply(data, is.character, logical(1))]
  invalid <- vapply(
    text,
    function(value) {
      # Latin-1 maps each input byte to one character. Reverse that diagnostic
      # read so iconv can check the original bytes in the intended encoding.
      bytes <- iconv(value, from = "UTF-8", to = "latin1")
      decoded <- tryCatch(iconv(bytes, from = encoding, to = "UTF-8"), error = function(error) bytes)
      any(!is.na(bytes) & is.na(decoded))
    },
    logical(1)
  )
  names(text)[invalid]
}

nis_convert_source_year <- function(data, filename) {
  columns <- nis_convert_column_keys(names(data))
  year_column <- match("year", columns)
  if (is.na(year_column)) {
    nis_convert_invalid("Missing", "YEAR", 1L)
  }
  values <- data[[year_column]]
  if (!is.numeric(values)) {
    nis_convert_invalid("Expected numeric", "YEAR", 1L)
  }
  if (!nrow(data)) {
    cli::cli_abort("Source file has no records.")
  }
  year <- values[[1L]]
  if (!nis_open_whole_years(year) || year < 2012 || year > 9999) {
    nis_convert_invalid("Invalid NIS year in", "YEAR", 1L)
  }
  named_year <- nis_convert_filename_year(filename)
  if (!is.na(named_year) && year != named_year) {
    nis_convert_invalid(paste("Expected filename year", named_year, "in"), "YEAR", 1L)
  }
  as.integer(year)
}

nis_convert_column_keys <- function(columns) {
  if (!all(validUTF8(columns)) || !all(nzchar(columns))) {
    cli::cli_abort("Source column names must be nonempty and valid UTF-8.")
  }
  keys <- nis_sql_identifier_key(columns)
  if (anyDuplicated(keys)) {
    cli::cli_abort("Source column names must be unique.")
  }
  keys
}

nis_convert_filename_year <- function(filename) {
  match <- regmatches(filename, regexec("^NIS[_-]?([0-9]{4})(?![0-9])", filename, ignore.case = TRUE, perl = TRUE))[[
    1L
  ]]
  as.integer(match[2L])
}

nis_convert_stage <- function(dir, year) {
  dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  target <- file.path(dir, paste0("NIS_", year, ".parquet"))
  nis_convert_check_target(target)
  temp <- tempfile(".easynis-convert-", tmpdir = dir)
  if (!dir.create(temp, mode = "0700")) {
    cli::cli_abort("Could not create a temporary sibling of {.path {target}}.")
  }
  list(target = target, temp = normalizePath(temp, winslash = "/", mustWork = TRUE))
}

nis_convert_publish <- function(stage) {
  nis_convert_check_target(stage$target)
  if (!suppressWarnings(file.rename(stage$temp, stage$target))) {
    cli::cli_abort("Could not publish {.path {stage$target}}.")
  }
  invisible(stage$target)
}

nis_convert_check_target <- function(path) {
  if (file.exists(path)) cli::cli_abort("Output {.path {path}} already exists.")
}

nis_convert_write_batches <- function(read, data, year, temp, con) {
  offset <- 0L
  part <- 1L
  year_column <- match("year", nis_sql_identifier_key(names(data)))
  repeat {
    size <- nrow(data)
    if (!size) {
      break
    }
    nis_convert_validate_batch(data, year, offset)
    data[[year_column]] <- as.integer(data[[year_column]])
    path <- file.path(temp, sprintf("part-%06d.parquet", part))
    nis_convert_copy_batch(con, data, path)
    offset <- offset + size
    if (size < 100000L) {
      break
    }
    part <- part + 1L
    data <- read(offset)
  }
  offset
}

nis_convert_validate_batch <- function(data, year, offset) {
  columns <- nis_sql_identifier_key(names(data))
  values <- data[[match("year", columns)]]
  wrong <- which(is.na(values) | values != year)
  if (length(wrong)) {
    nis_convert_invalid(paste("Expected", year, "in"), "YEAR", offset + wrong[[1L]])
  }

  eras <- nis_convert_eras(data, columns, year)
  for (i in seq_along(columns)) {
    nis_convert_validate_text(data[[i]], names(data)[[i]], eras, offset)
  }
}

nis_convert_eras <- function(data, columns, year) {
  get <- function(key) {
    i <- match(key, columns)
    if (is.na(i)) NA_integer_ else data[[i]]
  }
  if (year != 2015L) {
    era <- year < 2015L
    return(list(dx9 = era, pr9 = era, dx10 = !era, pr10 = !era))
  }
  quarter <- get("dqtr")
  dx <- get("dxver")
  pr <- get("prver")
  list(
    dx9 = nis_convert_2015_era(quarter, dx, 1:3, 9L),
    pr9 = nis_convert_2015_era(quarter, pr, 1:3, 9L),
    dx10 = nis_convert_2015_era(quarter, dx, 4L, 10L),
    pr10 = nis_convert_2015_era(quarter, pr, 4L, 10L)
  )
}

nis_convert_2015_era <- function(quarter, version, quarters, system) {
  valid_quarter <- quarter %in% quarters
  valid_version <- version %in% system
  (valid_quarter | valid_version) &
    (is.na(quarter) | valid_quarter) &
    (is.na(version) | valid_version)
}

nis_convert_validate_text <- function(values, column, eras, offset) {
  if (is.character(values)) {
    invalid <- which(!validUTF8(values) & !is.na(values))
    if (length(invalid)) nis_convert_invalid("Malformed UTF-8 in", column, offset + invalid[[1L]])
  }
  slot <- toupper(nis_sql_identifier_key(column))
  pattern <- nis_convert_code_pattern(slot)
  if (is.null(pattern)) {
    return(invisible(NULL))
  }
  if (!is.character(values)) {
    nis_convert_invalid("Expected text in", column, offset + 1L)
  }
  wrong <- which(!is.na(values) & !grepl(pattern, values, perl = TRUE, useBytes = TRUE))
  if (length(wrong)) {
    nis_convert_invalid("Malformed ICD code in", column, offset + wrong[[1L]])
  }
  wrong <- which(!nis_convert_slot_era(slot, eras) & !is.na(values) & grepl("[^ ]", values, useBytes = TRUE))
  if (length(wrong)) nis_convert_invalid("Wrong coding era in", column, offset + wrong[[1L]])
}

nis_convert_slot_era <- function(slot, eras) {
  switch(
    sub("[0-9]+$", "", slot),
    DX = eras$dx9,
    ECODE = eras$dx9,
    PR = eras$pr9,
    I10_DX = eras$dx10,
    I10_ECAUSE = eras$dx10,
    I10_PR = eras$pr10
  )
}

nis_convert_code_pattern <- function(column) {
  stem <- sub("[0-9]+$", "", column)
  if (identical(stem, column)) {
    return(NULL)
  }
  code <- switch(
    stem,
    DX = "[0-9]{3,5}|V[0-9]{2,4}|E[0-9]{3,4}",
    ECODE = "E[0-9]{3,4}",
    PR = "[0-9]{2,4}",
    I10_DX = "[A-Z][0-9][A-Z0-9]{1,5}",
    I10_ECAUSE = "[A-Z][0-9][A-Z0-9]{1,5}",
    I10_PR = "[A-HJ-NP-Z0-9]{7}"
  )
  if (!is.null(code)) paste0("^(?:", code, "|invl|incn)? *\\z")
}

nis_convert_invalid <- function(reason, column, row) {
  cli::cli_abort("{reason} column {.field {column}} at source row {row}.")
}

nis_convert_copy_batch <- function(con, data, path) {
  duckdb::duckdb_register(con, "nis_convert_batch", data)
  on.exit(duckdb::duckdb_unregister(con, "nis_convert_batch"), add = TRUE)
  target <- DBI::dbQuoteString(con, path)
  DBI::dbExecute(con, paste("COPY nis_convert_batch TO", target, "(FORMAT PARQUET, COMPRESSION ZSTD)"))
}

nis_convert_check_count <- function(con, temp, rows) {
  parts <- list.files(temp, pattern = "[.]parquet$", full.names = TRUE)
  paths <- nis_parquet_paths(con, parts)
  metadata <- DBI::dbGetQuery(con, paste0("SELECT num_rows FROM parquet_file_metadata(", paths, ")"))
  written <- sum(metadata$num_rows)
  if (written != rows) {
    cli::cli_abort("Parquet row count mismatch: read {rows} source rows and wrote {written}.")
  }
}
