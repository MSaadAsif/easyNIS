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
#' \dontrun{
#' codes <- nis_ccsr_codes("DXCCSR-Reference-File-v2025-1.xlsx", "CIR019")
#' nis_open("path/to/nis") |>
#'   nis_flag_dx(heart_failure = codes)
#' }
#' @export
nis_ccsr_codes <- function(file, categories, default_only = FALSE) {
  if (!is.character(categories) || length(categories) == 0L ||
      anyNA(categories) || any(!nzchar(trimws(categories)))) {
    cli::cli_abort("`categories` must be a non-empty character vector.")
  }
  if (!is.logical(default_only) || length(default_only) != 1L ||
      is.na(default_only)) {
    cli::cli_abort("`default_only` must be `TRUE` or `FALSE`.")
  }

  map <- read_ccsr_map(file)
  categories <- unique(toupper(trimws(categories)))
  unknown <- setdiff(categories, map$category)
  if (length(unknown) > 0L) {
    cli::cli_abort("Categor{?y/ies} {.val {unknown}} not found in {.arg file}.")
  }
  if (default_only) {
    if (all(is.na(map$default))) {
      cli::cli_abort(
        "`file` has no default inpatient category; use `default_only = FALSE`."
      )
    }
    map <- map[map$default %in% TRUE, , drop = FALSE]
  }
  sort(unique(map$code[map$category %in% categories]))
}

# Returns one row per code-category pair: code, category, and `default`
# (TRUE for the default inpatient category, NA when the file has none).
read_ccsr_map <- function(file) {
  if (!is.character(file) || length(file) != 1L || is.na(file) ||
      !file.exists(file)) {
    cli::cli_abort("`file` must name an existing CCSR reference file.")
  }
  raw <- if (grepl("[.]xlsx?$", file, ignore.case = TRUE)) {
    read_ccsr_sheet(file)
  } else {
    utils::read.csv(file, colClasses = "character", check.names = FALSE,
      fileEncoding = "UTF-8-BOM", na.strings = character())
  }

  key <- gsub("[^a-z0-9]", "", tolower(names(raw)))
  code_col <- grep("^icd10(cm|pcs)(code)?$", key)
  category_cols <- grep("^(ccsrcategory|prccsr)[0-9]*$", key)
  if (length(code_col) == 0L || length(category_cols) == 0L) {
    cli::cli_abort(
      "`file` does not look like an HCUP DXCCSR or PRCCSR reference file."
    )
  }

  clean <- function(x) {
    x <- gsub("^[[:space:]']+|[[:space:]']+$", "", x)
    x[!nzchar(x)] <- NA_character_
    toupper(x)
  }
  code <- gsub("[.[:space:]]", "", clean(raw[[code_col[1L]]]))
  long_default <- grep("^inpatientdefaultccsr", key)
  wide_default <- grep("^defaultccsrcategoryip$", key)

  pairs <- lapply(category_cols, function(col) {
    category <- clean(raw[[col]])
    default <- if (length(long_default) > 0L) {
      clean(raw[[long_default[1L]]]) %in% "Y"
    } else if (length(wide_default) > 0L) {
      default_category <- clean(raw[[wide_default[1L]]])
      !is.na(category) & !is.na(default_category) & category == default_category
    } else {
      NA
    }
    data.frame(code = code, category = category, default = default)
  })
  map <- do.call(rbind, pairs)
  map[!is.na(map$code) & !is.na(map$category), , drop = FALSE]
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
