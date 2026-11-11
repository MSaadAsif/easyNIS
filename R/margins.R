#' Predictive margins for a survey regression
#'
#' @param fit A `survey::svyglm()` fit.
#' @param exposure Exposure variable name, as a string or unquoted column.
#' @param design Optional survey design to use for averaging. Defaults to the
#'   design stored in `fit`.
#' @param level Confidence level.
#' @details For each exposure level, this function predicts every design row
#'   after setting the exposure to that level, then averages predictions using
#'   normalized survey weights among rows with complete model predictors and
#'   finite positive sampling weights; this same standardization sample is used
#'   for every exposure level. Rows missing a predictor or offset are excluded.
#'   Model offsets are retained. The standard error is the square root of
#'   `g' V g`, where `V` is `vcov(fit)` and `g` is the weighted mean of the
#'   prediction gradient with respect to the fitted coefficients. Confidence
#'   intervals use a t critical value with `survey::degf(design)` degrees of
#'   freedom. Contrasts are relative to the first exposure level: differences
#'   use the delta method; ratios use a log-scale delta interval. This method
#'   treats the empirical exposure distribution and weights as fixed. A ratio
#'   interval is undefined if either margin is zero or negative; its estimate,
#'   standard error, and limits are returned as `NA` in that case.
#' @return A tibble with margins and reference contrasts.
#' @export
#' @examples
#' d <- survey::svydesign(ids = ~1, weights = ~w,
#'   data = data.frame(y = c(0, 1, 1, 0), x = c(0, 0, 1, 1), w = 1))
#' fit <- survey::svyglm(y ~ x, d, family = quasibinomial())
#' nis_margins(fit, x)
nis_margins <- function(fit, exposure, design = NULL, level = 0.95) {
  exp_name <- rlang::as_name(rlang::ensym(exposure))
  inputs <- .nis_margin_inputs(fit, exp_name, design, level)
  design <- inputs$design
  exp_name <- inputs$exp_name
  data <- inputs$data
  values <- inputs$values
  b <- stats::coef(fit)
  v <- stats::vcov(fit)
  w <- as.numeric(stats::weights(design, type = "sampling"))
  predict_one <- function(value) {
    nd <- data
    nd[[exp_name]] <- value
    terms <- stats::delete.response(stats::terms(fit))
    mf <- stats::model.frame(terms, data = nd, na.action = stats::na.pass,
      xlev = fit$xlevels)
    mm <- stats::model.matrix(terms, mf,
      contrasts.arg = fit$contrasts, xlev = fit$xlevels)
    mm <- mm[, names(b), drop = FALSE]
    offset <- stats::model.offset(mf)
    if (is.null(offset)) offset <- rep(0, nrow(mm))
    call_offset <- fit$call$offset
    if (!is.null(call_offset)) {
      formula_env <- environment(stats::formula(fit))
      extra_offset <- eval(call_offset, envir = nd, enclos = formula_env)
      offset <- offset + rep_len(extra_offset, nrow(mm))
    }
    keep <- stats::complete.cases(mm) & is.finite(offset) &
      is.finite(w) & w > 0
    if (!any(keep)) {
      cli::cli_abort("No rows have complete model predictors and positive finite weights.")
    }
    mm <- mm[keep, , drop = FALSE]
    offset <- offset[keep]
    weights <- w[keep]
    eta <- drop(mm %*% b) + offset
    fam <- fit$family
    mu <- fam$linkinv(eta)
    grad <- mm * (fam$mu.eta(eta))
    g <- colSums(grad * weights) / sum(weights)
    c(margin = sum(weights * mu) / sum(weights), g)
  }
  est <- t(vapply(values, predict_one, numeric(length(b) + 1L)))
  gradients <- est[, -1, drop = FALSE]
  est <- est[, 1]
  margin_se <- sqrt(rowSums((gradients %*% v) * gradients))
  df <- survey::degf(design)
  crit <- stats::qt((1 + level) / 2, df)
  margin <- dplyr::tibble(level = values, margin = est, se = margin_se,
    conf.low = est - crit * margin_se, conf.high = est + crit * margin_se, contrast = "margin")
  base <- est[1]
  base_g <- gradients[1, ]
  dif <- est - base
  dgrad <- gradients - matrix(base_g, nrow(gradients), length(base_g), byrow = TRUE)
  dse <- sqrt(rowSums((dgrad %*% v) * dgrad))
  ratio <- rep(NA_real_, length(base))
  rse <- rep(NA_real_, length(base))
  positive <- est > 0 & base > 0
  ratio[positive] <- est[positive] / base
  rgrad <- gradients[positive, , drop = FALSE] / est[positive]
  rgrad <- rgrad - matrix(base_g / base, nrow(rgrad), length(base_g), byrow = TRUE)
  rse[positive] <- sqrt(rowSums((rgrad %*% v) * rgrad))
  contrasts <- dplyr::bind_rows(
    dplyr::tibble(level = values, margin = dif, se = dse,
      conf.low = dif - crit * dse, conf.high = dif + crit * dse,
      contrast = "difference"),
    dplyr::tibble(level = values, margin = ratio, se = ratio * rse,
      conf.low = exp(log(ratio) - crit * rse),
      conf.high = exp(log(ratio) + crit * rse), contrast = "ratio"))
  out <- dplyr::bind_rows(margin, contrasts)
  attr(out, "model_n") <- stats::nobs(fit)
  attr(out, "events") <- if (is.matrix(fit$y)) sum(fit$y[, 1]) else sum(fit$y, na.rm = TRUE)
  out
}

.nis_margin_inputs <- function(fit, exp_name, design, level) {
  .nis_margin_validate_fit(fit, level)
  design <- if (is.null(design)) fit$survey.design else design
  if (!inherits(design, c("survey.design", "survey.design2"))) {
    cli::cli_abort("`design` must be a survey design.")
  }
  data <- design$variables
  if (!exp_name %in% names(data)) {
    cli::cli_abort("`exposure` must be present in the design.")
  }
  values <- unique(data[[exp_name]][!is.na(data[[exp_name]])])
  if (length(values) < 2L) {
    cli::cli_abort("`exposure` must have at least two observed levels.")
  }
  list(design = design, exp_name = exp_name, data = data, values = values)
}

.nis_margin_validate_fit <- function(fit, level) {
  if (!inherits(fit, "svyglm")) {
    cli::cli_abort("`fit` must be a survey::svyglm() fit.")
  }
  if (length(level) != 1L || is.na(level) || level <= 0 || level >= 1) {
    cli::cli_abort("`level` must be between 0 and 1.")
  }
}

#' Estimate weighted event rates
#'
#' @param design Survey design from [nis_design()].
#' @param event Event indicator column, unquoted or a string.
#' @param by Optional grouping column, unquoted or a string.
#' @details The proportion is the weighted event total divided by the weighted
#'   non-missing denominator. Its standard error and confidence interval are
#'   estimated with `survey::svyciprop(method = "beta")` on each group domain.
#'   Use [nis_suppress()] on the returned table before reporting where required.
#'   The grouping column keeps its input name unless that name conflicts with a
#'   result column; in that case it is returned as `.group` (or `.group1`, etc.).
#' @return A tibble with weighted totals, rate, uncertainty, unweighted count,
#'   and a formatted `label`.
#' @export
#' @examples
#' d <- survey::svydesign(ids = ~1, weights = ~w,
#'   data = data.frame(event = c(0, 1, 1), w = c(1, 2, 3)))
#' nis_rate(d, event)
nis_rate <- function(design, event, by = NULL) {
  if (!inherits(design, c("survey.design", "survey.design2", "tbl_svy"))) {
    cli::cli_abort("`design` must be a survey design.")
  }
  ev <- rlang::as_name(rlang::ensym(event))
  grp <- if (missing(by) || rlang::quo_is_null(rlang::enquo(by))) {
    NULL
  } else {
    rlang::as_name(rlang::ensym(by))
  }
  data <- design$variables
  if (!ev %in% names(data) || (!is.null(grp) && !grp %in% names(data))) {
    cli::cli_abort("Requested columns must be present in the design.")
  }
  raw_event <- data[[ev]]
  valid_values <- .nis_rate_event_valid(raw_event)
  if (!valid_values) cli::cli_abort("`event` must be logical or numeric 0/1.")
  design$variables$.nis_event <- as.numeric(raw_event)
  design$variables$.nis_one <- 1
  keep <- !is.na(design$variables$.nis_event)
  design <- design[keep, ]
  data <- design$variables
  if (is.null(grp)) {
    stats <- .nis_rate_overall(design, data)
  } else {
    stats <- .nis_rate_grouped(design, data, grp)
  }
  out <- dplyr::tibble(weighted_events = stats$weighted_events,
    weighted_n = stats$weighted_n, proportion = stats$proportion,
    se = stats$se, conf.low = stats$conf.low, conf.high = stats$conf.high,
    n = stats$n)
  if (!is.null(grp)) {
    out[[.nis_rate_group_output_name(grp)]] <- stats$group
  }
  out$label <- sprintf("%s/%s (%.2f%%)",
    format(round(out$weighted_events), big.mark = ","),
    format(round(out$weighted_n), big.mark = ","), 100 * out$proportion)
  out
}

.nis_rate_overall <- function(design, data) {
  events <- survey::svytotal(~.nis_event, design)
  denom <- survey::svytotal(~.nis_one, design)
  prop <- survey::svyciprop(~.nis_event, design, method = "beta")
  conf <- stats::confint(prop)
  list(
    weighted_events = as.numeric(stats::coef(events)),
    weighted_n = as.numeric(stats::coef(denom)),
    proportion = as.numeric(stats::coef(prop)),
    se = as.numeric(survey::SE(prop)),
    conf.low = as.numeric(conf[, 1]),
    conf.high = as.numeric(conf[, 2]),
    n = nrow(data)
  )
}

.nis_rate_grouped <- function(design, data, grp) {
  groups <- rlang::new_formula(NULL, rlang::sym(grp))
  events <- survey::svyby(~.nis_event, groups, design, survey::svytotal)
  denom <- survey::svyby(~.nis_one, groups, design, survey::svytotal)
  mean_prop <- survey::svyby(~.nis_event, groups, design, survey::svymean,
    vartype = "se")
  prop <- survey::svyby(~.nis_event, groups, design, survey::svyciprop,
    vartype = "ci", method = "beta")
  prop_frame <- as.data.frame(prop)
  labels <- as.character(prop_frame[[1]])
  conf <- as.matrix(prop_frame[, c("ci_l", "ci_u"), drop = FALSE])
  unweighted_n <- unname(vapply(labels, function(label) {
    sum(!is.na(data[[grp]]) & as.character(data[[grp]]) == label)
  }, integer(1)))
  list(
    weighted_events = as.numeric(stats::coef(events)),
    weighted_n = as.numeric(stats::coef(denom)),
    proportion = as.numeric(stats::coef(prop)),
    se = as.numeric(survey::SE(mean_prop)),
    conf.low = as.numeric(conf[, 1]),
    conf.high = as.numeric(conf[, 2]),
    n = unweighted_n,
    group = labels
  )
}

.nis_rate_group_output_name <- function(grp) {
  reserved <- c("weighted_events", "weighted_n", "proportion", "se",
    "conf.low", "conf.high", "n", "label")
  if (!grp %in% reserved) return(grp)
  group_name <- ".group"
  suffix <- 1L
  while (group_name %in% c(reserved, grp)) {
    group_name <- paste0(".group", suffix)
    suffix <- suffix + 1L
  }
  group_name
}

.nis_rate_event_valid <- function(event) {
  is.logical(event) || (is.numeric(event) &&
    all(is.na(event) | event %in% c(0, 1)))
}
