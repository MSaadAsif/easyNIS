test_that("nis_rate agrees with survey totals and proportions", {
  skip_if_not_installed("survey")
  data <- data.frame(event = c(0, 1, 1, 0, 1, 0),
    group = factor(rep(c("a", "b"), 3)), w = c(1, 2, 3, 4, 2, 1),
    id = seq_len(6))
  design <- survey::svydesign(ids = ~id, weights = ~w, data = data)
  result <- nis_rate(design, event, by = group)
  expect_equal(result$weighted_events, c(2, 3))
  expect_equal(result$weighted_n, c(4, 8))
  expect_equal(result$proportion, c(0.5, 0.375))
  expect_equal(result$n, c(3L, 3L))
  expect_match(result$label[1], "2/4 (50.00%)")
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
