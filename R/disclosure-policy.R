nis_disclosure_masks <- function(counts, hospitals, threshold) {
  count <- counts <= threshold
  hospital <- if (is.null(hospitals)) rep(FALSE, length(counts)) else hospitals < 2L
  list(count = count, hospital = hospital & !count)
}

.nis_hospital_fields <- c("YEAR", "HOSP_NIS")

nis_validate_hospital_columns <- function(.data) {
  absent <- setdiff(.nis_hospital_fields, nis_names(.data))
  if (length(absent)) {
    cli::cli_abort("Column{?s} {.val {absent}} required by `nis_cell_counts()` not found.")
  }
}

nis_validate_hospital_types <- function(data) {
  keys <- dplyr::select(dplyr::ungroup(data), tidyselect::all_of(.nis_hospital_fields))
  sql <- dbplyr::sql_render(keys)
  types <- DBI::dbGetQuery(dbplyr::remote_con(data), paste("DESCRIBE", sql))$column_type
  numeric <- grepl("^U?(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT)$|^(FLOAT|DOUBLE|DECIMAL\\()", types)
  if (!all(numeric)) {
    nis_invalid_hospital_ids()
  }
}

.nis_cell_count_valid_id <- function(value) {
  is.numeric(value) && !anyNA(value) && all(is.finite(value)) && all(value > 0)
}

nis_validate_hospital_ids <- function(.data) {
  if (!all(vapply(.data[.nis_hospital_fields], .nis_cell_count_valid_id, logical(1)))) {
    nis_invalid_hospital_ids()
  }
}

nis_invalid_hospital_ids <- function() {
  cli::cli_abort("`YEAR` and `HOSP_NIS` must contain finite positive values.")
}
