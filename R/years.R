#' Inspect the year capability roadmap
#'
#' Look up separate capability states for the years in the easyNIS roadmap.
#' A target year is not a supported year. Fixture availability does not promote
#' a year to metadata-audited, synthetic-validated, or release-supported status.
#'
#' @param years Optional numeric vector of whole data years. `NULL` returns the
#'   complete roadmap. Requested years must be present in the roadmap.
#'   Duplicates are removed and results are ordered by year.
#' @param supported_only A single logical value. If `TRUE`, return only rows
#'   whose status is `"release_supported"`. Currently this returns zero rows.
#' @return A data frame with `year`, `era`, `target_stage`, `licensed_access`,
#'   `metadata_audit`, `import`, `cohorts`, `survey`, `models`, `tables`, `status`,
#'   and `evidence`. Capability fields are character strings, not booleans.
#' @export
#' @examples
#' nis_supported_years(2017:2022)
#' nis_supported_years(supported_only = TRUE)
nis_supported_years <- function(years = NULL, supported_only = FALSE) {
  if (!is.logical(supported_only) || length(supported_only) != 1L ||
      is.na(supported_only)) {
    stop("`supported_only` must be TRUE or FALSE.", call. = FALSE)
  }
  roadmap <- utils::read.csv(
    system.file("metadata", "year-support.csv", package = "easyNIS"),
    colClasses = c("integer", rep("character", 11L)),
    na.strings = "", check.names = FALSE
  )
  if (!is.null(years)) {
    validate_years(years)
    unknown <- setdiff(years, roadmap$year)
    if (length(unknown)) {
      stop("Years outside the roadmap: ", paste(unknown, collapse = ", "),
           ". No support is implied for unlisted years.", call. = FALSE)
    }
    roadmap <- roadmap[roadmap$year %in% years, , drop = FALSE]
  }
  if (supported_only) {
    roadmap <- roadmap[roadmap$status == "release_supported", , drop = FALSE]
  }
  rownames(roadmap) <- NULL
  roadmap
}

validate_years <- function(years) {
  if (!(is.integer(years) || is.double(years)) || is.object(years) || anyNA(years) ||
      any(!is.finite(years)) || any(years != floor(years))) {
    stop("`years` must contain finite, non-missing whole numeric years.",
         call. = FALSE)
  }
  invisible(years)
}
