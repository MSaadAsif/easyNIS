# Return the year-scoped hospital identities contributing to one displayed cell.
# `spec` is produced by `survey_row_spec()` and may include `level_value`, the
# raw card level corresponding to a displayed categorical/dichotomous row.
survey_card_scalar_values <- function(cards, column, rows, error_call) {
  values <- lapply(rows, function(i) {
    value <- cards[[column]][[i]]
    if (length(value) != 1L || is.na(value)) {
      cli::cli_abort("Summary cards do not identify one valid raw `{column}` value.", call = error_call)
    }
    as.character(value)
  })
  values <- unlist(values, use.names = FALSE)
  if (length(unique(values)) != 1L) cli::cli_abort("Summary cards do not identify one consistent raw `{column}` value.", call = error_call)
  values[[1L]]
}

survey_cell_hospitals <- function(x, cards, matches, column, spec, error_call = rlang::current_call()) {
  data <- x$inputs$data$variables
  if (!is.data.frame(data)) {
    cli::cli_abort("Survey design records are unavailable for hospital counting.", call = error_call)
  }
  .nis_cell_count_validate_cols(data, character())
  if (".in_cohort" %in% names(data)) data <- dplyr::filter(data, .in_cohort)
  if (!nrow(data)) return(data.frame(YEAR = numeric(), HOSP_NIS = numeric()))

  variable <- spec$variable
  if (!variable %in% names(data)) cli::cli_abort("Summary variable `{variable}` is absent from survey records.", call = error_call)
  keep <- rep(TRUE, nrow(data))
  if (identical(spec$context, "missing")) {
    keep <- if (identical(spec$stat_name, "N_miss_unweighted")) is.na(data[[variable]]) else !is.na(data[[variable]])
  } else if (identical(spec$context, "categorical")) {
    level <- spec$level_value
    if (is.null(level)) cli::cli_abort("Cannot map displayed categorical row to a raw card level.", call = error_call)
    raw_level <- survey_card_scalar_values(cards, "variable_level", matches, error_call)
    if (!identical(raw_level, as.character(level))) cli::cli_abort("Summary card raw variable level does not match the displayed row.", call = error_call)
    keep <- !is.na(data[[variable]]) & as.character(data[[variable]]) == raw_level
  } else if (identical(spec$context, "dichotomous")) {
    value <- x$inputs$value[[variable]]
    if (is.null(value) || length(value) != 1L || is.na(value)) cli::cli_abort("Cannot map dichotomous summary to one summarized value.", call = error_call)
    keep <- !is.na(data[[variable]]) & as.character(data[[variable]]) == as.character(value)
  }
  by <- x$inputs$by
  if (length(by) && !identical(column, "stat_0")) {
    if (length(by) != 1L || !all(c("gts_column", "group1", "group1_level") %in% names(cards))) cli::cli_abort("Cannot map `{column}` to a by-group from summary cards.", call = error_call)
    group_rows <- which(cards$gts_column == column & !is.na(cards$group1))
    if (!length(group_rows)) cli::cli_abort("Cannot map `{column}` to a by-group from summary cards.", call = error_call)
    group_values <- unique(as.character(cards$group1[group_rows]))
    if (length(group_values) != 1L || !identical(group_values[[1L]], by[[1L]])) cli::cli_abort("Summary cards do not identify one valid by-group for `{column}`.", call = error_call)
    raw_group_level <- survey_card_scalar_values(cards, "group1_level", group_rows, error_call)
    keep <- keep & !is.na(data[[by[[1L]]]]) & as.character(data[[by[[1L]]]]) == raw_group_level
  }
  selected <- data[keep, , drop = FALSE]
  if (nrow(selected)) .nis_cell_count_validate_ids(selected)
  selected[, c("YEAR", "HOSP_NIS"), drop = FALSE] |> unique()
}
