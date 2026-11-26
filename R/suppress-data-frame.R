check_suppress_columns <- function(columns, arg, x, error_call) {
  if (is.null(columns)) {
    return(character())
  }
  if (!is.character(columns) || anyNA(columns)) {
    cli::cli_abort(
      "`{arg}` must be a character vector of column names.",
      call = error_call
    )
  }
  absent <- setdiff(columns, names(x))
  if (length(absent)) {
    cli::cli_abort(
      "Column {.val {absent}} specified in `{arg}` not found in `x`.",
      call = error_call
    )
  }
  columns
}

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

validate_df_suppress_args <- function(
  x,
  count_col,
  weighted_cols,
  by,
  secondary,
  hospital_col,
  missing_count_col,
  error_call
) {
  validate_dataframe_count_col(count_col, missing_count_col, error_call)
  validate_secondary_option(secondary, error_call)
  columns <- validate_dataframe_columns(
    x,
    count_col,
    weighted_cols,
    by,
    hospital_col,
    error_call
  )
  counts <- validate_df_count_columns(
    x,
    columns$count_col,
    columns$hospital_col,
    error_call
  )
  list(
    count_col = columns$count_col,
    weighted_cols = columns$weighted_cols,
    by = columns$by,
    secondary = secondary,
    hospital_col = columns$hospital_col,
    counts = counts$counts,
    hospital_counts = counts$hospital_counts
  )
}

validate_dataframe_count_col <- function(count_col, missing_count_col, error_call) {
  invalid <- missing_count_col ||
    length(count_col) != 1L ||
    !is.character(count_col) ||
    is.na(count_col) ||
    !nzchar(count_col)
  if (invalid) {
    cli::cli_abort("`count_col` must name the unweighted-count column.", call = error_call)
  }
}

validate_secondary_option <- function(secondary, error_call) {
  invalid <- !is.logical(secondary) || length(secondary) != 1L || is.na(secondary)
  if (invalid) cli::cli_abort("`secondary` must be `TRUE` or `FALSE`.", call = error_call)
}

validate_dataframe_columns <- function(
  x,
  count_col,
  weighted_cols,
  by,
  hospital_col,
  error_call
) {
  columns <- list(
    count_col = check_suppress_columns(count_col, "count_col", x, error_call),
    weighted_cols = check_suppress_columns(
      weighted_cols,
      "weighted_cols",
      x,
      error_call
    ),
    by = check_suppress_columns(by, "by", x, error_call),
    hospital_col = check_suppress_columns(
      hospital_col,
      "hospital_col",
      x,
      error_call
    )
  )
  if (length(columns$hospital_col) > 1L) {
    cli::cli_abort("`hospital_col` must name one column.", call = error_call)
  }
  columns
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
  missing_count_col,
  error_call
) {
  args <- validate_df_suppress_args(
    x,
    count_col,
    weighted_cols,
    by,
    secondary,
    hospital_col,
    missing_count_col,
    error_call
  )
  masks <- nis_disclosure_masks(args$counts, args$hospital_counts, threshold)
  primary <- masks$count | masks$hospital
  secondary_rows <- rep(FALSE, nrow(x))
  if (args$secondary) {
    secondary_rows <- complementary_suppress_rows(x, args$counts, primary, args$by)
  }
  columns <- unique(c(args$count_col, args$weighted_cols, args$hospital_col))
  apply_dataframe_suppression(
    x,
    columns,
    masks$count,
    masks$hospital,
    secondary_rows,
    threshold
  )
}
