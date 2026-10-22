#' ICD-10 codes in HCUP CCSR categories
#'
#' Reads the official HCUP DXCCSR or PRCCSR reference file that you download
#' yourself and returns the full ICD-10-CM or ICD-10-PCS codes assigned to the
#' requested categories. Pass the result to [nis_flag_dx()] or [nis_flag_pr()],
#' which treat each code as a prefix. easyNIS does not ship or download any
#' CCSR content, and the code lists depend on the reference file version you
#' supply.
#'
#' The reference file may be the HCUP Excel workbook (`.xlsx`, which needs
#' the readxl package) or the HCUP comma-separated file. Excel files are read
#' from the `DX_to_CCSR_Mapping` or `PR_to_CCSR_Mapping` sheet. Comma-separated
#' files use the wide layout with `CCSR CATEGORY 1`, `CCSR CATEGORY 2`, and so
#' on. A code mapped to a category in any of those columns is returned.
#'
#' With `default_only = TRUE`, only codes whose default inpatient CCSR
#' category is one of `categories` are returned. This matches the HCUP
#' assignment of a single category to a principal diagnosis, so combine it
#' with `position = "principal"` in [nis_flag_dx()]. Procedure reference files
#' have no default assignment.
#'
#' UNVERIFIED: the file layouts above are assumed from secondhand descriptions
#' of HCUP downloads, not checked against a current release. The single-quoted
#' CSV reader checks row field counts; all supported formats check that codes
#' look like ICD-10 codes (3 to 7 letters or digits). Check the returned codes
#' against your reference file before you rely on them.
#'
#' This function is experimental.
#'
#' @param file Path to the HCUP CCSR reference file.
#' @param categories Character vector of CCSR category codes, such as
#'   `"CIR019"`. Matching ignores case.
#' @param default_only If `TRUE`, keep only codes whose default inpatient
#'   category is in `categories`. Diagnosis reference files only.
#'
#' @return A sorted character vector of unique codes without periods.
#' @examples
#' # An invented reference file in the HCUP comma-separated layout. Download
#' # the real DXCCSR file from HCUP and pass its path instead.
#' reference <- tempfile(fileext = ".csv")
#' writeLines(c(
#'   "'ICD-10-CM CODE','CCSR CATEGORY 1','CCSR CATEGORY 2','DEFAULT CCSR CATEGORY IP'",
#'   "'I5022','CIR019','','CIR019'",
#'   "'I509','CIR019','','CIR019'",
#'   "'E119','END002','','END002'"
#' ), reference)
#' codes <- nis_ccsr_codes(reference, "CIR019")
#' codes
#'
#' nis_open(nis_example(years = 2019)) |>
#'   nis_flag_dx(heart_failure = codes) |>
#'   dplyr::count(heart_failure) |>
#'   dplyr::collect()
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
nis_ccsr_codes <- function(file, categories, default_only = FALSE) {
  categories <- validate_ccsr_categories(categories)
  validate_ccsr_default_only(default_only)

  map <- read_ccsr_map(file)
  validate_ccsr_category_names(categories, map$category)
  map <- filter_ccsr_defaults(map, default_only)

  sort(unique(map$code[map$category %in% categories]))
}

validate_ccsr_categories <- function(categories) {
  if (!is.character(categories) || length(categories) == 0L ||
      anyNA(categories) || any(!nzchar(trimws(categories)))) {
    cli::cli_abort("`categories` must be a non-empty character vector.")
  }
  unique(toupper(trimws(categories)))
}

validate_ccsr_default_only <- function(default_only) {
  if (!is.logical(default_only) || length(default_only) != 1L ||
      is.na(default_only)) {
    cli::cli_abort("`default_only` must be `TRUE` or `FALSE`.")
  }
}

validate_ccsr_category_names <- function(categories, available) {
  unknown <- setdiff(categories, available)
  if (length(unknown) > 0L) {
    cli::cli_abort("Categor{?y/ies} {.val {unknown}} not found in {.arg file}.")
  }
}

filter_ccsr_defaults <- function(map, default_only) {
  if (default_only) {
    if (all(is.na(map$default))) {
      cli::cli_abort(
        "`file` has no default inpatient category; use `default_only = FALSE`."
      )
    }
    map[map$default %in% TRUE, , drop = FALSE]
  } else {
    map
  }
}

# Returns one row per code-category pair: code, category, and `default`
# (TRUE for the default inpatient category, NA when the file has none).
read_ccsr_map <- function(file) {
  validate_ccsr_file(file)
  raw <- read_ccsr_source(file)
  columns <- find_ccsr_columns(names(raw))
  code <- clean_ccsr_codes(raw[[columns$code]])
  map <- do.call(rbind, lapply(columns$category, function(col) {
    read_ccsr_category_pairs(raw, code, col, columns)
  }))
  map[!is.na(map$code) & !is.na(map$category), , drop = FALSE]
}

validate_ccsr_file <- function(file) {
  if (!is.character(file) || length(file) != 1L || is.na(file) ||
      !file.exists(file)) {
    cli::cli_abort("`file` must name an existing CCSR reference file.")
  }
}

read_ccsr_source <- function(file) {
  if (grepl("[.]xlsx?$", file, ignore.case = TRUE)) {
    read_ccsr_sheet(file)
  } else {
    read_ccsr_csv(file)
  }
}

find_ccsr_columns <- function(column_names) {
  key <- gsub("[^a-z0-9]", "", tolower(column_names))
  code_col <- grep("^icd10(cm|pcs)(code)?$", key)
  category_cols <- grep("^(ccsrcategory|prccsr)[0-9]*$", key)
  if (length(code_col) == 0L || length(category_cols) == 0L) {
    cli::cli_abort(
      "`file` does not look like an HCUP DXCCSR or PRCCSR reference file."
    )
  }
  list(
    code = code_col[1L],
    category = category_cols,
    long_default = grep("^inpatientdefaultccsr", key),
    wide_default = grep("^defaultccsrcategoryip$", key)
  )
}

clean_ccsr_value <- function(x) {
  x <- gsub("^[[:space:]']+|[[:space:]']+$", "", x)
  x[!nzchar(x)] <- NA_character_
  toupper(x)
}

clean_ccsr_codes <- function(x) {
  code <- gsub("[.[:space:]]", "", clean_ccsr_value(x))
  bad <- unique(code[!is.na(code) & !grepl("^[A-Z0-9]{3,7}$", code)])
  if (length(bad) > 0L) {
    cli::cli_abort(c(
      "`file` has values in its code column that are not ICD-10 codes.",
      "x" = "First offending value{?s}: {.val {utils::head(bad, 3L)}}",
      "i" = "The file may be malformed or in an unsupported layout."
    ))
  }
  code
}

read_ccsr_category_pairs <- function(raw, code, column, columns) {
  category <- clean_ccsr_value(raw[[column]])
  default <- ccsr_default_flag(raw, category, columns)
  data.frame(code = code, category = category, default = default)
}

ccsr_default_flag <- function(raw, category, columns) {
  if (length(columns$long_default) > 0L) {
    clean_ccsr_value(raw[[columns$long_default[1L]]]) %in% "Y"
  } else if (length(columns$wide_default) > 0L) {
    default_category <- clean_ccsr_value(raw[[columns$wide_default[1L]]])
    !is.na(category) & !is.na(default_category) & category == default_category
  } else {
    NA
  }
}

# HCUP comma-separated files wrap every field in single quotes, and
# descriptions can contain commas and apostrophes. A field boundary is
# therefore the three-character sequence ',' rather than a bare comma.
# Files without that wrapping fall back to standard CSV parsing.
read_ccsr_csv <- function(file) {
  lines <- readLines(file, encoding = "UTF-8", warn = FALSE)
  lines <- sub("^\ufeff", "", lines)
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0L) {
    cli::cli_abort("`file` is empty.")
  }
  if (!grepl("^'.*'$", lines[1L])) {
    return(utils::read.csv(text = lines, colClasses = "character",
      check.names = FALSE, na.strings = character()))
  }
  sentinel <- "\001"
  fields <- lapply(lines, function(line) {
    inner <- substr(line, 2L, nchar(line) - 1L)
    parts <- strsplit(paste0(inner, sentinel), "','", fixed = TRUE)[[1L]]
    parts[length(parts)] <- sub(sentinel, "", parts[length(parts)], fixed = TRUE)
    parts
  })
  width <- lengths(fields)
  wrong <- which(width != width[1L] | !grepl("^'.*'$", lines))
  if (length(wrong) > 0L) {
    # nolint start: object_usage_linter. Used by cli interpolation below.
    shown <- utils::head(wrong, 3L)
    expected <- width[1L]
    # nolint end
    cli::cli_abort(c(
      "`file` is not a well-formed single-quoted CSV.",
      "x" = "Line {shown} should have {expected} quoted fields like the header."
    ))
  }
  body <- as.data.frame(do.call(rbind, fields[-1L]), stringsAsFactors = FALSE)
  if (nrow(body) == 0L) {
    body <- as.data.frame(matrix(character(), 0L, width[1L]))
  }
  names(body) <- fields[[1L]]
  body
}

# HCUP workbooks put title rows above the header, so find the header row.
read_ccsr_sheet <- function(file) {
  rlang::check_installed("readxl", "to read HCUP Excel reference files.")
  sheets <- readxl::excel_sheets(file)
  sheet <- grep("^(DX|PR)_to_CCSR_Mapping$", sheets, value = TRUE,
    ignore.case = TRUE)
  if (length(sheet) != 1L) {
    cli::cli_abort(
      "`file` needs one `DX_to_CCSR_Mapping` or `PR_to_CCSR_Mapping` sheet."
    )
  }
  cells <- suppressMessages(readxl::read_excel(file, sheet = sheet,
    col_names = FALSE, col_types = "text"))
  header <- which(grepl("^ICD-?10", cells[[1L]], ignore.case = TRUE))[1L]
  if (is.na(header)) {
    cli::cli_abort("No header row starting with `ICD-10` was found in `file`.")
  }
  body <- as.data.frame(cells[-seq_len(header), , drop = FALSE],
    stringsAsFactors = FALSE)
  names(body) <- unlist(cells[header, ], use.names = FALSE)
  body
}
