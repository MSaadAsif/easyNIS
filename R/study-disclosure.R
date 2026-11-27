nis_study_mask <- function(n, hospitals, threshold) {
  masks <- nis_disclosure_masks(n, hospitals, threshold)
  result <- rep("", length(n))
  result[masks$count] <- paste0("\u2264", threshold)
  result[masks$hospital] <- "<2 hospitals"
  result
}

nis_study_support <- function(data, threshold) {
  n <- nrow(data)
  hospitals <- dplyr::n_distinct(data$YEAR, data$HOSP_NIS, na.rm = TRUE)
  list(n = n, hospitals = hospitals, mask = nis_study_mask(n, hospitals, threshold))
}

nis_study_split <- function(values) {
  if (is.null(values)) {
    return(list())
  }
  split(seq_len(vctrs::vec_size(values)), vctrs::vec_group_id(values))
}

nis_study_supported <- function(data, threshold, cells = list(seq_len(nrow(data)))) {
  length(cells) > 0L &&
    all(vapply(
      cells,
      function(i) {
        !nzchar(nis_study_support(data[i, , drop = FALSE], threshold)$mask)
      },
      logical(1)
    ))
}

nis_study_variable_supported <- function(rows, values, threshold) {
  if (is.logical(values) && !all(c(TRUE, FALSE) %in% values)) {
    return(FALSE)
  }
  # Continuous estimates expose the measured subset and its missing complement.
  if (is.numeric(values) && !is.factor(values)) {
    values <- ifelse(is.finite(values), "observed", as.character(values))
  }
  nis_study_supported(rows, threshold, nis_study_split(values))
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_report_support <- function(data, variables, exposure, threshold) {
  keys <- data[c("YEAR", "HOSP_NIS")]
  yearly <- split(seq_len(nrow(data)), data$YEAR)
  by_year <- dplyr::tibble(
    YEAR = as.integer(names(yearly)),
    count_mask = vapply(yearly, function(i) nis_study_support(keys[i, ], threshold)$mask, character(1))
  )
  arms <- if (length(exposure)) nis_study_split(data[[exposure]]) else list()
  groups <- c(list(seq_len(nrow(data))), yearly)
  variables <- intersect(variables, names(data))
  supported <- stats::setNames(
    vapply(
      variables,
      function(variable) {
        value <- data[[variable]]
        scopes <- if (identical(variable, exposure)) groups else c(groups, arms)
        all(vapply(
          scopes,
          function(i) {
            nis_study_variable_supported(keys[i, , drop = FALSE], value[i], threshold)
          },
          logical(1)
        ))
      },
      logical(1)
    ),
    variables
  )
  pooled <- nis_study_support(keys, threshold)$mask
  if (!nzchar(pooled) && any(nzchar(by_year$count_mask))) {
    pooled <- "Masked"
  }
  # When pooled results are withheld, safe annual estimates stand on their own.
  for (variable in c("DIED", "LOS")) {
    by_year[[variable]] <- if (nzchar(pooled)) {
      vapply(
        yearly,
        function(i) {
          nis_study_variable_supported(keys[i, , drop = FALSE], data[[variable]][i], threshold)
        },
        logical(1)
      )
    } else {
      rep(isTRUE(supported[[variable]]), nrow(by_year))
    }
  }
  list(variables = supported, by_year = by_year, pooled = pooled)
}

nis_study_model_groupings <- function(frame, exposure) {
  terms <- attr(frame, "terms")
  predictors <- setdiff(names(frame), names(frame)[attr(terms, "response")])
  categorical <- predictors[vapply(
    frame[predictors],
    function(value) {
      is.factor(value) || is.character(value) || is.logical(value)
    },
    logical(1)
  )]
  categorical <- union(categorical, exposure)
  factors <- attr(terms, "factors")
  combinations <- lapply(seq_len(ncol(factors)), function(i) {
    intersect(rownames(factors)[factors[, i] > 0L], categorical)
  })
  unique(c(as.list(categorical), Filter(function(fields) length(fields) > 1L, combinations)))
}

nis_study_complete_cases <- function(formula, data, exposure) {
  if (!all(c("YEAR", "HOSP_NIS", exposure) %in% names(data))) {
    return(NULL)
  }
  frame <- tryCatch(
    stats::model.frame(formula, data = data, na.action = stats::na.omit, drop.unused.levels = TRUE),
    error = function(error) NULL
  )
  if (is.null(frame)) {
    return(NULL)
  }
  rows <- match(rownames(frame), rownames(data))
  response <- stats::model.response(frame)
  valid <- c(
    exposure %in% names(frame),
    !anyNA(rows),
    anyDuplicated(rows) == 0L,
    is.null(dim(response)),
    !is.null(response)
  )
  if (!all(valid)) {
    return(NULL)
  }
  list(frame = frame, data = data[rows, , drop = FALSE], response = response, rows = rows)
}

nis_study_model_disclosure <- function(formula, data, family, exposure, threshold) {
  cases <- nis_study_complete_cases(formula, data, exposure)
  # Different complete-case samples would introduce competing denominators.
  if (is.null(cases) || length(cases$rows) != nrow(data)) {
    return(FALSE)
  }
  frame <- cases$frame
  response <- cases$response
  if (family$family %in% c("binomial", "quasibinomial")) {
    if (length(unique(response)) != 2L) {
      return(FALSE)
    }
    response <- factor(response)
  }
  groups <- c(
    list(seq_len(nrow(frame))),
    unlist(
      lapply(
        nis_study_model_groupings(frame, exposure),
        function(fields) nis_study_split(as.data.frame(frame[fields]))
      ),
      recursive = FALSE
    )
  )
  all(vapply(
    groups,
    function(i) {
      nis_study_variable_supported(cases$data[i, , drop = FALSE], response[i], threshold)
    },
    logical(1)
  ))
}

nis_study_withheld_model <- function() {
  list(model = NULL, status = "Withheld under the study disclosure policy.", warnings = character())
}

nis_study_fit_report_model <- function(
  formula,
  design,
  family,
  outcome,
  exposure,
  disclosure_limit,
  report_supported = TRUE,
  ...
) {
  status <- nis_study_model_input_status(design$variables, outcome, exposure)
  if (!is.null(status)) {
    return(list(model = NULL, status = status, warnings = character()))
  }
  if (
    !report_supported ||
      !nis_study_model_disclosure(formula, design$variables, family, exposure, disclosure_limit)
  ) {
    return(nis_study_withheld_model())
  }
  nis_study_fit_model(formula, design, family, outcome = outcome, exposure = exposure, ...)
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_render_table <- function(table, html) {
  if (inherits(table, "gtsummary")) {
    return(if (html) gtsummary::as_gt(table) else gtsummary::as_flex_table(table))
  }
  if (html) gt::gt(table) else flextable::flextable(table)
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_summary_table <- function(table, supported, threshold, header) {
  table <- nis_suppress(table, threshold = threshold)
  # Hide the remaining statistics for a variable with a protected cell.
  # Otherwise, a displayed percentage and a group header can recover the count.
  table <- gtsummary::modify_table_body(table, function(body) {
    stat <- grep("^stat_[0-9]+$", names(body), value = TRUE)
    masks <- c(paste0("\u2264", threshold), "<2 hospitals", "Masked")
    masked <- Reduce(`|`, lapply(body[stat], function(values) values %in% masks))
    related <- body$variable %in% c(body$variable[masked], names(supported)[!supported])
    for (column in stat) {
      value <- body[[column]]
      value[related & !is.na(value) & nzchar(value) & !value %in% masks] <- "Masked"
      body[[column]] <- value
    }
    if ("p.value" %in% names(body)) {
      body$p.value[related] <- NA_real_
    }
    body
  })
  header(table)
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_trend_table <- function(trend) {
  display <- function(mask, value) ifelse(nzchar(mask), mask, value)
  dplyr::transmute(
    trend,
    `Discharge year` = as.character(!!rlang::sym("YEAR")),
    discharges = display(.data$count_mask, format(.data$n_unweighted, big.mark = ",", trim = TRUE)),
    weighted_N = display(.data$count_mask, formatC(.data$weighted_n, format = "f", digits = 1, big.mark = ",")),
    mortality = display(
      ifelse(!nzchar(.data$count_mask) & !.data$mortality_ok, "Masked", .data$count_mask),
      paste0(formatC(.data$mortality * 100, format = "f", digits = 1), "%")
    ),
    mean_LOS = display(
      ifelse(!nzchar(.data$count_mask) & !.data$los_ok, "Masked", .data$count_mask),
      formatC(.data$mean_los, format = "f", digits = 2)
    )
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_model_table <- function(fits, outcomes) {
  models <- lapply(seq_len(nrow(outcomes)), function(i) {
    gtsummary::tbl_regression(fits[[i]]$model, exponentiate = outcomes$exponentiate[[i]])
  })
  gtsummary::tbl_merge(
    tbls = models,
    tab_spanner = paste0("**", outcomes$outcome, "**")
  )
}

nis_study_flow_summary <- function(data, groups) {
  support <- function(keep) {
    rlang::expr(list(
      n = dplyr::coalesce(sum(dplyr::if_else(!!keep, 1L, 0L)), 0L),
      hospitals = dplyr::n_distinct(dplyr::if_else(!!keep, .hospital, NA), na.rm = TRUE),
      weighted = dplyr::coalesce(sum(dplyr::if_else(!!keep, .data$.flow_weight, 0), na.rm = TRUE), 0)
    ))
  }
  expressions <- lapply(groups, function(keep) as.list(support(keep))[-1L])
  keys <- paste0("flow_", seq_len(3L * length(groups)))
  totals <- dplyr::summarise(data, !!!stats::setNames(unlist(expressions, recursive = FALSE), keys)) |>
    nis_collect()
  matrix(unlist(totals, use.names = FALSE), ncol = 3L, byrow = TRUE)
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_flow <- function(data, principal, cohort, design, pooled_mask, threshold, exposure_restricted = FALSE) {
  if (exposure_restricted) {
    # A pre-restriction total would expose another reporting denominator.
    records <- design$variables
    return(nis_study_flow_display(
      "Analysis cohort (observed exposure)",
      nrow(records),
      sum(as.numeric(records$DISCWT)),
      pooled_mask
    ))
  }
  cohort <- rlang::enquo(cohort)
  principal <- rlang::enquo(principal)
  data <- nis_sample_fields(dplyr::ungroup(data), cohort) |>
    dplyr::mutate(
      .cohort = dplyr::coalesce(.data$.nis_cohort, FALSE),
      .principal = dplyr::coalesce(!!principal, FALSE),
      .flow_weight = dplyr::if_else(.nis_valid, as.double(DISCWT), 0),
      .hospital = dbplyr::sql(paste0(
        'CASE WHEN "YEAR" > 0 AND isfinite(CAST("YEAR" AS DOUBLE)) ',
        'AND "HOSP_NIS" > 0 AND isfinite(CAST("HOSP_NIS" AS DOUBLE)) ',
        'THEN struct_pack(year_id := "YEAR", hospital_id := "HOSP_NIS") END'
      ))
    )
  groups <- rlang::exprs(
    TRUE,
    .principal,
    .cohort,
    .cohort & .nis_valid,
    !.principal & !.cohort & .nis_valid,
    .principal & !.cohort & .nis_valid,
    !.principal & !.cohort & !.nis_valid,
    .principal & !.cohort & !.nis_valid,
    !.principal & .cohort & .nis_valid,
    .principal & .cohort & .nis_valid,
    !.principal & .cohort & !.nis_valid,
    .principal & .cohort & !.nis_valid
  )
  totals <- nis_study_flow_summary(data, groups)
  same_cohort <- totals[4L, 1L] == nrow(design$variables) &&
    identical(attr(design, "nis_design_input", exact = TRUE)$cohort, nis_design_cohort_text(cohort))
  mask <- nis_study_mask(totals[, 1L], totals[, 2L], threshold)
  primary <- seq_len(4L)
  if (nzchar(pooled_mask)) {
    mask[4L] <- pooled_mask
  }
  complementary <- !same_cohort || any(nzchar(mask[primary])) || any(nzchar(mask[-primary]) & totals[-primary, 1L] > 0)
  if (complementary) {
    mask[mask == ""] <- "Masked"
  }
  nis_study_flow_display(
    c(
      "All discharges",
      "Principal diagnosis prefix",
      "Cohort definition",
      "Analysis cohort (valid survey design)"
    ),
    totals[primary, 1L],
    totals[primary, 3L],
    mask[primary]
  )
}

nis_study_flow_display <- function(step, discharges, weights, mask) {
  dplyr::tibble(
    step = step,
    discharges = ifelse(nzchar(mask), mask, format(discharges, big.mark = ",", trim = TRUE)),
    weighted_discharges = ifelse(nzchar(mask), mask, formatC(weights, format = "f", digits = 1, big.mark = ","))
  )
}
