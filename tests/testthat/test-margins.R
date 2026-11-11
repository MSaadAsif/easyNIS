test_that("nis_rate agrees with survey totals and proportions", {
  skip_if_not_installed("survey")
  data <- data.frame(event = c(0, 1, 1, 0, 1, 0),
    group = factor(rep(c("a", "b"), 3)), w = c(1, 2, 3, 4, 2, 1),
    id = seq_len(6))
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  result <- nis_rate(design, event, by = group)
  expect_equal(result$weighted_events, c(5, 2))
  expect_equal(result$weighted_n, c(6, 7))
  expect_equal(result$proportion, c(5 / 6, 2 / 7))
  expect_equal(unname(result$n), c(3L, 3L))
  expect_equal(result$label[1], "5/6 (83.33%)")
})

test_that("nis_rate accepts synthetic indicators derived from labeled outcomes", {
  skip_if_not_installed("survey")
  data <- data.frame(DIED = factor(c("No", "Yes", "No", "Yes")),
    group = rep(c("a", "b"), each = 2), w = c(1, 2, 3, 4), id = 1:4)
  data$death <- as.integer(data$DIED == "Yes")
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)

  result <- nis_rate(design, death, by = group)

  expect_equal(result$weighted_events, c(2, 4))
  expect_equal(result$proportion, c(2 / 3, 4 / 7))
})

test_that("the descriptives article derives death after nis_design labels DIED", {
  nis <- nis_open(nis_example(years = 2019:2020)) |>
    nis_flag_dx(heart_failure = "I50")
  design <- nis_design(
    nis,
    cohort = AGE >= 18,
    keep = c(AGE, FEMALE, LOS, DIED, heart_failure),
    annualize = TRUE
  ) |>
    dplyr::mutate(death = as.integer(DIED == "Yes"))

  expect_true(is.factor(design$variables$DIED))
  expect_equal(design$variables$death,
    as.integer(design$variables$DIED == "Yes"))
  expect_true(any(!is.na(design$variables$death)))
})

test_that("nis_margins returns counterfactual margins and contrasts", {
  skip_if_not_installed("survey")
  set.seed(42)
  data <- data.frame(y = rnorm(500), x = factor(rep(c("a", "b"), 250)),
    z = rnorm(500), w = runif(500, 0.5, 2), id = seq_len(500))
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  fit <- survey::svyglm(y ~ x + z, design)
  result <- nis_margins(fit, x)
  expect_equal(result$margin[result$contrast == "margin"],
    c(mean(predict(fit, newdata = transform(data, x = "a"))),
      mean(predict(fit, newdata = transform(data, x = "b")))), tolerance = 0.05)
  expect_true(all(c("difference", "ratio") %in% result$contrast))
})

test_that("nis_margins retains offsets in point predictions and gradients", {
  skip_if_not_installed("survey")
  data <- data.frame(
    y = c(2, 2, 3, 3, 2, 2, 3, 3),
    x = factor(c("a", "a", "b", "b", "a", "a", "b", "b")),
    t = rep(2, 8),
    w = c(1, 2, 1, 2, 2, 1, 2, 1),
    id = seq_len(8)
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  fit <- survey::svyglm(y ~ x + offset(log(t)), design,
    family = stats::poisson())
  result <- nis_margins(fit, x)
  estimates <- result$margin[result$contrast == "margin"]
  expected <- vapply(levels(data$x), function(value) {
    counterfactual <- data
    counterfactual$x <- value
    terms <- stats::delete.response(stats::terms(fit))
    model_matrix <- stats::model.matrix(terms, counterfactual,
      contrasts.arg = fit$contrasts, xlev = fit$xlevels)
    model_matrix <- model_matrix[, names(stats::coef(fit)), drop = FALSE]
    eta <- drop(model_matrix %*% stats::coef(fit)) + log(counterfactual$t)
    weighted.mean(fit$family$linkinv(eta), counterfactual$w)
  }, numeric(1))

  expect_equal(unname(estimates), unname(expected), tolerance = 1e-8)
  expect_equal(estimates, c(2, 3), tolerance = 1e-8)
  first <- data
  first$x <- levels(data$x)[[1]]
  terms <- stats::delete.response(stats::terms(fit))
  model_matrix <- stats::model.matrix(terms, first,
    contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  model_matrix <- model_matrix[, names(stats::coef(fit)), drop = FALSE]
  eta <- drop(model_matrix %*% stats::coef(fit)) + log(first$t)
  gradient <- model_matrix * fit$family$mu.eta(eta)
  average_gradient <- colSums(gradient * first$w) / sum(first$w)
  expected_se <- sqrt(drop(average_gradient %*% stats::vcov(fit) %*%
    average_gradient))
  expect_equal(result$se[result$contrast == "margin"][[1]], expected_se,
    tolerance = 1e-8)
})

test_that("nis_margins aligns weights after excluding missing predictors", {
  skip_if_not_installed("survey")
  data <- data.frame(
    y = c(0, 1, 1, 0, 0, 1),
    x = factor(c("a", "a", "b", "b", "a", "b")),
    z = c(1, NA, 0, 1, 2, NA),
    w = c(1, 100, 2, 3, 4, 200),
    id = seq_len(6)
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  fit <- survey::svyglm(y ~ x + z, design, family = stats::quasibinomial())
  result <- nis_margins(fit, x, design = design)
  keep <- stats::complete.cases(data[c("x", "z")])
  complete <- data[keep, ]
  expected <- vapply(levels(data$x), function(value) {
    counterfactual <- complete
    counterfactual$x <- value
    prediction <- stats::predict(fit, newdata = counterfactual,
      type = "response")
    weighted.mean(prediction, complete$w)
  }, numeric(1))

  expect_equal(unname(result$margin[result$contrast == "margin"]),
    unname(expected), tolerance = 1e-8)
  expect_true(all(is.finite(result$se[result$contrast == "margin"])))
})

test_that("nis_margins aligns external offsets after missing predictors", {
  skip_if_not_installed("survey")
  data <- data.frame(
    y = c(0, 1, 1, 0, 0, 1, 1, 0),
    x = factor(c("a", "a", "b", "b", "a", "b", "a", "b")),
    z = c(1, NA, 0, 1, 2, NA, 0, 2),
    offset_value = c(-0.2, 0.7, 0.1, -0.4, 0.3, 0.8, -0.1, 0.2),
    w = c(1, 100, 2, 3, 4, 200, 2, 1),
    id = seq_len(8)
  )
  external_offset <- data$offset_value
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  external_fit <- survey::svyglm(y ~ x + z, design,
    family = stats::quasibinomial(), offset = external_offset)
  formula_fit <- survey::svyglm(y ~ x + z + offset(offset_value), design,
    family = stats::quasibinomial())

  external_result <- nis_margins(external_fit, x)
  formula_result <- nis_margins(formula_fit, x)
  full_result <- nis_margins(external_fit, x, design = design)
  subset_design <- design[1:6, ]
  subset_result <- nis_margins(external_fit, x, design = subset_design)
  subset_reference <- nis_margins(formula_fit, x, design = subset_design)
  reordered_design <- design[c(8, 7, 5, 4, 3, 1), ]
  reordered_result <- nis_margins(external_fit, x, design = reordered_design)
  reordered_reference <- nis_margins(formula_fit, x, design = reordered_design)
  unmapped_design <- subset_design
  rownames(unmapped_design$variables) <- paste0("other", seq_len(6))

  expect_equal(stats::coef(external_fit), stats::coef(formula_fit),
    tolerance = 1e-10)
  expect_equal(external_result$margin, formula_result$margin,
    tolerance = 1e-10)
  expect_equal(external_result$se, formula_result$se, tolerance = 1e-10)
  expect_equal(full_result$margin, formula_result$margin, tolerance = 1e-10)
  expect_equal(full_result$se, formula_result$se, tolerance = 1e-10)
  expect_equal(subset_result$margin, subset_reference$margin,
    tolerance = 1e-10)
  expect_equal(subset_result$se, subset_reference$se, tolerance = 1e-10)
  expect_equal(reordered_result$margin, reordered_reference$margin,
    tolerance = 1e-10)
  expect_equal(reordered_result$se, reordered_reference$se,
    tolerance = 1e-10)
  expect_error(nis_margins(external_fit, x, design = unmapped_design),
    "Cannot map the external model offset to design rows by row identity")
})

test_that("nis_rate uses survey interval columns rather than grouping names", {
  skip_if_not_installed("survey")
  data <- data.frame(
    event = c(0, 1, 1, 0, 1, 0, 1, 0),
    city = factor(rep(c("north", "south"), each = 4)),
    w = c(1, 2, 3, 2, 2, 1, 1, 3),
    id = seq_len(8)
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  result <- nis_rate(design, event, by = city)
  reference <- survey::svyby(~event, ~city, design, survey::svyciprop,
    vartype = "ci", method = "beta")

  reference <- as.data.frame(reference)
  expect_equal(result$conf.low, reference$ci_l)
  expect_equal(result$conf.high, reference$ci_u)
})

test_that("nis_rate counts valid non-missing groups and accepts string names", {
  skip_if_not_installed("survey")
  data <- data.frame(
    event = c(0, 1, 1, 0, 1, 1),
    check.names = FALSE,
    "risk group" = c("low", "low", "high", "high", NA, NA),
    w = c(1, 2, 3, 1, 50, 60),
    id = seq_len(6)
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  result <- nis_rate(design, event, by = "risk group")

  expect_identical(result[["risk group"]], c("high", "low"))
  expect_equal(result$n, c(2L, 2L))
  expect_equal(result$weighted_n, c(4, 3))
})

test_that("nis_rate preserves numeric outputs when a group name is reserved", {
  skip_if_not_installed("survey")
  data <- data.frame(
    event = c(0, 1, 1, 0, 1, 0),
    proportion = factor(c("low", "low", "high", "high", "low", "high"),
      levels = c("low", "high")),
    label = factor(c("first", "first", "second", "second", "first", "second")),
    w = c(1, 2, 3, 4, 2, 1),
    id = seq_len(6)
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  proportion_result <- nis_rate(design, event, by = proportion)
  label_result <- nis_rate(design, event, by = label)

  expect_identical(proportion_result$.group, c("low", "high"))
  expect_true(is.numeric(proportion_result$proportion))
  expect_equal(proportion_result$proportion, c(4 / 5, 3 / 8))
  expect_identical(label_result$.group, c("first", "second"))
  expect_true(all(grepl("/", label_result$label, fixed = TRUE)))
  expect_true(all(is.finite(label_result$weighted_n)))
})

test_that("nis_rate protects grouping columns from survey intermediates", {
  skip_if_not_installed("survey")
  data <- data.frame(
    event = c(0, 1, 1, 0, 1, 0, 1, 0),
    ci_l = rep(c("low", "high"), each = 4),
    ci_u = rep(c("north", "south"), each = 4),
    .nis_event = rep(c("group one", "group two"), each = 4),
    .nis_one = rep(c("first", "second"), each = 4),
    w = c(1, 2, 3, 2, 2, 1, 1, 3),
    id = seq_len(8),
    check.names = FALSE
  )
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)

  for (group in c("ci_l", "ci_u", ".nis_event", ".nis_one")) {
    result <- rlang::inject(nis_rate(design, event, by = !!rlang::sym(group)))
    expect_identical(result[[group]], sort(unique(data[[group]])))
    expect_true(is.numeric(result$proportion))
    expect_equal(result$weighted_events,
      unname(vapply(sort(unique(data[[group]])), function(value) {
        sum(data$event[data[[group]] == value] * data$w[data[[group]] == value])
      }, numeric(1))))
  }
})
