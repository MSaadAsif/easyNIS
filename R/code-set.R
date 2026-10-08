#' Declare a versioned diagnosis or procedure code set
#'
#' Records user-supplied syntax, coding system, time applicability, and source.
#' Syntax checks do not establish that a code exists in an annual dictionary or
#' that the set defines a clinically valid condition. No clinical sets are bundled.
#'
#' @param codes A non-empty character vector. Exact ICD-10-CM codes have 3 to 7
#'   characters excluding a decimal; exact ICD-10-PCS codes have 7 characters.
#'   Prefixes can be shorter. Numeric vectors and duplicate normalized codes
#'   are rejected. Leading zeros in procedure codes are preserved.
#' @param system Either `"ICD10CM"` or `"ICD10PCS"`.
#' @param valid_years Explicit whole data years to which the entire set applies.
#' @param version,source,author Non-empty strings documenting the user's set.
#' @param match Either `"exact"` or `"prefix"`. Prefixes are literal strings,
#'   never regular expressions or SQL wildcard patterns.
#' @param normalize If `TRUE`, trim ASCII spaces, tabs and line breaks, uppercase,
#'   and remove diagnosis decimal points from both the set and observed codes.
#'   Procedure decimal points are always invalid. If `FALSE`, matching preserves raw
#'   spelling. Decimal points are only accepted after the third diagnosis character.
#' @param valid_quarters Integer quarters 1 through 4, applied in every declared
#'   year. A restricted set requires valid DQTR values when flagging. Use separate
#'   sets when time applicability differs between codes or years.
#' @return A `nis_code_set` list with original and matching codes, the declared
#'   system, applicability, matching policy, and user provenance. Review status
#'   is `"user_supplied_not_verified"`.
#' @export
#' @examples
#' codes <- nis_code_set(
#'   "A001", system = "ICD10CM", valid_years = 2022,
#'   version = "invented-example-1", source = "invented example", author = "example"
#' )
#' codes$review_status
nis_code_set <- function(codes, system, valid_years, version, source, author,
                         match = c("exact", "prefix"), normalize = FALSE,
                         valid_quarters = 1:4) {
  system <- match.arg(system, c("ICD10CM", "ICD10PCS"))
  match <- match.arg(match)
  if (!is.character(codes) || !length(codes) || anyNA(codes) || any(!nzchar(codes))) {
    stop("`codes` must be non-empty character strings without missing values.", call. = FALSE)
  }
  if (!is.logical(normalize) || length(normalize) != 1L || is.na(normalize)) {
    stop("`normalize` must be TRUE or FALSE.", call. = FALSE)
  }
  validate_years(valid_years)
  if (!length(valid_years) || any(valid_years < 1988 | valid_years > 9999)) {
    stop("Declare non-empty `valid_years` of four-digit data years from 1988 onward.",
         call. = FALSE)
  }
  validate_years(valid_quarters)
  if (!length(valid_quarters) || any(!valid_quarters %in% 1:4)) {
    stop("`valid_quarters` must contain quarters 1 through 4.", call. = FALSE)
  }
  for (field in c("version", "source", "author")) {
    check_string(get(field), field)
    if (!nzchar(trimws(get(field)))) {
      stop("`", field, "` must contain non-whitespace provenance.", call. = FALSE)
    }
  }
  syntax <- if (normalize) toupper(trimws(codes)) else codes
  matched <- if (normalize) normalize_codes(codes, system) else codes
  if (anyDuplicated(matched)) {
    stop("Duplicate codes after the selected normalization are not allowed.", call. = FALSE)
  }
  valid <- code_syntax_valid(syntax, system, match)
  if (!all(valid)) {
    stop("Code-set syntax is incompatible with ", system, " and ", match,
         " matching. Check characters, decimals, and lengths.", call. = FALSE)
  }
  structure(list(
    codes = codes, matching_codes = matched, system = system,
    valid_years = sort(unique(as.integer(valid_years))),
    valid_quarters = sort(unique(as.integer(valid_quarters))),
    version = version, source = source, author = author,
    match = match, normalize = normalize, review_status = "user_supplied_not_verified"
  ), class = "nis_code_set")
}

normalize_codes <- function(codes, system) {
  normalized <- toupper(trimws(codes))
  if (system == "ICD10CM") gsub(".", "", normalized, fixed = TRUE) else normalized
}

code_syntax_valid <- function(codes, system, matching) {
  if (system == "ICD10PCS") {
    return(grepl("^[0-9A-HJ-NP-Z]+$", codes) &
             nchar(codes) <= 7L & (matching == "prefix" | nchar(codes) == 7L))
  }
  compact <- gsub(".", "", codes, fixed = TRUE)
  decimal_ok <- !grepl(".", codes, fixed = TRUE) |
    grepl("^[A-Z][0-9][A-Z0-9]\\.[A-Z0-9]*$", codes)
  second_ok <- nchar(compact) < 2L | grepl("^[A-Z][0-9]", compact)
  grepl("^[A-Z][A-Z0-9]*$", compact) & decimal_ok & second_ok &
    nchar(compact) <= 7L & (matching == "prefix" | nchar(compact) >= 3L) &
    (matching == "prefix" | !endsWith(codes, "."))
}
