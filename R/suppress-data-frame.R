validate_suppress_counts <- function(counts, arg, error_call) {
  if (!is.numeric(counts)) {
    cli::cli_abort("`{arg}` must refer to a numeric column.", call = error_call)
  }
  invalid <- anyNA(counts) || !all(is.finite(counts)) || any(counts < 0) || any(counts != floor(counts))
  if (invalid) {
    cli::cli_abort(
      "`{arg}` must contain finite, non-negative whole counts without missing values.",
      call = error_call
    )
  }
}

validate_dataframe_count_columns <- function(count_col, hospital_col, error_call) {
  if (length(count_col) != 1L) {
    cli::cli_abort("`count_col` must name the unweighted-count column.", call = error_call)
  }
  if (length(hospital_col) > 1L) {
    cli::cli_abort("`hospital_col` must name one column.", call = error_call)
  }
}

validate_secondary_option <- function(secondary, error_call) {
  invalid <- !is.logical(secondary) || length(secondary) != 1L || is.na(secondary)
  if (invalid) cli::cli_abort("`secondary` must be `TRUE` or `FALSE`.", call = error_call)
}

validate_df_count_columns <- function(x, count_col, hospital_col, error_call) {
  counts <- x[[count_col]]
  validate_suppress_counts(counts, "count_col", error_call)
  hospital_counts <- NULL
  if (length(hospital_col)) {
    hospital_counts <- x[[hospital_col]]
    validate_suppress_counts(hospital_counts, "hospital_col", error_call)
  }
  list(counts = counts, hospital_counts = hospital_counts)
}

complementary_suppress_rows <- function(x, counts, primary, by) {
  secondary_rows <- rep(FALSE, nrow(x))
  if (!any(primary)) {
    return(secondary_rows)
  }
  groups <- dplyr::group_by(x, dplyr::across(dplyr::all_of(by)))
  for (rows in dplyr::group_rows(groups)) {
    companion <- nis_disclosure_companion(counts[rows], primary[rows])
    secondary_rows[rows[companion]] <- TRUE
  }
  secondary_rows
}

suppress_dataframe <- function(
  x,
  threshold,
  count_col,
  weighted_cols,
  by,
  secondary,
  hospital_col,
  error_call
) {
  validate_secondary_option(secondary, error_call)
  counts <- validate_df_count_columns(x, count_col, hospital_col, error_call)
  masks <- nis_disclosure_masks(counts$counts, counts$hospital_counts, threshold)
  display <- nis_disclosure_display(masks, threshold)
  if (secondary) {
    secondary_rows <- complementary_suppress_rows(x, counts$counts, !is.na(display), by)
    display[secondary_rows] <- .nis_disclosure_secondary_label
  }
  columns <- unique(c(count_col, weighted_cols, hospital_col))
  masked <- !is.na(display)
  for (column in columns) {
    values <- as.character(x[[column]])
    values[masked] <- display[masked]
    x[[column]] <- values
  }
  x
}
