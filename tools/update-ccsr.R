#!/usr/bin/env Rscript

# Run from the package root. A release can be sourced from the HCUP download
# URL itself, a locally downloaded ZIP, mapping CSV, or reference workbook.
source(file.path("R", "ccsr.R"))

read_ccsr_release <- function(input, type) {
  scratch <- tempfile("ccsr-release-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  if (grepl("^https://", input)) {
    path <- file.path(scratch, basename(input))
    utils::download.file(input, path, mode = "wb", method = "libcurl")
    input <- path
  }
  if (grepl("[.]zip$", input, ignore.case = TRUE)) {
    manifest <- utils::unzip(input, list = TRUE)$Name
    pattern <- paste0("^", toupper(type), "CCSR.*[.]csv$")
    mapping <- manifest[grepl(pattern, basename(manifest), ignore.case = TRUE)]
    if (length(mapping) != 1L) {
      stop("The archive must contain one CCSR mapping CSV for ", type, ".", call. = FALSE)
    }
    input <- utils::unzip(input, files = mapping, exdir = scratch, junkpaths = TRUE)
  }
  raw <- read_ccsr_source(input, rlang::current_call())
  catalog <- if (grepl("[.]xlsx?$", input, ignore.case = TRUE)) read_ccsr_catalog(input)
  list(raw = raw, catalog = catalog)
}

read_ccsr_catalog <- function(input) {
  sheets <- readxl::excel_sheets(input)
  sheet <- grep("^CCSR[ _]Categories$", sheets, ignore.case = TRUE, value = TRUE)
  if (length(sheet) != 1L) {
    stop("Expected one CCSR categories sheet.", call. = FALSE)
  }
  raw <- readxl::read_excel(input, sheet = sheet, skip = 1, col_types = "text", .name_repair = "minimal")
  names(raw) <- gsub("[^a-z0-9]", "", tolower(names(raw)))
  categories <- ccsr_columns(raw, c("ccsrcategory", "ccsrcategorydescription"))
  names(categories) <- c("category", "description")
  categories <- as.data.frame(categories)
  end <- which(categories$category %in% "End of Content" & is.na(categories$description))
  if (identical(end, nrow(categories))) categories[-end, , drop = FALSE] else categories
}

ccsr_columns <- function(raw, required) {
  missing <- setdiff(required, names(raw))
  if (length(missing)) {
    stop("Missing CCSR columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  raw[required]
}

ccsr_long_release <- function(raw, type, version) {
  code_col <- if (type == "dx") "icd10cmcode" else "icd10pcscode"
  if (type == "pr" && "icd10pcs" %in% names(raw)) {
    code_col <- "icd10pcs"
  }
  if ("prccsr" %in% names(raw)) {
    names(raw)[match(c("prccsr", "prccsrdescription"), names(raw), nomatch = 0L)] <-
      c("ccsrcategory", "ccsrcategorydescription")[c("prccsr", "prccsrdescription") %in% names(raw)]
  }
  pairs <- ccsr_columns(raw, c(code_col, "ccsrcategory", "ccsrcategorydescription"))
  data.frame(
    code = pairs[[1L]],
    category = pairs[[2L]],
    description = pairs[[3L]],
    inpatient = ccsr_long_default(raw, "inpatient", type == "dx" && numeric_version(version) >= "2020.2"),
    outpatient = ccsr_long_default(raw, "outpatient", type == "dx" && numeric_version(version) >= "2021.1")
  )
}

ccsr_long_default <- function(raw, setting, required) {
  column <- grep(paste0("^", setting, "defaultccsr"), names(raw), value = TRUE)
  if (!required) {
    return(rep(NA_character_, nrow(raw)))
  }
  if (length(column) != 1L) {
    stop("Expected a CCSR default column for ", setting, ".", call. = FALSE)
  }
  raw[[column]]
}

ccsr_wide_default <- function(raw, category, column, required, sentinel) {
  if (!required) {
    return(rep(NA_character_, nrow(raw)))
  }
  default <- ccsr_columns(raw, column)[[1L]]
  if (anyNA(default) || !all(grepl("^[A-Z]{3}[0-9]{3}$", default))) {
    stop("Invalid CCSR default category in ", column, ".", call. = FALSE)
  }
  matched <- !is.na(category) & category == default
  ifelse(default == sentinel, "X", ifelse(matched, "Y", "N"))
}

ccsr_wide_release <- function(raw, version) {
  fields <- grep("^ccsrcategory[0-9]+$", names(raw), value = TRUE)
  ccsr_columns(raw, c("icd10cmcode", "ccsrcategory1", paste0(fields, "description")))
  if (anyNA(raw$ccsrcategory1) || anyDuplicated(raw$icd10cmcode)) {
    stop("Each diagnosis code needs one row with a first category.", call. = FALSE)
  }
  ip <- if ("defaultccsrcategoryip" %in% names(raw)) "defaultccsrcategoryip" else "defaultccsrcategory"
  pairs <- do.call(
    rbind,
    lapply(fields, function(field) {
      category <- raw[[field]]
      data.frame(
        code = raw$icd10cmcode,
        category = category,
        description = raw[[paste0(field, "description")]],
        inpatient = ccsr_wide_default(raw, category, ip, numeric_version(version) >= "2020.2", "XXX000"),
        outpatient = ccsr_wide_default(
          raw,
          category,
          "defaultccsrcategoryop",
          numeric_version(version) >= "2021.1",
          "XXX111"
        )
      )
    })
  )
  pairs[!is.na(pairs$category) | !is.na(pairs$description), , drop = FALSE]
}

validate_ccsr_release <- function(pairs, type, expected, catalog) {
  code_format <- if (type == "dx") "^[A-Z][0-9][A-Z0-9]{1,5}$" else "^[0-9A-HJ-NP-Z]{7}$"
  if (!nrow(pairs) || !all(grepl(code_format, pairs$code))) {
    stop("Empty mapping or invalid ICD-10 code.", call. = FALSE)
  }
  if (!all(grepl("^[A-Z]{3}[0-9]{3}$", pairs$category)) || anyNA(pairs$description)) {
    stop("Invalid or undescribed CCSR category.", call. = FALSE)
  }
  if (anyDuplicated(pairs[c("code", "category")]) || (type == "pr" && anyDuplicated(pairs$code))) {
    stop("Duplicate code-category pair or multiple categories for a procedure code.", call. = FALSE)
  }
  validate_ccsr_defaults(pairs$inpatient, pairs$code)
  validate_ccsr_defaults(pairs$outpatient, pairs$code)
  categories <- if (is.null(catalog)) {
    unique(pairs[c("category", "description")])
  } else {
    catalog[catalog$category %in% pairs$category, , drop = FALSE]
  }
  if (
    anyDuplicated(categories$category) ||
      anyNA(categories$description) ||
      !setequal(categories$category, pairs$category)
  ) {
    stop("Missing or conflicting CCSR category descriptions. Check the official workbook.", call. = FALSE)
  }
  totals <- c(codes = length(unique(pairs$code)), categories = nrow(categories), pairs = nrow(pairs))
  if (any(totals[seq_along(expected)] != expected)) {
    stop("CCSR totals differ from the expected counts: ", paste(totals, collapse = ", "), ".", call. = FALSE)
  }
  list(categories = categories, totals = totals)
}

validate_ccsr_defaults <- function(flags, codes) {
  if (all(is.na(flags))) {
    return(invisible(NULL))
  }
  if (!all(flags %in% c("Y", "N", "X")) || anyDuplicated(codes[flags == "Y"])) {
    stop("Invalid or multiple CCSR defaults for one code.", call. = FALSE)
  }
  if (!setequal(codes, codes[flags != "N"]) || any(codes[flags == "X"] %in% codes[flags != "X"])) {
    stop("Missing or conflicting CCSR default for one code.", call. = FALSE)
  }
}

ccsr_normalize_release <- function(raw, type, version, expected, catalog = NULL) {
  names(raw) <- gsub("[^a-z0-9]", "", tolower(names(raw)))
  if (anyDuplicated(names(raw))) {
    stop("Duplicate CCSR column names.", call. = FALSE)
  }
  raw[] <- lapply(raw, function(col) {
    col <- trimws(col)
    col[col %in% ""] <- NA_character_
    col
  })
  pairs <- if (type == "dx" && "ccsrcategory1" %in% names(raw)) {
    ccsr_wide_release(raw, version)
  } else {
    ccsr_long_release(raw, type, version)
  }
  checked <- validate_ccsr_release(pairs, type, expected, catalog)
  list(
    map = data.frame(type, version, pairs[c("code", "category", "inpatient", "outpatient")]),
    categories = data.frame(type, version, checked$categories),
    totals = checked$totals
  )
}

merge_ccsr_release <- function(old, new, keys) {
  replace <- old$type == new$type[1L] & old$version == new$version[1L]
  updated <- rbind(old[!replace, , drop = FALSE], new)
  updated[do.call(order, c(updated[keys], method = "radix")), , drop = FALSE]
}

write_ccsr_release <- function(dir, data, release) {
  scratch <- tempfile("ccsr-build-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  con <- DBI::dbConnect(duckdb::duckdb(), config = list(threads = 1))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (table in c("map", "categories")) {
    filename <- paste0(table, ".parquet")
    path <- file.path(dir, filename)
    old <- if (file.exists(path)) {
      DBI::dbGetQuery(con, paste0("SELECT * FROM read_parquet(", DBI::dbQuoteString(con, path), ")"))
    } else {
      data[[table]][0L, ]
    }
    keys <- intersect(c("type", "version", "code", "category"), names(old))
    updated <- merge_ccsr_release(old, data[[table]], keys)
    duckdb::duckdb_register(con, "ccsr_update", updated)
    DBI::dbExecute(
      con,
      paste(
        "COPY ccsr_update TO",
        DBI::dbQuoteString(con, file.path(scratch, filename)),
        "(FORMAT PARQUET, COMPRESSION ZSTD)"
      )
    )
    duckdb::duckdb_unregister(con, "ccsr_update")
  }
  index <- file.path(dir, "releases.csv")
  old <- if (file.exists(index)) utils::read.csv(index, colClasses = "character") else release[0L, ]
  releases <- merge_ccsr_release(old, release, c("type", "version"))
  utils::write.csv(releases, file.path(scratch, "releases.csv"), row.names = FALSE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (!all(file.copy(list.files(scratch, full.names = TRUE), dir, overwrite = TRUE))) {
    stop("Could not write the updated CCSR data.", call. = FALSE)
  }
}

update_ccsr <- function(args) {
  if (length(args) < 4L || length(args) > 8L) {
    stop(
      paste(
        "Usage: Rscript --vanilla tools/update-ccsr.R <dx|pr> <version> <release date>",
        "<official download URL> [local file] [expected codes] [expected categories] [expected pairs]"
      ),
      call. = FALSE
    )
  }
  type <- match.arg(args[1L], c("dx", "pr"))
  version <- args[2L]
  released <- args[3L]
  source <- args[4L]
  if (
    !grepl("^20[0-9]{2}[.][1-9][0-9]*$", version) ||
      is.na(as.Date(released, format = "%Y-%m-%d")) ||
      !grepl("^https://hcup-us[.]ahrq[.]gov/", source)
  ) {
    stop("Supply a CCSR version, ISO release date, and official HCUP URL.", call. = FALSE)
  }
  input <- if (length(args) > 4L && args[5L] != "-") args[5L] else source
  expected <- as.integer(args[-seq_len(min(5L, length(args)))])
  if (anyNA(expected) || any(expected < 1L)) {
    stop("Expected totals must be positive integers.", call. = FALSE)
  }
  reference <- read_ccsr_release(input, type)
  data <- ccsr_normalize_release(reference$raw, type, version, expected, reference$catalog)
  release <- data.frame(type, version, released, as.list(data$totals), source)
  write_ccsr_release(file.path("inst", "ccsr"), data, release)
  print(release, row.names = FALSE)
}

if (sys.nframe() == 0L) {
  update_ccsr(commandArgs(trailingOnly = TRUE))
}
