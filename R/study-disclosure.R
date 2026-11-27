nis_study_mask <- function(n, hospitals, threshold) {
  masks <- nis_disclosure_masks(n, hospitals, threshold)
  result <- rep("", length(n))
  result[n > 0L & masks$count] <- paste0("\u2264", threshold)
  result[n > 0L & masks$hospital] <- "<2 hospitals"
  result
}

nis_study_support <- function(data, threshold) {
  n <- nrow(data)
  hospitals <- dplyr::n_distinct(data$YEAR, data$HOSP_NIS, na.rm = TRUE)
  list(n = n, hospitals = hospitals, mask = nis_study_mask(n, hospitals, threshold))
}

nis_study_supported <- function(data, threshold) {
  support <- nis_study_support(data, threshold)
  support$n > 0L && !nzchar(support$mask)
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_trend_support <- function(data, threshold) {
  dplyr::group_by(data, !!rlang::sym("YEAR")) |>
    dplyr::group_modify(function(rows, year) {
      rows$YEAR <- year$YEAR[[1L]]
      supported <- function(selected) nis_study_supported(rows[which(selected), ], threshold)
      dplyr::tibble(
        count_mask = nis_study_support(rows, threshold)$mask,
        mortality_ok = supported(rows$DIED) && supported(!rows$DIED),
        los_ok = supported(is.finite(rows$LOS))
      )
    }) |>
    dplyr::ungroup()
}

nis_study_model_group_ok <- function(data, response, binary, threshold) {
  if (!nis_study_supported(data, threshold)) {
    return(FALSE)
  }
  if (!binary) {
    return(TRUE)
  }
  values <- unique(response)
  length(values) == 2L &&
    all(vapply(
      values,
      function(value) {
        nis_study_supported(data[which(response == value), ], threshold)
      },
      logical(1)
    ))
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
  list(frame = frame, data = data[rows, , drop = FALSE], response = response)
}

nis_study_model_disclosure <- function(formula, data, family, exposure, threshold) {
  cases <- nis_study_complete_cases(formula, data, exposure)
  if (is.null(cases)) {
    return(FALSE)
  }
  frame <- cases$frame
  data <- cases$data
  response <- cases$response
  binary <- family$family %in% c("binomial", "quasibinomial")
  supported <- function(i) {
    nis_study_model_group_ok(data[i, , drop = FALSE], response[i], binary, threshold)
  }
  if (!supported(seq_len(nrow(data)))) {
    return(FALSE)
  }
  groupings <- nis_study_model_groupings(frame, exposure)
  all(vapply(
    groupings,
    function(fields) {
      groups <- split(seq_len(nrow(frame)), unname(as.list(frame[fields])), drop = TRUE)
      length(groups) > 0L && all(vapply(groups, supported, logical(1)))
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
