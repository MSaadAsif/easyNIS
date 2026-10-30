#' Predictive margins for a survey regression
#'
#' @param fit A `survey::svyglm()` fit.
#' @param exposure Exposure variable name, as a string or unquoted column.
#' @param design Optional survey design to use for averaging. Defaults to the
#'   design stored in `fit`.
#' @param level Confidence level.
#' @details For each exposure level, this function predicts every design row
#'   after setting the exposure to that level, then averages predictions using
#'   normalized survey weights. The standard error is the square root of
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
  if (!inherits(fit, "svyglm")) cli::cli_abort("`fit` must be a survey::svyglm() fit.")
  if (length(level) != 1L || is.na(level) || level <= 0 || level >= 1) cli::cli_abort("`level` must be between 0 and 1.")
  exp_name <- rlang::as_name(rlang::ensym(exposure))
  design <- if (is.null(design)) fit$survey.design else design
  if (!inherits(design, "survey.design") && !inherits(design, "survey.design2")) cli::cli_abort("`design` must be a survey design.")
  data <- design$variables
  if (!exp_name %in% names(data)) cli::cli_abort("`exposure` must be present in the design.")
  values <- unique(data[[exp_name]][!is.na(data[[exp_name]])])
  if (length(values) < 2L) cli::cli_abort("`exposure` must have at least two observed levels.")
  b <- stats::coef(fit); v <- stats::vcov(fit)
  w <- as.numeric(stats::weights(design, type = "sampling")); w[!is.finite(w)] <- 0
  predict_one <- function(value) {
    nd <- data; nd[[exp_name]] <- value
    mm <- stats::model.matrix(stats::delete.response(stats::terms(fit)), nd,
      contrasts.arg = fit$contrasts, xlev = fit$xlevels)
    mm <- mm[, names(b), drop = FALSE]
    eta <- drop(mm %*% b)
    fam <- fit$family
    mu <- fam$linkinv(eta)
    grad <- mm * (fam$mu.eta(eta))
    g <- colSums(grad * w) / sum(w)
    c(margin = sum(w * mu) / sum(w), se = sqrt(drop(t(g) %*% v %*% g)))
  }
  est <- t(vapply(values, predict_one, numeric(2)))
  df <- survey::degf(design); crit <- stats::qt((1 + level) / 2, df)
  margin <- tibble::tibble(level = values, margin = est[, 1], se = est[, 2],
    conf.low = est[, 1] - crit * est[, 2], conf.high = est[, 1] + crit * est[, 2], contrast = "margin")
  base <- est[1, 1]; base_se <- est[1, 2]
  dif <- est[, 1] - base
  dse <- sqrt(est[, 2]^2 + base_se^2)
  ratio <- rep(NA_real_, length(base))
  rse <- rep(NA_real_, length(base))
  positive <- est[, 1] > 0 & base > 0
  ratio[positive] <- est[positive, 1] / base
  rse[positive] <- sqrt((est[positive, 2] / est[positive, 1])^2 + (base_se / base)^2)
  contrasts <- dplyr::bind_rows(
    tibble::tibble(level = values, margin = dif, se = dse, conf.low = dif - crit*dse, conf.high = dif + crit*dse, contrast = "difference"),
    tibble::tibble(level = values, margin = ratio, se = ratio*rse, conf.low = exp(log(ratio)-crit*rse), conf.high = exp(log(ratio)+crit*rse), contrast = "ratio"))
  out <- dplyr::bind_rows(margin, contrasts)
  attr(out, "model_n") <- stats::nobs(fit)
  attr(out, "events") <- if (is.matrix(fit$y)) sum(fit$y[, 1]) else sum(fit$y, na.rm = TRUE)
  out
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
#' @return A tibble with weighted totals, rate, uncertainty, unweighted count,
#'   and a formatted `label`.
#' @export
#' @examples
#' d <- survey::svydesign(ids = ~1, weights = ~w,
#'   data = data.frame(event = c(0, 1, 1), w = c(1, 2, 3)))
#' nis_rate(d, event)
nis_rate <- function(design, event, by = NULL) {
  if (!inherits(design, c("survey.design", "survey.design2", "tbl_svy"))) cli::cli_abort("`design` must be a survey design.")
  ev <- rlang::as_name(rlang::ensym(event)); grp <- if (missing(by) || rlang::quo_is_null(rlang::enquo(by))) NULL else rlang::as_name(rlang::ensym(by))
  data <- design$variables
  if (!ev %in% names(data) || (!is.null(grp) && !grp %in% names(data))) cli::cli_abort("Requested columns must be present in the design.")
  design$variables$.nis_event <- as.numeric(data[[ev]])
  design$variables$.nis_one <- 1
  valid <- !is.na(design$variables$.nis_event)
  design <- design[valid, ]
  data <- design$variables
  groups <- if (is.null(grp)) NULL else stats::as.formula(paste("~", grp))
  total <- function(formula) if (is.null(groups)) survey::svytotal(formula, design) else survey::svyby(formula, groups, design, survey::svytotal, keep.names = FALSE)
  mean <- function(formula) if (is.null(groups)) survey::svymean(formula, design) else survey::svyby(formula, groups, design, survey::svymean, vartype = c("se", "ci"), keep.names = FALSE)
  events <- total(~I(.nis_event != 0)); denom <- total(~.nis_one); prop <- mean(~I(.nis_event != 0))
  evw <- as.numeric(stats::coef(events)); nw <- as.numeric(stats::coef(denom)); p <- as.numeric(stats::coef(prop))
  se <- as.numeric(survey::SE(prop))
  ci <- if (is.null(groups)) as.matrix(stats::confint(survey::svyciprop(~I(.nis_event != 0), design, method = "beta"))) else as.matrix(prop)[, grep("ci", names(as.data.frame(prop)), value = TRUE), drop = FALSE]
  n <- if (is.null(groups)) nrow(data) else as.integer(table(factor(data[[grp]], levels = unique(as.character(data[[grp]])))))
  out <- if (is.null(groups)) tibble::tibble(weighted_events = evw, weighted_n = nw, proportion = p, se = se, conf.low = ci[1], conf.high = ci[2], n = n) else tibble::tibble(!!grp := as.character(as.data.frame(prop)[[1]]), weighted_events = evw, weighted_n = nw, proportion = p, se = se, conf.low = as.numeric(ci[, 1]), conf.high = as.numeric(ci[, 2]), n = n)
  dplyr::mutate(out, label = sprintf("%s/%s (%.2f%%)", format(round(weighted_events), big.mark = ","), format(round(weighted_n), big.mark = ","), 100 * proportion))
}
