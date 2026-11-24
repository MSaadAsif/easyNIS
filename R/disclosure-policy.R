nis_disclosure_masks <- function(counts, hospitals, threshold) {
  count <- counts <= threshold
  hospital <- if (is.null(hospitals)) rep(FALSE, length(counts)) else hospitals < 2L
  list(count = count, hospital = hospital & !count)
}

nis_validate_hospital_columns <- function(.data, by = character()) {
  required <- c("YEAR", "HOSP_NIS", by)
  absent <- setdiff(required, nis_names(.data)) # nolint: object_usage_linter
  if (length(absent)) {
    cli::cli_abort("Column{?s} {.val {absent}} required by `nis_cell_counts()` not found.")
  }
}

.nis_cell_count_valid_id <- function(value) {
  is.numeric(value) && !anyNA(value) && all(is.finite(value)) && all(value > 0)
}

nis_validate_hospital_ids <- function(.data) {
  year <- .data[["YEAR"]]
  hospital <- .data[["HOSP_NIS"]]
  if (!.nis_cell_count_valid_id(year) || !.nis_cell_count_valid_id(hospital)) {
    cli::cli_abort("`YEAR` and `HOSP_NIS` must contain finite positive values.")
  }
}
