validate_survey_suppress_input <- function(x, error_call) {
  valid <- inherits(x, "tbl_svysummary") && !is.null(x$cards$tbl_svysummary)
  if (!valid) {
    cli::cli_abort(
      "`.data` must be a data frame or a table created by `gtsummary::tbl_svysummary()`.",
      call = error_call
    )
  }
}

validate_survey_suppress_args <- function(
  count_col,
  weighted_cols,
  by,
  hospital_col,
  secondary,
  missing_count_col,
  error_call
) {
  data_frame_only <- !missing_count_col || !is.null(weighted_cols) || !is.null(by) || !is.null(hospital_col)
  if (data_frame_only) {
    cli::cli_abort(
      "`count_col`, `weighted_cols`, `by`, and `hospital_col` apply only to data frames.",
      call = error_call
    )
  }
  if (!identical(secondary, TRUE)) {
    cli::cli_abort("`secondary` applies only to data frames.", call = error_call)
  }
}

survey_suppress_cards <- function(x) {
  cards <- x$cards$tbl_svysummary
  if (!is.null(x$cards$add_overall)) {
    cards <- dplyr::bind_rows(cards, x$cards$add_overall)
  }
  cards
}

survey_row_spec <- function(body, row, cards, card_variable_level) {
  if (!all(c("variable", "row_type", "var_type") %in% names(body))) {
    return(NULL)
  }
  variable <- body$variable[[row]]
  row_type <- body$row_type[[row]]
  var_type <- body$var_type[[row]]
  if (!survey_row_metadata_valid(variable, row_type, var_type)) {
    return(NULL)
  }
  survey_row_spec_by_type(body, row, variable, row_type, var_type, cards, card_variable_level)
}

survey_row_metadata_valid <- function(variable, row_type, var_type) {
  !is.na(variable) && nzchar(trimws(variable)) && !is.na(row_type) && !is.na(var_type) && nzchar(trimws(var_type))
}

survey_row_spec_by_type <- function(body, row, variable, row_type, var_type, cards, card_variable_level) {
  if (identical(row_type, "level")) {
    return(survey_level_row_spec(
      body,
      row,
      variable,
      var_type,
      cards,
      card_variable_level
    ))
  }
  if (identical(row_type, "missing")) {
    return(survey_missing_row_spec(variable, cards))
  }
  if (identical(row_type, "label")) {
    return(survey_label_row_spec(variable, var_type, cards))
  }
  NULL
}

survey_cell_mask_result <- function(body, column, row, masks, threshold) {
  masked <- any(masks$count | masks$hospital)
  if (masks$count[[1L]]) {
    body[[column]][[row]] <- paste0("\u2264", threshold)
  } else if (masks$hospital[[1L]]) {
    body[[column]][[row]] <- "<2 hospitals"
  } else if (masked) {
    body[[column]][[row]] <- "Masked"
  }
  overall <- identical(column, "stat_0")
  list(body = body, group_masked = masked && !overall, overall_masked = masked && overall)
}

survey_level_row_spec <- function(
  body,
  row,
  variable,
  var_type,
  cards,
  card_variable_level
) {
  if (identical(var_type, "continuous2")) {
    return(list(
      variable = variable,
      context = "missing",
      stat_name = "N_nonmiss_unweighted",
      level_index = rep(TRUE, nrow(cards)),
      continuous2 = TRUE
    ))
  }
  context <- if (identical(var_type, "dichotomous")) "dichotomous" else "categorical"
  level_value <- survey_card_level_value(cards, variable, context, card_variable_level, body$label[[row]])
  if (is.null(level_value)) {
    cli::cli_abort(paste0(
      "Cannot verify the raw level for displayed `",
      variable,
      "` statistic labeled `",
      body$label[[row]],
      "`. Restore the original gtsummary level label."
    ))
  }
  list(
    variable = variable,
    context = context,
    stat_name = "n_unweighted",
    level_index = survey_level_index(card_variable_level, body$label[[row]]),
    level_value = level_value,
    continuous2 = FALSE
  )
}

survey_card_level_value <- function(cards, variable, context, levels, label) {
  idx <- which(
    cards$variable == variable &
      cards$context == context &
      cards$stat_name == "n_unweighted" &
      levels == as.character(label)
  )
  values <- unique(levels[idx])
  if (length(values) == 1L) values[[1L]] else NULL
}

survey_missing_row_spec <- function(variable, cards) {
  list(
    variable = variable,
    context = "missing",
    stat_name = "N_miss_unweighted",
    level_index = rep(TRUE, nrow(cards)),
    continuous2 = FALSE
  )
}

survey_label_row_spec <- function(variable, var_type, cards) {
  if (identical(var_type, "continuous")) {
    return(list(
      variable = variable,
      context = "missing",
      stat_name = "N_nonmiss_unweighted",
      level_index = rep(TRUE, nrow(cards)),
      continuous2 = FALSE
    ))
  }
  if (identical(var_type, "dichotomous")) {
    return(list(
      variable = variable,
      context = "dichotomous",
      stat_name = "n_unweighted",
      level_index = rep(TRUE, nrow(cards)),
      continuous2 = FALSE
    ))
  }
  NULL
}

survey_variable_levels <- function(cards) {
  if ("variable_level" %in% names(cards)) {
    vapply(
      cards[["variable_level"]],
      function(value) {
        if (length(value) == 0L) "" else as.character(value[[1L]])
      },
      character(1)
    )
  } else {
    rep(NA_character_, nrow(cards))
  }
}

survey_level_index <- function(card_variable_level, level) {
  card_variable_level == level
}

survey_continuous2_blank <- function(cell) {
  length(cell) == 0L ||
    (length(cell) == 1L &&
      (is.na(cell) || (is.character(cell) && !nzchar(trimws(cell)))))
}

survey_card_matches <- function(cards, spec, column) {
  matches <- which(
    cards$variable == spec$variable &
      cards$context == spec$context &
      cards$stat_name == spec$stat_name &
      cards$gts_column == column &
      spec$level_index
  )
  if (length(matches) == 0L && identical(column, "stat_0") && !spec$continuous2) {
    matches <- which(
      cards$variable == spec$variable &
        cards$context == spec$context &
        cards$stat_name == spec$stat_name &
        grepl("^stat_[1-9][0-9]*$", cards$gts_column) &
        spec$level_index
    )
  }
  matches
}

survey_card_count <- function(cards, matches, spec, column, error_call) {
  count <- if (length(matches) == 1L) {
    suppressWarnings(as.numeric(unlist(cards$stat[[matches]], use.names = FALSE)))
  } else {
    numeric()
  }
  if (length(count) == 1L && is.finite(count) && count >= 0 && count == floor(count)) {
    return(count)
  }
  variable <- spec$variable
  if (spec$continuous2) {
    cli::cli_abort(
      paste0(
        "Cannot verify the non-missing count for continuous2 statistic `",
        variable,
        "` in `",
        column,
        "`. Keep exactly one finite ",
        "`N_nonmiss_unweighted` card for that variable and column."
      ),
      call = error_call
    )
  }
  cli::cli_abort(
    paste0(
      "Cannot verify the unweighted count for `",
      variable,
      "` in `",
      column,
      "`."
    ),
    call = error_call
  )
}

survey_cell_suppression <- function(x, records, body, cards, row, column, spec, threshold, error_call) {
  cell <- body[[column]][[row]]
  if (spec$continuous2 && survey_continuous2_blank(cell)) {
    return(list(body = body, group_masked = FALSE, overall_masked = FALSE))
  }
  matches <- survey_card_matches(cards, spec, column)
  count <- survey_card_count(cards, matches, spec, column, error_call)
  evidence <- survey_cell_evidence(x, records, cards, matches, column, spec, error_call)
  evidence$n[[1L]] <- min(count, evidence$n[[1L]])
  masks <- nis_disclosure_masks(evidence$n, evidence$hospitals, threshold)
  survey_cell_mask_result(body, column, row, masks, threshold)
}

survey_stat_displayed <- function(body, row, stat_columns) {
  any(vapply(
    stat_columns,
    function(column) {
      value <- body[[column]][[row]]
      length(value) > 0L && !all(is.na(value)) && !(is.character(value) && !any(nzchar(trimws(value))))
    },
    logical(1)
  ))
}

survey_row_mapping_error <- function(body, row, row_type, error_call) {
  variable <- if ("variable" %in% names(body)) body$variable[[row]] else NA_character_
  description <- if (length(row_type) == 1L && !is.na(row_type)) {
    row_type
  } else {
    "missing or unsupported"
  }
  cli::cli_abort(
    paste0(
      "Cannot verify the statistic mapping for displayed row `",
      description,
      "` in `",
      variable,
      "`."
    ),
    call = error_call
  )
}

suppress_survey_row <- function(
  x,
  records,
  body,
  cards,
  row,
  spec,
  stat_columns,
  threshold,
  error_call
) {
  group_masked <- FALSE
  overall_primary_masked <- FALSE
  for (column in stat_columns) {
    result <- survey_cell_suppression(
      x,
      records,
      body,
      cards,
      row,
      column,
      spec,
      threshold,
      error_call
    )
    body <- result$body
    group_masked <- group_masked || result$group_masked
    overall_primary_masked <- overall_primary_masked || result$overall_masked
  }
  if (group_masked && "stat_0" %in% stat_columns && !overall_primary_masked) {
    body$stat_0[[row]] <- "Masked"
  }
  body
}

suppress_survey_table <- function(x, threshold, error_call) {
  body <- x$table_body
  cards <- survey_suppress_cards(x)
  records <- survey_hospital_cohort_records(x, error_call)
  card_variable_level <- survey_variable_levels(cards)
  stat_columns <- grep("^stat_[0-9]+$", names(body), value = TRUE)
  for (row in seq_len(nrow(body))) {
    displayed_stat <- survey_stat_displayed(body, row, stat_columns)
    row_type <- if ("row_type" %in% names(body)) body$row_type[[row]] else NA_character_
    spec <- survey_row_spec(body, row, cards, card_variable_level)
    if (displayed_stat && is.null(spec)) {
      survey_row_mapping_error(body, row, row_type, error_call)
    }
    if (is.null(spec)) {
      next
    }
    body <- suppress_survey_row(
      x,
      records,
      body,
      cards,
      row,
      spec,
      stat_columns,
      threshold,
      error_call
    )
  }
  x <- gtsummary::modify_table_body(x, function(table_body) body)
  gtsummary::modify_footnote_header(
    x,
    footnote = paste0(
      "Statistics based on unweighted n \u2264",
      threshold,
      " are marked \u2264",
      threshold,
      "; cells contributed by fewer than two distinct year-scoped hospitals ",
      "are marked '<2 hospitals', regardless of count. The discharge-count ",
      "mask takes precedence when both rules apply.",
      " Dichotomous rows with a protected complement are marked 'Masked' ",
      "when the displayed event passes both rules.",
      if ("stat_0" %in% stat_columns) {
        paste0(
          " Overall cells in rows with a masked by-group cell are marked ",
          "'Masked' unless their own count is at or below the threshold; ",
          "overall cells with a primary mask show their applicable primary ",
          "mask."
        )
      },
      " Other derivable cells are not masked; review tables for other ",
      "derivable cells before sharing ",
      "under the HCUP Data Use Agreement."
    ),
    columns = gtsummary::all_stat_cols(),
    replace = FALSE,
    text_interpret = "html"
  )
}

survey_card_scalar_values <- function(cards, column, rows, error_call) {
  values <- lapply(rows, function(i) {
    value <- cards[[column]][[i]]
    if (length(value) != 1L || is.na(value)) {
      cli::cli_abort("Summary cards do not identify one valid raw `{column}` value.", call = error_call)
    }
    as.character(value)
  })
  values <- unlist(values, use.names = FALSE)
  if (length(unique(values)) != 1L) {
    cli::cli_abort(
      "Summary cards do not identify one consistent raw `{column}` value.",
      call = error_call
    )
  }
  values[[1L]]
}

survey_hospital_cohort_records <- function(x, error_call) {
  data <- x$inputs$data$variables
  if (!is.data.frame(data)) {
    cli::cli_abort("Survey design records are unavailable for hospital counting.", call = error_call)
  }
  nis_validate_hospital_columns(data)
  nis_cohort_records(data)
}

survey_hospital_var_records <- function(data, x, cards, matches, spec, error_call) {
  variable <- spec$variable
  if (!variable %in% names(data)) {
    cli::cli_abort("Summary variable `{variable}` is absent from survey records.", call = error_call)
  }
  if (identical(spec$context, "missing")) {
    return(survey_hosp_missing(data, variable, spec))
  }
  if (identical(spec$context, "categorical")) {
    return(survey_hosp_categorical(data, variable, cards, matches, spec, error_call))
  }
  if (identical(spec$context, "dichotomous")) {
    return(survey_hosp_dichotomous(data, x, variable, error_call))
  }
  rep(TRUE, nrow(data))
}

survey_hosp_missing <- function(data, variable, spec) {
  if (identical(spec$stat_name, "N_miss_unweighted")) is.na(data[[variable]]) else !is.na(data[[variable]])
}

survey_hosp_categorical <- function(data, variable, cards, matches, spec, error_call) {
  level <- spec$level_value
  if (is.null(level)) {
    cli::cli_abort("Cannot map displayed categorical row to a raw card level.", call = error_call)
  }
  raw_level <- survey_card_scalar_values(cards, "variable_level", matches, error_call)
  if (!identical(raw_level, as.character(level))) {
    cli::cli_abort("Summary card raw variable level does not match the displayed row.", call = error_call)
  }
  !is.na(data[[variable]]) & as.character(data[[variable]]) == raw_level
}

survey_hosp_dichotomous <- function(data, x, variable, error_call) {
  value <- x$inputs$value[[variable]]
  if (is.null(value) || length(value) != 1L || is.na(value)) {
    cli::cli_abort("Cannot map dichotomous summary to one summarized value.", call = error_call)
  }
  data[[variable]] %in% value
}

survey_hospital_group_records <- function(data, x, cards, column, keep, error_call) {
  by <- x$inputs$by
  if (!length(by) || identical(column, "stat_0")) {
    return(keep)
  }
  if (length(by) != 1L || !all(c("gts_column", "group1", "group1_level") %in% names(cards))) {
    cli::cli_abort("Cannot map `{column}` to a by-group from summary cards.", call = error_call)
  }
  group_rows <- which(cards$gts_column == column & !is.na(cards$group1))
  if (!length(group_rows)) {
    cli::cli_abort("Cannot map `{column}` to a by-group from summary cards.", call = error_call)
  }
  group_values <- unique(as.character(cards$group1[group_rows]))
  if (length(group_values) != 1L || !identical(group_values[[1L]], by[[1L]])) {
    cli::cli_abort("Summary cards do not identify one valid by-group for `{column}`.", call = error_call)
  }
  raw_level <- survey_card_scalar_values(cards, "group1_level", group_rows, error_call)
  keep & !is.na(data[[by[[1L]]]]) & as.character(data[[by[[1L]]]]) == raw_level
}

survey_cell_evidence <- function(x, data, cards, matches, column, spec, error_call) {
  if (!nrow(data)) {
    return(list(n = 0L, hospitals = 0L))
  }
  selected <- survey_hospital_var_records(data, x, cards, matches, spec, error_call)
  group <- survey_hospital_group_records(data, x, cards, column, rep(TRUE, nrow(data)), error_call)
  evidence <- survey_record_counts(data[group & selected, c("YEAR", "HOSP_NIS"), drop = FALSE])
  if (identical(spec$context, "dichotomous")) {
    complement <- group & !selected & !is.na(data[[spec$variable]])
    other <- survey_record_counts(data[complement, c("YEAR", "HOSP_NIS"), drop = FALSE])
    evidence <- Map(c, evidence, other)
  }
  evidence
}

survey_record_counts <- function(selected) {
  nis_validate_hospital_ids(selected)
  list(n = nrow(selected), hospitals = dplyr::n_distinct(selected$YEAR, selected$HOSP_NIS))
}
