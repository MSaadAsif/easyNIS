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
    masked <- rows[primary[rows]]
    if (length(masked) != 1L || length(rows) < 2L) {
      next
    }
    candidates <- rows[!primary[rows] & counts[rows] > 0]
    if (length(candidates)) {
      secondary_rows[candidates[[which.min(counts[candidates])]]] <- TRUE
    }
  }
  secondary_rows
}

apply_dataframe_suppression <- function(
  x,
  columns,
  count_primary,
  hospital_primary,
  secondary_rows,
  threshold
) {
  for (column in columns) {
    values <- as.character(x[[column]])
    values[count_primary] <- paste0("\u2264", threshold)
    values[hospital_primary] <- "<2 hospitals"
    values[secondary_rows] <- "Masked"
    x[[column]] <- values
  }
  x
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
  primary <- masks$count | masks$hospital
  secondary_rows <- if (secondary) {
    complementary_suppress_rows(x, counts$counts, primary, by)
  } else {
    rep(FALSE, nrow(x))
  }
  columns <- unique(c(count_col, weighted_cols, hospital_col))
  apply_dataframe_suppression(
    x,
    columns,
    masks$count,
    masks$hospital,
    secondary_rows,
    threshold
  )
}
