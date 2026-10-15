# Equal-weight invented rows. Row i belongs to hospital (i - 1) %% h + 1, so any
# run of h or more consecutive rows spans all h hospitals. The first half of
# the hospitals form stratum 1 and the rest stratum 2. By default h = 4.
regression_rows <- function(n, year = 2022L, first_key = 0L, hospitals = 4L) {
  rows <- nis_synthetic_data(year)$core[rep(1L, n), ]
  rows$KEY_NIS <- sprintf("%06d", first_key + seq_len(n))
  hospital <- (seq_len(n) - 1L) %% hospitals + 1L
  rows$HOSP_NIS <- sprintf("%04d", hospital)
  rows$NIS_STRATUM <- as.integer(hospital > hospitals / 2) + 1L
  rows$DISCWT <- 5
  rownames(rows) <- NULL
  rows
}

regression_noise <- function(n) ((seq_len(n) * 7L) %% 11L) / 10

regression_design <- function(session, rows, columns) {
  path <- write_invented_parquet(session, rows)
  on.exit(unlink(path))
  nis_survey_design(nis_import(session, path, unique(rows$YEAR)), columns, TRUE,
    "hospital_wr", "fail")
}

# `group` and `sex` label raw codes 1, 2, ... in fields `g` and `s`.
regression_fit <- function(session, rows, columns, formula, family = "gaussian", group = NULL,
                           sex = NULL, missing = "fail") {
  design <- regression_design(session, rows, columns)
  if (!is.null(group)) {
    design <- nis_factor(design, "g", "group", seq_along(group), group)
  }
  if (!is.null(sex)) {
    design <- nis_factor(design, "s", "sex", seq_along(sex), sex)
  }
  nis_model(design, formula, family, missing, 8, 0.95, "wr_unadjusted")
}

regression_spec <- function(fit, terms = fit$coefficients$term, id = terms) {
  data.frame(id = id, term = terms, label = paste("Invented", id), unit = "link")
}

regression_review <- function(fit, suppress = c(1, 10), zero = "display", min_hospitals = 2,
                              spec = regression_spec(fit)) {
  nis_disclosure_review(nis_regression_table(fit, spec, "link"), suppress, zero,
    min_hospitals, list())
}

regression_reasons <- function(review) {
  stats::setNames(review$audit$rows$reasons, review$audit$rows$id)
}

regression_status <- function(review) {
  stats::setNames(review$presentation$disclosure_status, review$presentation$id)
}

# Audited counts (or hospitals) for one model, column, factor or crossing, keyed
# by check and level. Response-nonzero splits of a multi-valued response are
# included only on request.
regression_counts <- function(review, scope, target = NA_character_, value = "count",
                              nonzero = FALSE) {
  groups <- review$audit$groups
  groups <- groups[groups$scope == scope & groups$target %in% target &
    (nonzero | !groups$outcome %in% "nonzero"), ]
  stats::setNames(groups[[value]],
    ifelse(is.na(groups$level), groups$check, paste0(groups$check, ":", groups$level)))
}

test_that("equal-weight logistic cells are checked just inside and outside the range", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Cells x0/y0, x0/y1, x1/y0, x1/y1. With equal weights the intercept, slope
  # and their SEs determine all four cells, so each is a checked group.
  logistic <- function(cells) {
    rows <- regression_rows(sum(cells))
    rows$x <- rep(c(0, 0, 1, 1), cells)
    rows$event <- rep(c(0, 1, 0, 1), cells)
    regression_fit(session, rows, c("x", "event"), event ~ x, "quasibinomial")
  }
  outside <- regression_review(logistic(c(11, 11, 11, 11)))
  expect_identical(unname(regression_status(outside)), c("shown", "shown"))
  expect_identical(regression_counts(outside, "model"),
    c(included = 44, events = 22, nonevents = 22))
  expect_identical(regression_counts(outside, "column", "x"),
    c(lower_level = 22, lower_level_events = 11, lower_level_nonevents = 11,
      upper_level = 22, upper_level_events = 11, upper_level_nonevents = 11))
  expect_true(all(regression_counts(outside, "column", "x", "hospitals") == 4))
  expect_identical(outside$audit$sample$binary_response, TRUE)
  expect_identical(outside$presentation$unweighted_n, c(44, 44))
  checks <- c("lower_level_nonevents", "lower_level_events", "upper_level_nonevents",
    "upper_level_events")
  for (k in 1:4) {
    cells <- c(11, 11, 11, 11)
    cells[[k]] <- 10
    fit <- logistic(cells)
    review <- regression_review(fit)
    expected <- c(lower_level = 22, lower_level_events = 11, lower_level_nonevents = 11,
      upper_level = 22, upper_level_events = 11, upper_level_nonevents = 11)
    expected[[checks[[k]]]] <- 10
    expected[[if (k <= 2) "lower_level" else "upper_level"]] <- 21
    expect_identical(regression_counts(review, "column", "x"), expected, info = k)
    expect_identical(unname(regression_reasons(review)),
      c("reference:x", paste0("column:", checks[[k]])), info = k)
    expect_identical(unname(regression_status(review)), c("suppressed", "suppressed"))
    expect_true(all(is.na(review$presentation[, c("estimate", "se", "statistic", "p_value",
      "lower", "upper", "aliased")])))
    expect_identical(review$presentation$unweighted_n, c(43, 43))
    expect_true(all(is.finite(fit$coefficients$estimate)))
  }
})

test_that("small reference and non-reference factor levels suppress the factor and intercept", {
  session <- nis_open()
  on.exit(nis_close(session))
  factor_fit <- function(g) {
    rows <- regression_rows(84L)
    rows$g <- g
    rows$x <- rep(c(-1, 0, 2), length.out = 84L)
    rows$y <- 1 + 0.5 * rows$x + rows$g + regression_noise(84L)
    regression_fit(session, rows, c("y", "x", "g"), y ~ group + x, group = c("A", "B", "C"))
  }
  reference <- regression_review(factor_fit(rep(c(1, 2, 3), c(3, 40, 41))))
  expect_identical(regression_counts(reference, "factor", "group"),
    c("level:A" = 3, "level:B" = 40, "level:C" = 41))
  expect_identical(regression_counts(reference, "factor", "group", "hospitals"),
    c("level:A" = 3, "level:B" = 4, "level:C" = 4))
  expect_identical(regression_counts(reference, "column", c("groupB", "groupC")),
    c(lower_level = 44, upper_level = 40, lower_level = 43, upper_level = 41))
  expect_identical(regression_counts(reference, "column", "x"), c(nonzero = 56, zero_valued = 28))
  expect_identical(regression_reasons(reference), c("(Intercept)" = "factor:group",
    groupB = "factor:group", groupC = "factor:group", x = ""))
  expect_identical(unname(regression_status(reference)),
    c("suppressed", "suppressed", "suppressed", "shown"))
  other <- regression_review(factor_fit(rep(c(1, 2, 3), c(41, 40, 3))))
  expect_identical(regression_counts(other, "factor", "group"),
    c("level:A" = 41, "level:B" = 40, "level:C" = 3))
  expect_identical(regression_counts(other, "column", "groupC"), c(lower_level = 81, upper_level = 3))
  expect_identical(regression_reasons(other), c("(Intercept)" = "reference:groupC;factor:group",
    groupB = "factor:group", groupC = "column:upper_level;column:upper_level_response_nonzero;factor:group", x = ""))
  expect_identical(other$presentation$estimate[[4L]], other$table$data$estimate[[4L]])
})

test_that("zero-count fitted levels and zero cells follow the zero policy", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  rows$flag <- rep(FALSE, 40L)
  fit <- regression_fit(session, rows, c("y", "x", "flag"), y ~ x + flag)
  expect_identical(fit$factors$flag$levels, c("FALSE", "TRUE"))
  display <- regression_review(fit)
  expect_identical(regression_counts(display, "factor", "flag"),
    c("level:FALSE" = 40, "level:TRUE" = 0))
  expect_identical(regression_counts(display, "factor", "flag", "hospitals"),
    c("level:FALSE" = 4, "level:TRUE" = 0))
  expect_identical(regression_counts(display, "column", "x"), c(nonzero = 27, zero_valued = 13))
  # The all-zero flagTRUE column checks its zero nonzero count.
  expect_identical(regression_counts(display, "column", "flagTRUE"), c(nonzero = 0))
  expect_identical(unname(regression_status(display)), c("shown", "shown", "shown"))
  expect_identical(display$presentation$aliased, c(FALSE, FALSE, TRUE))
  suppressed <- regression_review(fit, zero = "suppress")
  expect_identical(regression_reasons(suppressed),
    c("(Intercept)" = "reference:flagTRUE;factor:flag", x = "",
      flagTRUE = "column:nonzero;column:nonzero_response_nonzero;factor:flag"))
  expect_identical(suppressed$presentation$aliased, c(NA, FALSE, NA))

  cells <- regression_rows(60L)
  cells$flag <- seq_len(60L) <= 20L
  cells$event <- as.double(seq_len(60L) > 20L & seq_len(60L) %% 2L == 0L)
  # A zero/one Gaussian response is binary, so level-by-outcome cells apply.
  cell_fit <- regression_fit(session, cells, c("event", "flag"), event ~ flag)
  shown <- regression_review(cell_fit)
  expect_identical(regression_counts(shown, "model"), c(included = 60, events = 20, nonevents = 40))
  expect_identical(regression_counts(shown, "model", value = "hospitals"),
    c(included = 4, events = 2, nonevents = 4))
  expect_identical(regression_counts(shown, "column", "flagTRUE"),
    c(lower_level = 40, lower_level_events = 20, lower_level_nonevents = 20,
      upper_level = 20, upper_level_events = 0, upper_level_nonevents = 20))
  expect_identical(regression_counts(shown, "factor", "flag"),
    c("level:FALSE" = 40, "level_events:FALSE" = 20, "level_nonevents:FALSE" = 20,
      "level:TRUE" = 20, "level_events:TRUE" = 0, "level_nonevents:TRUE" = 20))
  expect_identical(regression_counts(shown, "factor", "flag", "hospitals"),
    c("level:FALSE" = 4, "level_events:FALSE" = 2, "level_nonevents:FALSE" = 2,
      "level:TRUE" = 4, "level_events:TRUE" = 0, "level_nonevents:TRUE" = 4))
  expect_identical(unname(regression_status(shown)), c("shown", "shown"))
  hidden <- regression_review(cell_fit, zero = "suppress")
  expect_identical(regression_reasons(hidden), c("(Intercept)" = "reference:flagTRUE;factor:flag",
    flagTRUE = "column:upper_level_events;factor:flag"))
})

test_that("factor interactions protect marginal terms and sparse interaction columns", {
  session <- nis_open()
  on.exit(nis_close(session))
  interaction_fit <- function(g, x) {
    rows <- regression_rows(84L)
    rows$g <- g
    rows$x <- x
    rows$z <- rep(1:5, length.out = 84L) + 0
    rows$y <- 1 + 0.5 * rows$x + rows$g + 0.2 * rows$z + regression_noise(84L)
    regression_fit(session, rows, c("y", "x", "z", "g"), y ~ x * group + z, group = c("A", "B"))
  }
  small <- regression_review(interaction_fit(rep(c(1, 2), c(76, 8)),
    rep(c(-1, 0, 2), length.out = 84L)))
  expect_identical(small$audit$rows$term, c("(Intercept)", "x", "groupB", "z", "x:groupB"))
  expect_identical(regression_counts(small, "factor", "group"), c("level:A" = 76, "level:B" = 8))
  expect_identical(regression_counts(small, "column", c("groupB", "z", "x:groupB")),
    c(lower_level = 76, upper_level = 8, nonzero = 84, nonzero = 5, zero_valued = 79))
  expect_identical(regression_counts(small, "column", "x:groupB", "hospitals"),
    c(nonzero = 4, zero_valued = 4))
  expect_identical(unname(regression_reasons(small)),
    c("reference:groupB;reference:x:groupB;factor:group", "factor:group",
      "column:upper_level;column:upper_level_response_nonzero;factor:group", "",
      "column:nonzero;column:nonzero_response_nonzero;factor:group"))
  sparse_x <- c(rep(c(-1, 0, 2), length.out = 44L), c(1, 2, 3, 1, 2), rep(0, 35L))
  sparse <- regression_review(interaction_fit(rep(c(1, 2), c(44, 40)), sparse_x))
  expect_identical(regression_counts(sparse, "factor", "group"), c("level:A" = 44, "level:B" = 40))
  expect_identical(regression_counts(sparse, "column", c("x", "x:groupB")),
    c(nonzero = 34, zero_valued = 50, nonzero = 5, zero_valued = 79))
  expect_identical(unname(regression_reasons(sparse)),
    c("reference:x:groupB", "", "", "", "column:nonzero;column:nonzero_response_nonzero"))
  expect_identical(unname(regression_status(sparse)),
    c("suppressed", "shown", "shown", "shown", "suppressed"))
})

test_that("two-valued, sparse-zero and exactly distinct columns are checked", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(60L)
  rows$dose <- ifelse(seq_len(60L) <= 6L, 5, 2)
  rows$w <- rep(1:5, length.out = 60L) + 0
  rows$w[c(10, 20, 30, 40)] <- 0
  rows$x <- rep(c(-1, 0, 2), length.out = 60L)
  rows$y <- 1 + 0.3 * rows$dose + 0.2 * rows$w + 0.5 * rows$x + regression_noise(60L)
  fit <- regression_fit(session, rows, c("y", "dose", "w", "x"), y ~ dose + w + x)
  review <- regression_review(fit)
  expect_identical(regression_counts(review, "column", c("dose", "w", "x")),
    c(lower_level = 54, upper_level = 6, nonzero = 56, zero_valued = 4, nonzero = 40,
      zero_valued = 20))
  expect_identical(regression_counts(review, "column", "dose", "value"),
    c(lower_level = 2, upper_level = 5))
  expect_identical(regression_counts(review, "column", "w", "hospitals"),
    c(nonzero = 4, zero_valued = 2))
  expect_identical(regression_reasons(review), c("(Intercept)" = "reference:dose;reference:w",
    dose = "column:upper_level;column:upper_level_response_nonzero",
    w = "column:zero_valued;column:zero_valued_response_nonzero", x = ""))
  expect_identical(unname(regression_status(regression_review(fit, suppress = c(1, 3)))),
    rep("shown", 4L))

  rows$near <- ifelse(seq_len(60L) <= 6L, 1 + 2^-52, 1)
  near_fit <- regression_fit(session, rows, c("y", "x", "near"), y ~ x + near)
  near <- regression_review(near_fit)
  expect_identical(regression_counts(near, "column", "near"), c(lower_level = 54, upper_level = 6))
  expect_identical(regression_counts(near, "column", "near", "value"),
    c(lower_level = 1, upper_level = 1 + 2^-52))
  expect_identical(regression_reasons(near),
    c("(Intercept)" = "reference:near", x = "", near = "column:upper_level;column:upper_level_response_nonzero"))
})

test_that("hospital minimums apply to model, column and factor groups", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  fit <- regression_fit(session, rows, c("y", "x"), y ~ x)
  model <- regression_review(fit, min_hospitals = 5)
  expect_identical(regression_counts(model, "model", value = "hospitals"), c(included = 4))
  expect_identical(regression_reasons(model), c("(Intercept)" = "model:hospitals_included;model:hospitals_response_nonzero;reference:x",
    x = paste0("model:hospitals_included;model:hospitals_response_nonzero;column:hospitals_nonzero;",
      "column:hospitals_nonzero_response_nonzero;column:hospitals_zero_valued;column:hospitals_zero_valued_response_nonzero")))
  expect_identical(model$presentation$unweighted_n, c(NA_real_, NA_real_))
  expect_identical(regression_review(fit, min_hospitals = 4)$presentation$unweighted_n, c(40, 40))

  hospital <- (seq_len(48L) - 1L) %% 4L + 1L
  rows <- regression_rows(48L)
  rows$site <- as.double(hospital == 1L)
  rows$x <- rep(c(-1, 0, 2), length.out = 48L)
  rows$y <- 1 + 0.5 * rows$x + rows$site + regression_noise(48L)
  column <- regression_review(regression_fit(session, rows, c("y", "site", "x"), y ~ site + x))
  expect_identical(regression_counts(column, "column", "site"), c(lower_level = 36, upper_level = 12))
  expect_identical(regression_counts(column, "column", "site", "hospitals"),
    c(lower_level = 3, upper_level = 1))
  expect_identical(regression_reasons(column), c("(Intercept)" = "reference:site",
    site = "column:hospitals_upper_level;column:hospitals_upper_level_response_nonzero", x = ""))

  # Reference level A is hospital 1; B and C alternate over the other rows.
  rows$g <- 1
  rows$g[hospital != 1L] <- rep(c(2, 3), 18L)
  factor_review <- regression_review(regression_fit(session, rows, c("y", "x", "g"), y ~ group + x,
    group = c("A", "B", "C")))
  expect_identical(regression_counts(factor_review, "factor", "group"),
    c("level:A" = 12, "level:B" = 18, "level:C" = 18))
  expect_identical(regression_counts(factor_review, "factor", "group", "hospitals"),
    c("level:A" = 1, "level:B" = 3, "level:C" = 3))
  expect_identical(regression_counts(factor_review, "column", c("groupB", "groupC"), "hospitals"),
    c(lower_level = 4, upper_level = 3, lower_level = 4, upper_level = 3))
  expect_identical(regression_reasons(factor_review), c("(Intercept)" = "factor:group",
    groupB = "factor:group", groupC = "factor:group", x = ""))
})

test_that("a model-level failure suppresses every row and the published n", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(60L)
  rows$x <- rep(c(-1, 0, 2), length.out = 60L)
  rows$event <- as.double(seq_len(60L) %in% c(1, 7, 13, 19, 25, 31, 37, 43, 49))
  fit <- regression_fit(session, rows, c("x", "event"), event ~ x, "quasibinomial")
  review <- regression_review(fit)
  expect_identical(regression_counts(review, "model"), c(included = 60, events = 9, nonevents = 51))
  expect_identical(regression_counts(review, "model", value = "hospitals"),
    c(included = 4, events = 2, nonevents = 4))
  # All nine events have x = -1, so the nonzero-x event cell also fails.
  expect_identical(unname(regression_reasons(review)),
    c("model:events;reference:x", "model:events;column:nonzero_events"))
  expect_identical(unname(regression_status(review)), c("suppressed", "suppressed"))
  expect_identical(review$presentation$unweighted_n, c(NA_real_, NA_real_))
  wider <- regression_review(fit, suppress = c(1, 8))
  expect_identical(unname(regression_status(wider)), c("shown", "shown"))
  expect_identical(wider$presentation$unweighted_n, c(60, 60))
  expect_identical(wider$presentation$estimate, fit$coefficients$estimate)
})

test_that("repeated and reordered terms share one identity", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(84L)
  rows$g <- rep(c(1, 2, 3), c(3, 40, 41))
  rows$x <- rep(c(-1, 0, 2), length.out = 84L)
  rows$y <- 1 + 0.5 * rows$x + rows$g + regression_noise(84L)
  fit <- regression_fit(session, rows, c("y", "x", "g"), y ~ group + x, group = c("A", "B", "C"))
  spec <- regression_spec(fit, c("x", "(Intercept)", "groupB", "x", "groupB"),
    c("slope", "constant", "b", "slope_again", "b_again"))
  review <- regression_review(fit, spec = spec)
  expect_identical(review$presentation$id, spec$id)
  expect_identical(review$presentation$term, spec$term)
  expect_identical(unname(regression_status(review)),
    c("shown", "suppressed", "suppressed", "shown", "suppressed"))
  expect_identical(unname(regression_reasons(review)),
    c("", "factor:group", "factor:group", "", "factor:group"))
  slope <- fit$coefficients$estimate[fit$coefficients$term == "x"]
  expect_identical(review$presentation$estimate, c(slope, NA, NA, slope, NA))
})

test_that("domains and average annual pools count reused hospitals by year", {
  session <- nis_open()
  on.exit(nis_close(session))
  designs <- lapply(c(2021L, 2022L), function(year) {
    rows <- regression_rows(24L, year, (year - 2020L) * 1000L)
    hospital <- (seq_len(24L) - 1L) %% 4L + 1L
    rows$flag <- as.double(hospital == 1L)
    rows$dom <- !(year == 2022L & seq_len(24L) %in% c(2:4, 6:8))
    rows$y <- 1 + 0.5 * rows$flag + regression_noise(24L) + (year == 2022L) * 0.3
    regression_design(session, rows, c("y", "flag", "dom"))
  })
  pool <- nis_pool_design(designs, c("y", "flag", "dom"), "average_annual_total")
  domain <- nis_domain(pool, "dom", "fail")
  fit <- nis_model(domain, y ~ flag, "gaussian", "fail", 8, 0.95, "wr_unadjusted")
  review <- regression_review(fit)
  expect_identical(regression_counts(review, "model"), c(included = 42))
  expect_identical(regression_counts(review, "model", value = "hospitals"), c(included = 8))
  expect_identical(regression_counts(review, "column", "flag"), c(lower_level = 30, upper_level = 12))
  expect_identical(regression_counts(review, "column", "flag", "hospitals"),
    c(lower_level = 6, upper_level = 2))
  # The domain design supplies its 42 member rows to the model.
  expect_identical(review$audit$sample$supplied, 42)
  expect_identical(review$presentation$unweighted_n, c(42, 42))
  expect_identical(unname(regression_status(review)), c("shown", "shown"))
  strict <- regression_review(fit, min_hospitals = 3)
  expect_identical(regression_reasons(strict), c("(Intercept)" = "reference:flag",
    flag = "column:hospitals_upper_level;column:hospitals_upper_level_response_nonzero"))
})

test_that("presentation keeps only declared, inference and policy columns", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(60L)
  rows$x <- rep(c(-1, 0, 2), length.out = 60L)
  rows$x_copy <- rows$x
  rows$s <- as.double(seq_len(60L) <= 6L)
  rows$s_copy <- rows$s
  rows$y <- 1 + 0.5 * rows$x + 0.7 * rows$s + regression_noise(60L)
  fit <- regression_fit(session, rows, c("y", "x", "x_copy", "s", "s_copy"),
    y ~ x + x_copy + s + s_copy)
  expect_identical(fit$coefficients$aliased, c(FALSE, FALSE, TRUE, FALSE, TRUE))
  table <- nis_regression_table(fit, regression_spec(fit), "link")
  before <- table
  fit_before <- fit
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  expect_identical(table, before)
  expect_identical(fit, fit_before)
  expect_identical(review$table, table)
  expect_identical(regression_counts(review, "column", c("x_copy", "s_copy")),
    c(nonzero = 40, zero_valued = 20, lower_level = 54, upper_level = 6))
  # The two-valued s and s_copy are also crossed; their off-diagonal cells are empty.
  expect_identical(regression_counts(review, "cross", "s:s_copy"),
    c("cell:0:0" = 54, "cell:1:0" = 0, "cell:0:1" = 0, "cell:1:1" = 6))
  expect_identical(regression_reasons(review),
    c("(Intercept)" = "reference:s;reference:s_copy;cross:s:s_copy", x = "", x_copy = "",
      s = "column:upper_level;column:upper_level_response_nonzero;cross:s:s_copy",
      s_copy = "column:upper_level;column:upper_level_response_nonzero;cross:s:s_copy"))
  out <- review$presentation
  expect_identical(names(out), c("id", "term", "label", "unit", "estimate", "se", "statistic",
    "p_value", "lower", "upper", "aliased", "coefficient_scale", "family", "link", "df",
    "confidence", "unweighted_n", "disclosure_status"))
  expect_identical(sort(names(attributes(out))), c("class", "names", "row.names"))
  expect_identical(class(out), "data.frame")
  expect_identical(out$aliased, c(NA, FALSE, TRUE, NA, NA))
  shown <- out$disclosure_status == "shown"
  for (column in c("estimate", "se", "statistic", "p_value", "lower", "upper")) {
    expect_identical(out[[column]][shown], table$data[[column]][shown])
    expect_true(all(is.na(out[[column]][!shown])))
  }
  expect_identical(out[c("id", "term", "label", "unit", "coefficient_scale", "family", "link",
    "df", "confidence")], table$data[c("id", "term", "label", "unit", "coefficient_scale",
    "family", "link", "df", "confidence")])
  expect_identical(out$unweighted_n, rep(60, 5L))
  hidden <- table$data$estimate[!shown & !is.na(table$data$estimate)]
  expect_true(length(hidden) > 0L)
  expect_false(any(unlist(lapply(out[vapply(out, is.numeric, logical(1))], function(v) v %in% hidden))))
  expect_false(any(c(6, 54) %in% unlist(out[vapply(out, is.numeric, logical(1))])))
  expect_identical(review$provenance$table_kind, "regression")
  expect_identical(review$provenance$scope, "experimental_disclosure_review")
  expect_identical(review$provenance$policy,
    list(suppress = c(1, 10), zero = "display", min_hospitals = 2, margins = list()))
  expect_identical(review$provenance$table, table$provenance)
  expect_false(review$provenance$analysis_ready)
  expect_identical(review$audit$sample, data.frame(supplied = 60, included = 60, missing = 0,
    hospitals = 4, binary_response = FALSE))
})

test_that("altered regression tables, margins and policies are refused", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  fit <- regression_fit(session, rows, c("y", "x"), y ~ x)
  table <- nis_regression_table(fit, regression_spec(fit), "link")
  before <- table
  altered <- function(change) {
    copy <- table
    change(copy)
  }
  unchanged <- "unchanged nis_regression_table"
  for (change in list(
    function(x) { x$data$estimate[[2L]] <- x$data$estimate[[2L]] + 1; x },
    function(x) { x$data$label[[1L]] <- "Relabeled"; x },
    function(x) { x$provenance$declarations$label[[1L]] <- "Relabeled"; x },
    function(x) { x$data$raw_included <- x$data$raw_included + 1; x },
    function(x) { x$factors <- list(extra = 1); x },
    function(x) { class(x) <- c("other", "nis_regression_table"); x },
    function(x) { x$extra <- 1; x })) {
    expect_error(nis_disclosure_review(altered(change), c(1, 10), "display", 2, list()), unchanged)
  }
  # A consistent forgery passes the table rebuild but not the retained fit.
  forged <- table
  forged$model$coefficients$estimate[[2L]] <- 0
  forged$data$estimate[[2L]] <- 0
  expect_error(nis_disclosure_review(forged, c(1, 10), "display", 2, list()),
    "retained model's fit, coefficients or factors are internally inconsistent")
  expect_error(nis_disclosure_review(structure(list(), class = "nis_regression_table"),
    c(1, 10), "display", 2, list()), unchanged)
  for (margins in list(list(list(total = "x", parts = "(Intercept)")), NULL, list(list()))) {
    expect_error(nis_disclosure_review(table, c(1, 10), "display", 2, margins), "margins = list\\(\\)")
  }
  expect_error(nis_disclosure_review(table, c(1, 10), "display", 2), "explicit")
  expect_error(nis_disclosure_review(table, c(0, 10), "display", 2, list()), "suppress")
  expect_error(nis_disclosure_review(table, c(1, 10), "hide", 2, list()), "zero")
  expect_error(nis_disclosure_review(table, c(1, 10), "display", 0, list()), "min_hospitals")
  expect_error(nis_disclosure_review(fit, c(1, 10), "display", 2, list()),
    "nis_descriptive_table or nis_regression_table")
  expect_identical(table, before)
})

test_that("regression reviews are not exportable and descriptive reviews keep their shape", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  fit <- regression_fit(session, rows, c("y", "x"), y ~ x)
  review <- regression_review(fit)
  before <- review
  path <- tempfile(fileext = ".csv")
  expect_error(nis_export_table(review, path, "csv", NULL, "keep", FALSE),
    "Regression disclosure reviews cannot be exported yet")
  expect_error(nis_export_table(review$table, path, "csv", NULL, "keep", FALSE),
    "Only a nis_disclosure_review")
  expect_false(file.exists(path))
  expect_identical(review, before)

  design <- regression_design(session, rows, c("y", "x"))
  descriptive <- nis_descriptive_table(design, data.frame(id = "y", field = "y",
    statistic = "mean", label = "Invented mean", unit = "days"), "fail", 8, 0.95, "wr_unadjusted")
  ordinary <- nis_disclosure_review(descriptive, c(1, 10), "display", 2, list())
  expect_identical(names(ordinary$provenance), c("policy", "rule_source", "count_basis",
    "complementary", "table", "scope", "analysis_ready"))
  expect_true(is.data.frame(ordinary$audit))
  expect_identical(ordinary$presentation$disclosure_status, "shown")
  expect_identical(ordinary$presentation$unweighted_n, 40)
})

test_that("intercept-only, transformed and offset models use their fitted rows", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  rows$count <- (seq_len(40L) %% 4L) + 1
  rows$exposure <- rep(c(1, 2), 20L)
  design <- regression_design(session, rows, c("y", "x", "count", "exposure"))
  fit <- function(formula, family = "gaussian") {
    nis_model(design, formula, family, "fail", 8, 0.95, "wr_unadjusted")
  }
  constant <- regression_review(fit(y ~ 1))
  expect_identical(regression_counts(constant, "model"), c(included = 40))
  expect_identical(regression_counts(constant, "column", "(Intercept)"),
    stats::setNames(numeric(), character()))
  expect_identical(constant$presentation$disclosure_status, "shown")
  # log1p(abs(x)) is zero exactly where x is zero.
  transformed <- regression_review(fit(log1p(abs(y)) ~ log1p(abs(x))))
  expect_identical(regression_counts(transformed, "column", "log1p(abs(x))"),
    c(nonzero = 27, zero_valued = 13))
  expect_identical(transformed$audit$sample$binary_response, FALSE)
  offset <- regression_review(fit(count ~ x + offset(log(exposure)), "quasipoisson"))
  expect_identical(regression_counts(offset, "column", "x"), c(nonzero = 27, zero_valued = 13))
  expect_identical(offset$audit$rows$term, c("(Intercept)", "x"))
  expect_identical(unname(regression_status(offset)), c("shown", "shown"))
})

test_that("interaction cells, including the reference cell, are crossed and checked", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Cells A/F, A/M, B/F, B/M in consecutive blocks over six hospitals; events
  # are the even rows, which lie in hospitals 2, 4 and 6.
  logistic <- function(sizes) {
    rows <- regression_rows(sum(sizes), hospitals = 6L)
    rows$g <- rep(c(1, 1, 2, 2), sizes)
    rows$s <- rep(c(1, 2, 1, 2), sizes)
    rows$event <- as.double(seq_len(sum(sizes)) %% 2L == 0L)
    regression_fit(session, rows, c("event", "g", "s"), event ~ group * sex, "quasibinomial",
      group = c("A", "B"), sex = c("F", "M"))
  }
  small <- regression_review(logistic(c(3, 50, 50, 50)))
  expect_identical(regression_counts(small, "model"), c(included = 153, events = 76, nonevents = 77))
  expect_identical(regression_counts(small, "cross", "group:sex"),
    c("cell:A:F" = 3, "cell_events:A:F" = 1, "cell_nonevents:A:F" = 2,
      "cell:B:F" = 50, "cell_events:B:F" = 25, "cell_nonevents:B:F" = 25,
      "cell:A:M" = 50, "cell_events:A:M" = 25, "cell_nonevents:A:M" = 25,
      "cell:B:M" = 50, "cell_events:B:M" = 25, "cell_nonevents:B:M" = 25))
  expect_identical(regression_counts(small, "cross", "group:sex", "hospitals"),
    c("cell:A:F" = 3, "cell_events:A:F" = 1, "cell_nonevents:A:F" = 2,
      "cell:B:F" = 6, "cell_events:B:F" = 3, "cell_nonevents:B:F" = 3,
      "cell:A:M" = 6, "cell_events:A:M" = 3, "cell_nonevents:A:M" = 3,
      "cell:B:M" = 6, "cell_events:B:M" = 3, "cell_nonevents:B:M" = 3))
  # Every marginal group is safe; only the crossed reference cell fails.
  expect_identical(regression_counts(small, "factor", c("group", "sex")),
    c("level:A" = 53, "level_events:A" = 26, "level_nonevents:A" = 27,
      "level:B" = 100, "level_events:B" = 50, "level_nonevents:B" = 50,
      "level:F" = 53, "level_events:F" = 26, "level_nonevents:F" = 27,
      "level:M" = 100, "level_events:M" = 50, "level_nonevents:M" = 50))
  expect_identical(regression_reasons(small), c("(Intercept)" = "cross:group:sex",
    groupB = "cross:group:sex", sexM = "cross:group:sex", "groupB:sexM" = "cross:group:sex"))
  expect_true(all(is.na(small$presentation$estimate)))
  safe <- regression_review(logistic(c(22, 50, 50, 50)))
  expect_identical(regression_counts(safe, "cross", "group:sex")[1:3],
    c("cell:A:F" = 22, "cell_events:A:F" = 11, "cell_nonevents:A:F" = 11))
  expect_identical(unname(regression_status(safe)), rep("shown", 4L))

  # Two-valued numeric predictors are crossed the same way.
  rows <- regression_rows(93L)
  rows$a <- rep(c(0, 1, 0, 1), c(3, 30, 30, 30))
  rows$b <- rep(c(0, 0, 1, 1), c(3, 30, 30, 30))
  rows$y <- 1 + rows$a + rows$b + regression_noise(93L)
  numeric <- regression_review(regression_fit(session, rows, c("y", "a", "b"), y ~ a * b))
  expect_identical(regression_counts(numeric, "column", c("a", "b", "a:b")),
    c(lower_level = 33, upper_level = 60, lower_level = 33, upper_level = 60,
      lower_level = 63, upper_level = 30))
  expect_identical(regression_counts(numeric, "cross", "a:b"),
    c("cell:0:0" = 3, "cell:1:0" = 30, "cell:0:1" = 30, "cell:1:1" = 30))
  expect_identical(unname(regression_reasons(numeric)), rep("cross:a:b", 4L))
})

test_that("empty interaction cells and all-zero indicators follow the zero policy", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(120L)
  rows$g <- rep(c(1, 1, 2), each = 40L)
  rows$s <- rep(c(1, 2, 1), each = 40L)
  rows$y <- 1 + rows$g + rows$s + regression_noise(120L)
  fit <- regression_fit(session, rows, c("y", "g", "s"), y ~ group * sex,
    group = c("A", "B"), sex = c("F", "M"))
  expect_identical(fit$coefficients$aliased, c(FALSE, FALSE, FALSE, TRUE))
  display <- regression_review(fit)
  expect_identical(regression_counts(display, "cross", "group:sex"),
    c("cell:A:F" = 40, "cell:B:F" = 40, "cell:A:M" = 40, "cell:B:M" = 0))
  expect_identical(regression_counts(display, "cross", "group:sex", "hospitals"),
    c("cell:A:F" = 4, "cell:B:F" = 4, "cell:A:M" = 4, "cell:B:M" = 0))
  expect_identical(regression_counts(display, "column", "groupB:sexM"), c(nonzero = 0))
  expect_identical(unname(regression_status(display)), rep("shown", 4L))
  expect_identical(display$presentation$aliased, c(FALSE, FALSE, FALSE, TRUE))
  hidden <- regression_review(fit, zero = "suppress")
  expect_identical(regression_reasons(hidden),
    c("(Intercept)" = "reference:groupB:sexM;cross:group:sex", groupB = "cross:group:sex",
      sexM = "cross:group:sex",
      "groupB:sexM" = "column:nonzero;column:nonzero_response_nonzero;cross:group:sex"))
  expect_identical(hidden$presentation$aliased, rep(NA, 4L))

  # `site` is 1 only on rows whose outcome is missing, so it is all zero in the
  # analysis sample. Rows 5 and 20 had x = 0; rows 10 and 15 did not.
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  rows$site <- as.double(seq_len(40L) %in% c(5, 10, 15, 20))
  rows$y[rows$site == 1] <- NA
  site_fit <- regression_fit(session, rows, c("y", "x", "site"), y ~ x + site, missing = "exclude")
  shown <- regression_review(site_fit)
  expect_identical(shown$audit$sample[c("supplied", "included", "missing")],
    data.frame(supplied = 40, included = 36, missing = 4))
  expect_identical(regression_counts(shown, "column", c("x", "site")),
    c(nonzero = 25, zero_valued = 11, nonzero = 0))
  expect_identical(unname(regression_status(shown)), rep("shown", 3L))
  expect_identical(regression_reasons(regression_review(site_fit, zero = "suppress")),
    c("(Intercept)" = "reference:site", x = "", site = "column:nonzero;column:nonzero_response_nonzero"))
})

test_that("a count of exactly one is the lower edge of the range", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$solo <- as.double(seq_len(40L) == 7L)
  rows$y <- 1 + 0.5 * rows$x + rows$solo + regression_noise(40L)
  fit <- regression_fit(session, rows, c("y", "x", "solo"), y ~ x + solo)
  inside <- regression_review(fit, min_hospitals = 1)
  expect_identical(regression_counts(inside, "column", "solo"), c(lower_level = 39, upper_level = 1))
  expect_identical(regression_counts(inside, "column", "solo", "hospitals"),
    c(lower_level = 4, upper_level = 1))
  expect_identical(regression_reasons(inside),
    c("(Intercept)" = "reference:solo", x = "",
      solo = "column:upper_level;column:upper_level_response_nonzero"))
  outside <- regression_review(fit, suppress = c(2, 10), min_hospitals = 1)
  expect_identical(unname(regression_status(outside)), rep("shown", 3L))
})

test_that("missing exclusions, including a whole hospital, leave only fitted rows", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Eight hospitals; hospital 8 holds rows 8, 16, ..., 64 and loses every
  # outcome. Rows 1 and 2 lose x. Zero x rows (i %% 3 == 2) lost: 2, 8, 32, 56.
  rows <- regression_rows(64L, hospitals = 8L)
  hospital <- (seq_len(64L) - 1L) %% 8L + 1L
  rows$x <- rep(c(-1, 0, 2), length.out = 64L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(64L)
  rows$y[hospital == 8L] <- NA
  rows$x[1:2] <- NA
  fit <- regression_fit(session, rows, c("y", "x"), y ~ x, missing = "exclude")
  review <- regression_review(fit)
  expect_identical(review$audit$sample, data.frame(supplied = 64, included = 54, missing = 10,
    hospitals = 7, binary_response = FALSE))
  expect_identical(regression_counts(review, "model", value = "hospitals"), c(included = 7))
  expect_identical(regression_counts(review, "column", "x"), c(nonzero = 37, zero_valued = 17))
  expect_identical(regression_counts(review, "column", "x", "hospitals"),
    c(nonzero = 7, zero_valued = 7))
  expect_identical(review$presentation$unweighted_n, c(54, 54))
  expect_identical(regression_reasons(regression_review(fit, min_hospitals = 8)),
    c("(Intercept)" = "model:hospitals_included;model:hospitals_response_nonzero;reference:x",
      x = paste0("model:hospitals_included;model:hospitals_response_nonzero;column:hospitals_nonzero;",
        "column:hospitals_nonzero_response_nonzero;column:hospitals_zero_valued;column:hospitals_zero_valued_response_nonzero")))
})

test_that("any two-valued response checks its response-value cells", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Group A is rows 1-50 with the upper response at rows 1-3 (hospitals 1-3);
  # group B is rows 51-100 with the upper response at rows 76-100.
  coded <- function(lower, upper) {
    rows <- regression_rows(100L)
    rows$g <- rep(c(1, 2), each = 50L)
    rows$y <- ifelse(seq_len(100L) %in% c(1:3, 76:100), upper, lower)
    regression_review(regression_fit(session, rows, c("y", "g"), y ~ group, group = c("A", "B")))
  }
  two <- coded(1, 2)
  expect_identical(two$audit$sample$binary_response, TRUE)
  expect_identical(regression_counts(two, "model"), c(included = 100, events = 28, nonevents = 72))
  expect_identical(regression_counts(two, "factor", "group"),
    c("level:A" = 50, "level_events:A" = 3, "level_nonevents:A" = 47,
      "level:B" = 50, "level_events:B" = 25, "level_nonevents:B" = 25))
  expect_identical(regression_reasons(two), c("(Intercept)" = "reference:groupB;factor:group",
    groupB = "column:lower_level_events;factor:group"))
  expect_true(all(is.na(two$presentation$estimate)))
  binary <- coded(0, 1)
  expect_identical(binary$audit$groups[c("check", "level", "count", "hospitals")],
    two$audit$groups[c("check", "level", "count", "hospitals")])
  expect_identical(regression_reasons(binary), regression_reasons(two))
})

test_that("factor and two-valued predictors are crossed jointly, even additively", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Blocks of cells over six hospitals; events are the even rows.
  cells_fit <- function(sizes, formula) {
    rows <- regression_rows(sum(sizes), hospitals = 6L)
    rows$g <- rep(c(1, 1, 2, 2), sizes)
    rows$s <- rep(c(1, 2, 1, 2), sizes)
    rows$event <- as.double(seq_len(sum(sizes)) %% 2L == 0L)
    regression_fit(session, rows, c("event", "g", "s"), formula, "quasibinomial",
      group = c("A", "B"), sex = c("F", "M"))
  }
  # An empty B/M cell makes the additive fit saturated: the intercept is the
  # logit of the 3-row A/F cell.
  additive <- regression_review(cells_fit(c(3, 50, 50, 0), event ~ group + sex))
  expect_identical(regression_counts(additive, "cross", "group:sex")[c(1:3, 10:12)],
    c("cell:A:F" = 3, "cell_events:A:F" = 1, "cell_nonevents:A:F" = 2,
      "cell:B:M" = 0, "cell_events:B:M" = 0, "cell_nonevents:B:M" = 0))
  expect_identical(regression_counts(additive, "factor", "group"),
    c("level:A" = 53, "level_events:A" = 26, "level_nonevents:A" = 27,
      "level:B" = 50, "level_events:B" = 25, "level_nonevents:B" = 25))
  expect_identical(unname(regression_reasons(additive)), rep("cross:group:sex", 3L))
  # Only the non-reference B/M cell is small: rows 151-153 in hospitals 1-3,
  # whose single event (row 152) lies in hospital 2.
  corner <- regression_review(cells_fit(c(50, 50, 50, 3), event ~ group * sex))
  expect_identical(regression_counts(corner, "cross", "group:sex")[10:12],
    c("cell:B:M" = 3, "cell_events:B:M" = 1, "cell_nonevents:B:M" = 2))
  expect_identical(regression_counts(corner, "cross", "group:sex", "hospitals")[10:12],
    c("cell:B:M" = 3, "cell_events:B:M" = 1, "cell_nonevents:B:M" = 2))
  expect_identical(regression_reasons(corner), c(
    "(Intercept)" = "reference:groupB:sexM;cross:group:sex",
    groupB = "cross:group:sex", sexM = "cross:group:sex",
    "groupB:sexM" = paste0("column:upper_level;column:upper_level_events;",
      "column:upper_level_nonevents;column:hospitals_upper_level_events;cross:group:sex")))

  # Three-way crossing of two factors and a logical predictor: only A/F/FALSE
  # is small, and every marginal column group has at least 30 rows.
  sizes <- c(3, rep(30, 7L))
  rows <- regression_rows(sum(sizes))
  rows$g <- rep(c(1, 2, 1, 2, 1, 2, 1, 2), sizes)
  rows$s <- rep(c(1, 1, 2, 2, 1, 1, 2, 2), sizes)
  rows$flag <- rep(c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE), sizes)
  rows$y <- 1 + rows$g + rows$s + rows$flag + regression_noise(sum(sizes))
  three <- regression_review(regression_fit(session, rows, c("y", "g", "s", "flag"),
    y ~ group * sex * flag, group = c("A", "B"), sex = c("F", "M")))
  expect_identical(regression_counts(three, "cross", "group:sex:flag"),
    c("cell:A:F:FALSE" = 3, "cell:B:F:FALSE" = 30, "cell:A:M:FALSE" = 30, "cell:B:M:FALSE" = 30,
      "cell:A:F:TRUE" = 30, "cell:B:F:TRUE" = 30, "cell:A:M:TRUE" = 30, "cell:B:M:TRUE" = 30))
  expect_identical(regression_counts(three, "column", c("groupB:sexM:flagTRUE")),
    c(lower_level = 183, upper_level = 30))
  expect_identical(unname(regression_reasons(three)), rep("cross:group:sex:flag", 8L))

  # Factor by logical with a small non-reference B/TRUE cell (rows 91-93).
  sizes <- c(30, 30, 30, 3)
  rows <- regression_rows(sum(sizes))
  rows$g <- rep(c(1, 2, 1, 2), sizes)
  rows$flag <- rep(c(FALSE, FALSE, TRUE, TRUE), sizes)
  rows$y <- 1 + rows$g + rows$flag + regression_noise(sum(sizes))
  logical <- regression_review(regression_fit(session, rows, c("y", "g", "flag"),
    y ~ group * flag, group = c("A", "B")))
  expect_identical(regression_counts(logical, "cross", "group:flag"),
    c("cell:A:FALSE" = 30, "cell:B:FALSE" = 30, "cell:A:TRUE" = 30, "cell:B:TRUE" = 3))
  expect_identical(regression_reasons(logical), c(
    "(Intercept)" = "reference:groupB:flagTRUE;cross:group:flag", groupB = "cross:group:flag",
    flagTRUE = "cross:group:flag",
    "groupB:flagTRUE" = "column:upper_level;column:upper_level_response_nonzero;cross:group:flag"))

  # Factor by a 2/5 numeric predictor with a small non-reference A/5 cell.
  sizes <- c(30, 30, 3, 30)
  rows <- regression_rows(sum(sizes))
  rows$g <- rep(c(1, 2, 1, 2), sizes)
  rows$dose <- rep(c(2, 2, 5, 5), sizes)
  rows$y <- 1 + rows$g + 0.3 * rows$dose + regression_noise(sum(sizes))
  dose <- regression_review(regression_fit(session, rows, c("y", "g", "dose"),
    y ~ group * dose, group = c("A", "B")))
  expect_identical(regression_counts(dose, "column", c("dose", "groupB:dose")),
    c(lower_level = 60, upper_level = 33, nonzero = 60, zero_valued = 33))
  expect_identical(regression_counts(dose, "cross", "group:dose"),
    c("cell:A:2" = 30, "cell:B:2" = 30, "cell:A:5" = 3, "cell:B:5" = 30))
  expect_identical(unname(regression_reasons(dose)), rep("cross:group:dose", 4L))
})

test_that("an indicator equal to one on every row has an empty zero-valued group", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(40L)
  rows$x <- rep(c(-1, 0, 2), length.out = 40L)
  rows$y <- 1 + 0.5 * rows$x + regression_noise(40L)
  rows$one <- 1
  fit <- regression_fit(session, rows, c("y", "x", "one"), y ~ x + one)
  display <- regression_review(fit)
  expect_identical(regression_counts(display, "column", "one"), c(nonzero = 40, zero_valued = 0))
  expect_identical(unname(regression_status(display)), rep("shown", 3L))
  expect_identical(display$presentation$aliased, c(FALSE, FALSE, TRUE))
  expect_identical(regression_reasons(regression_review(fit, zero = "suppress")),
    c("(Intercept)" = "reference:one", x = "", one = "column:zero_valued;column:zero_valued_response_nonzero"))
})

test_that("joint crossings larger than 10000 cells are refused", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- regression_rows(100L)
  fields <- paste0("b", 1:14)
  for (k in seq_along(fields)) {
    rows[[fields[[k]]]] <- as.double(sin(seq_len(100L) * k * 1.7 + k) > 0)
  }
  rows$y <- regression_noise(100L) + rows$b1
  fit <- regression_fit(session, rows, c("y", fields),
    stats::reformulate(fields, response = "y"))
  expect_error(regression_review(fit), "more than 10000 cells")
})

test_that("a multi-valued response checks its nonzero rows in every group", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Group A is rows 1-50 with y = 1 only at rows 1-3 (hospitals 1-3). Group B
  # cycles 0, 1, 2 over rows 51-100: 17 zeros and 33 nonzero values.
  rows <- regression_rows(100L)
  rows$g <- rep(c(1, 2), each = 50L)
  rows$y <- c(rep(c(1, 0), c(3L, 47L)), rep(c(0, 1, 2), length.out = 50L))
  for (family in c("gaussian", "quasipoisson")) {
    review <- regression_review(regression_fit(session, rows, c("y", "g"), y ~ group, family,
      group = c("A", "B")))
    expect_identical(review$audit$sample$binary_response, FALSE)
    expect_identical(regression_counts(review, "model", nonzero = TRUE),
      c(included = 100, response_nonzero = 36))
    expect_identical(regression_counts(review, "factor", "group", nonzero = TRUE),
      c("level:A" = 50, "level_response_nonzero:A" = 3,
        "level:B" = 50, "level_response_nonzero:B" = 33))
    expect_identical(regression_counts(review, "factor", "group", "hospitals", nonzero = TRUE),
      c("level:A" = 4, "level_response_nonzero:A" = 3,
        "level:B" = 4, "level_response_nonzero:B" = 4))
    expect_identical(regression_reasons(review), c("(Intercept)" = "reference:groupB;factor:group",
      groupB = "column:lower_level_response_nonzero;factor:group"), info = family)
  }

  # One fractional value makes the P13 zero/one response three-valued; its
  # 3-row nonzero group in A is still checked.
  fractional <- regression_rows(100L)
  fractional$g <- rep(c(1, 2), each = 50L)
  fractional$y <- ifelse(seq_len(100L) %in% c(1:3, 76:100), 1, 0)
  fractional$y[[51L]] <- 0.5
  f1 <- regression_review(regression_fit(session, fractional, c("y", "g"), y ~ group,
    group = c("A", "B")))
  expect_identical(f1$audit$sample$binary_response, FALSE)
  expect_identical(regression_counts(f1, "model", nonzero = TRUE),
    c(included = 100, response_nonzero = 29))
  expect_identical(regression_reasons(f1), c("(Intercept)" = "reference:groupB;factor:group",
    groupB = "column:lower_level_response_nonzero;factor:group"))

  # A strictly positive response has no empty or small nonzero group.
  positive <- regression_rows(100L)
  positive$g <- rep(c(1, 2), each = 50L)
  positive$y <- 1 + positive$g + regression_noise(100L)
  shown <- regression_review(regression_fit(session, positive, c("y", "g"), y ~ group,
    group = c("A", "B")))
  expect_identical(regression_counts(shown, "factor", "group", nonzero = TRUE),
    c("level:A" = 50, "level_response_nonzero:A" = 50,
      "level:B" = 50, "level_response_nonzero:B" = 50))
  expect_identical(unname(regression_status(shown)), c("shown", "shown"))
  expect_false(any(shown$audit$groups$check == "response_zero_valued"))
})

test_that("a sparse multi-valued response matches the descriptive nonzero rule", {
  session <- nis_open()
  on.exit(nis_close(session))
  # Rows 1, 30 and 60 (hospitals 1, 2 and 4) hold the values 1, 2 and 1.
  rows <- regression_rows(100L)
  rows$y <- 0
  rows$y[c(1, 30, 60)] <- c(1, 2, 1)
  design <- regression_design(session, rows, "y")
  fit <- nis_model(design, y ~ 1, "quasipoisson", "fail", 8, 0.95, "wr_unadjusted")
  review <- regression_review(fit)
  expect_identical(regression_counts(review, "model", nonzero = TRUE),
    c(included = 100, response_nonzero = 3))
  expect_identical(regression_counts(review, "model", value = "hospitals", nonzero = TRUE),
    c(included = 4, response_nonzero = 3))
  expect_identical(regression_reasons(review), c("(Intercept)" = "model:response_nonzero"))
  expect_identical(review$presentation$unweighted_n, NA_real_)
  descriptive <- nis_descriptive_table(design, data.frame(id = "y", field = "y",
    statistic = "mean", label = "Invented mean", unit = "count"), "fail", 8, 0.95,
    "wr_unadjusted")
  ordinary <- nis_disclosure_review(descriptive, c(1, 10), "display", 2, list())
  expect_identical(ordinary$presentation$disclosure_status, "suppressed_primary")
  expect_identical(ordinary$audit$reasons, "nonzero")
})

test_that("a joint cell can fail on its hospital minimum alone", {
  session <- nis_open()
  on.exit(nis_close(session))
  # A/F is the 12 hospital-1 rows among rows 1-48; the other 108 rows cycle
  # through A/M, B/F and B/M and each span all four hospitals.
  hospital <- (seq_len(120L) - 1L) %% 4L + 1L
  cell <- rep(0L, 120L)
  cell[hospital == 1L & seq_len(120L) <= 48L] <- 1L
  cell[cell == 0L] <- rep(2:4, 36L)
  rows <- regression_rows(120L)
  rows$g <- c(1, 1, 2, 2)[cell]
  rows$s <- c(1, 2, 1, 2)[cell]
  rows$y <- 1 + rows$g + rows$s + regression_noise(120L)
  review <- regression_review(regression_fit(session, rows, c("y", "g", "s"), y ~ group * sex,
    group = c("A", "B"), sex = c("F", "M")))
  expect_identical(regression_counts(review, "cross", "group:sex"),
    c("cell:A:F" = 12, "cell:B:F" = 36, "cell:A:M" = 36, "cell:B:M" = 36))
  expect_identical(regression_counts(review, "cross", "group:sex", "hospitals"),
    c("cell:A:F" = 1, "cell:B:F" = 4, "cell:A:M" = 4, "cell:B:M" = 4))
  groups <- review$audit$groups
  af <- groups$scope == "cross" & groups$level == "A:F"
  expect_identical(groups$count_failed[af], c(FALSE, FALSE))
  expect_identical(groups$hospitals_failed[af], c(TRUE, TRUE))
  expect_identical(unname(regression_reasons(review)), rep("cross:group:sex", 4L))
})
