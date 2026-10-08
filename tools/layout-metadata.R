# Development-only reader of public HCUP Core specifications. It does not
# interpret missing values, authenticate conversions, or approve annual inputs.
parse_core_layout <- function(lines, year, revision = "unspecified") {
  fail <- function(message) stop("Invalid Core layout for ", year, ": ", message,
                                call. = FALSE)
  whole <- function(value) {
    if (anyNA(value) || any(!grepl("^[0-9]+$", value))) fail("invalid whole number.")
    result <- as.numeric(value)
    if (any(!is.finite(result) | result > .Machine$integer.max)) {
      fail("whole number exceeds the parser limit.")
    }
    as.integer(result)
  }
  header <- function(prefix) {
    matched <- lines[startsWith(lines, prefix)]
    if (length(matched) != 1L) fail(paste0("missing or repeated ", prefix))
    trimws(substring(matched, nchar(prefix) + 1L))
  }
  dataset <- paste0("NIS_", year, "_CORE", if (revision == "V2") "_V2" else "")
  if (!identical(header("Data Set Name:"), dataset)) fail("wrong dataset or revision.")
  count <- whole(header("Number of Observations:"))
  record_length <- whole(header("Total Record Length:"))
  field_count <- whole(header("Total Number of Data Elements:"))
  if (any(c(count, record_length, field_count) < 1L)) fail("empty layout header.")

  # The specification's own column guide differs between 2017 and 2022.
  guide <- function(description) {
    matched <- lines[grepl("^ *[0-9]+- *[0-9]+ +", lines) &
                       endsWith(trimws(lines), description)]
    if (length(matched) != 1L) fail(paste0("missing or repeated column guide: ", description))
    range <- regmatches(matched, regexec("^ *([0-9]+)- *([0-9]+) +", matched))[[1L]]
    bounds <- whole(range[2:3])
    if (bounds[1L] < 1L || bounds[2L] < bounds[1L]) fail("invalid column guide bounds.")
    bounds
  }
  descriptions <- c(
    "Database name", "Discharge year of data", "File name", "Data element number",
    "Data element name", "Starting column of data element in ASCII file",
    "Ending column of data element in ASCII file",
    "Non-zero number of digits after decimal point for numeric data element",
    "Data element type (Num=numeric; Char=character)"
  )
  ranges <- lapply(descriptions, guide)
  if (any(vapply(ranges[-1L], `[`, integer(1), 1L) <=
          vapply(ranges[-length(ranges)], `[`, integer(1), 2L))) {
    fail("overlapping column guide ranges.")
  }
  rows <- lines[grepl("^NIS([[:space:]]|$)", lines)]
  if (length(rows) != field_count) fail("field count does not match the rows.")
  extract <- function(index) trimws(substr(rows, ranges[[index]][1L], ranges[[index]][2L]))
  if (any(nchar(rows, type = "chars") < ranges[[9L]][2L])) fail("truncated field row.")
  if (any(extract(1L) != "NIS") || any(extract(2L) != as.character(year)) ||
      any(toupper(extract(3L)) != dataset)) fail("wrong dataset or year in a field row.")
  fields <- data.frame(
    number = whole(extract(4L)), name = extract(5L), start = whole(extract(6L)),
    end = whole(extract(7L)), decimals = whole(ifelse(extract(8L) == "", "0", extract(8L))),
    type = extract(9L), stringsAsFactors = FALSE
  )
  if (!identical(fields$number, seq_len(field_count))) fail("nonsequential field numbers.")
  if (any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", fields$name)) ||
      anyDuplicated(tolower(fields$name))) fail("invalid or duplicated field names.")
  if (any(!fields$type %in% c("Num", "Char"))) fail("unknown field type.")
  if (fields$start[1L] != 1L || any(fields$end < fields$start) ||
      any(fields$start[-1L] != as.double(fields$end[-nrow(fields)]) + 1) ||
      tail(fields$end, 1L) != record_length) fail("noncontiguous record positions.")
  if (any(fields$decimals >= fields$end - fields$start + 1L) ||
      any(fields$type == "Char" & fields$decimals != 0L)) fail("invalid decimal precision.")
  required <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
  if (!all(required %in% fields$name) ||
      any(fields$type[match(required, fields$name)] != "Num") ||
      any(fields$decimals[match(setdiff(required, "DISCWT"), fields$name)] != 0L)) {
    fail("missing or invalid structural fields.")
  }
  slots <- function(prefix) {
    selected <- fields[grepl(paste0("^", prefix, "[0-9]+$"), fields$name), , drop = FALSE]
    if (!nrow(selected) || !identical(selected$name, paste0(prefix, seq_len(nrow(selected)))) ||
        any(selected$type != "Char") || any(selected$end - selected$start + 1L != 7L)) {
      fail(paste0("invalid coding slots: ", prefix))
    }
    nrow(selected)
  }
  list(dataset = dataset, records = count, record_length = record_length,
       fields = fields, diagnosis_slots = slots("I10_DX"), procedure_slots = slots("I10_PR"))
}

update_layout_metadata <- function(years = 2017:2022,
    cache = "docs/references/local/official-layouts",
    output = "inst/metadata/modern-layouts.csv", cached_only = FALSE,
    download = function(url, path) utils::download.file(url, path, mode = "wb", quiet = TRUE)) {
  if (!is.numeric(years) || !length(years) || anyNA(years) ||
      any(!years %in% 2017:2022) || anyDuplicated(years)) {
    stop("Choose unique whole years from 2017 through 2022.", call. = FALSE)
  }
  if (!is.logical(cached_only) || length(cached_only) != 1L || is.na(cached_only)) {
    stop("`cached_only` must be TRUE or FALSE.", call. = FALSE)
  }
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  previous <- options(timeout = 30)
  on.exit(options(previous), add = TRUE)
  rows <- lapply(sort(years), function(year) {
    revision <- if (year %in% c(2019L, 2020L)) "V2" else "unspecified"
    suffix <- if (revision == "V2") "_V2" else ""
    filename <- paste0("FileSpecifications_NIS_", year, "_Core", suffix, ".TXT")
    url <- paste0("https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/", filename)
    path <- file.path(cache, filename)
    if (!file.exists(path)) {
      if (cached_only) stop("Missing cached official Core specification for ", year, call. = FALSE)
      staged <- tempfile(tmpdir = cache)
      on.exit(unlink(staged), add = TRUE)
      status <- download(url, staged)
      if (!identical(status, 0L)) stop("Official layout download failed for ", year, call. = FALSE)
      parse_core_layout(readLines(staged, warn = FALSE), year, revision)
      if (!file.rename(staged, path)) stop("Could not cache validated layout.", call. = FALSE)
    }
    layout <- parse_core_layout(readLines(path, warn = FALSE), year, revision)
    data.frame(
      year = year, documented_revision = revision, core_records = layout$records,
      core_columns = nrow(layout$fields), core_record_length = layout$record_length,
      diagnosis_slots = layout$diagnosis_slots, procedure_slots = layout$procedure_slots,
      discharge_key = "KEY_NIS", hospital_key = "HOSP_NIS", stratum = "NIS_STRATUM",
      weight = "DISCWT", diagnosis_system = "ICD10CM", procedure_system = "ICD10PCS",
      source = url, parsed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      source_md5 = unname(tools::md5sum(path)), review_status = "provisional",
      stringsAsFactors = FALSE
    )
  })
  staged <- tempfile(tmpdir = dirname(output))
  on.exit(unlink(staged), add = TRUE)
  registry <- do.call(rbind, rows)
  utils::write.csv(registry, staged, row.names = FALSE)
  if (!file.rename(staged, output)) stop("Could not replace layout registry.", call. = FALSE)
  invisible(registry)
}
