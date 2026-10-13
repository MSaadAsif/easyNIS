test_that("analysis factors preserve raw values, design information and declared mappings", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group[1L] <- NA
  design <- model_design(session, rows)
  before <- design
  options_before <- options()
  result <- nis_factor(design, "group", "group_factor", c(1, 0, 2),
    c("Exposed", "Comparator", "Unused"))
  expected <- factor(rows$group, levels = c(1, 0, 2), labels = c("Exposed", "Comparator", "Unused"))
  expect_identical(result$design$variables$group_factor, expected)
  expect_identical(result$design$variables[names(design$design$variables)], design$design$variables)
  for (slot in setdiff(names(design$design), "variables")) {
    expect_identical(result$design[[slot]], design$design[[slot]])
  }
  expect_identical(result$population, design$population)
  expect_identical(result$domains, design$domains)
  expect_identical(result$provenance$columns, names(result$design$variables))
  expect_false(result$provenance$analysis_ready)
  declaration <- result$provenance$analysis_transforms[[1L]]
  expect_identical(declaration, list(type = "factor", field = "group", name = "group_factor",
    levels = c(1, 0, 2), labels = c("Exposed", "Comparator", "Unused"),
    raw_preserved = TRUE, mapping_status = "caller_declared_unverified"))
  expect_identical(design, before)
  expect_identical(options(), options_before)
  second <- nis_factor(result, "domain", "domain_factor", c(FALSE, TRUE), c("Outside", "Inside"))
  expect_length(second$provenance$analysis_transforms, 2L)
  expect_identical(second$provenance$analysis_transforms[[1L]], declaration)
  expect_identical(second$design$variables$group_factor, expected)
})

test_that("character labels, raw missingness and close numeric categories stay distinct", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  design$design$variables$raw_text <- rep(c("NA", NA, "", "No"), 16L)
  result <- nis_factor(design, "raw_text", "labelled text", c("No", "", "NA"),
    c("Comparator", "Explicit empty string", "NA"))
  expect_identical(as.character(result$design$variables[["labelled text"]]),
    rep(c("NA", NA, "Explicit empty string", "Comparator"), 16L))
  expect_identical(is.na(result$design$variables[["labelled text"]]),
    is.na(design$design$variables$raw_text))
  design$design$variables$x <- rep(c(1, 1 + .Machine$double.eps, NA, NaN), 16L)
  close <- nis_factor(design, "x", "precise", c(1 + .Machine$double.eps, 1), c("Higher", "Lower"))
  expect_identical(as.integer(close$design$variables$precise), rep(c(2L, 1L, NA_integer_, NA_integer_), 16L))
  expect_identical(close$design$variables$x, design$design$variables$x)
  selected <- nis_domain(result, ~ `labelled text` == "NA", "exclude")
  expect_identical(as.character(selected$design$variables[["labelled text"]]), rep("NA", 16L))
  expect_identical(selected$domains[[1L]]$unknown, 16L)
})

test_that("factor models match explicit native factors and independent WR references", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group[rows$HOSP_NIS == "0004"] <- NA
  design <- model_design(session, rows)
  for (domain in c(FALSE, TRUE)) {
    selected <- if (domain) nis_domain(design, "domain", "fail") else design
    prepared <- nis_factor(selected, "group", "group_factor", c(1, 0), c("Exposed", "Comparator"))
    manual <- selected
    manual$design$variables$group_factor <- factor(manual$design$variables$group,
      levels = c(1, 0), labels = c("Exposed", "Comparator"))
    batch <- nis_models(prepared, c(y = "gaussian", binary = "quasibinomial"),
      ~ x + group_factor, "exclude", 6, 0.95, "wr_unadjusted")
    direct <- nis_models(manual, c(y = "gaussian", binary = "quasibinomial"),
      ~ x + group_factor, "exclude", 6, 0.95, "wr_unadjusted")
    reference_rows <- rows
    reference_rows$group_factor <- factor(rows$group, levels = c(1, 0), labels = c("Exposed", "Comparator"))
    keep <- !is.na(rows$group) & if (domain) rows$domain else TRUE
    for (field in c("y", "binary")) {
      result <- batch$models[[field]]
      expect_identical(result$coefficients, direct$models[[field]]$coefficients)
      expect_identical(result$factors, direct$models[[field]]$factors)
      expect_identical(result$sample, direct$models[[field]]$sample)
      family <- if (field == "y") stats::gaussian() else stats::quasibinomial()
      reference <- model_sandwich(reference_rows, stats::reformulate(c("x", "group_factor"), field), family, keep)
      expect_equal(stats::coef(result$native), reference$coefficients, tolerance = 1e-8)
      expect_lt(max(abs(stats::vcov(result$native) - reference$covariance)),
        if (field == "y") 1e-10 else 1e-7)
      expect_identical(result$provenance$design$analysis_transforms,
        prepared$provenance$analysis_transforms)
    }
  }
})

test_that("pooled, unused, single-level and empty-domain factors retain design structure", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  second <- rows
  second$YEAR <- 2021L
  pooled <- nis_pool_design(list(model_design(session, rows), model_design(session, second)),
    c("group", "domain", "y"), "combined_total")
  result <- nis_factor(pooled, "group", "group_factor", c(0, 1, 2), c("A", "B", "Unused"))
  expect_identical(result$population, pooled$population)
  expect_identical(result$design$cluster, pooled$design$cluster)
  expect_length(unique(result$design$cluster[[1L]]), 16L)
  expect_identical(levels(result$design$variables$group_factor), c("A", "B", "Unused"))
  fit <- nis_model(result, y ~ group_factor, "gaussian", "fail", 12, 0.95, "wr_unadjusted")
  reference_rows <- rbind(rows, second)
  reference_rows$group_factor <- factor(reference_rows$group, levels = c(0, 1, 2),
    labels = c("A", "B", "Unused"))
  reference <- model_sandwich(reference_rows, y ~ group_factor, stats::gaussian(),
    rep(TRUE, nrow(reference_rows)))
  expect_equal(stats::coef(fit$native), reference$coefficients, tolerance = 1e-10)
  expect_lt(max(abs(stats::vcov(fit$native) - reference$covariance)), 1e-10)
  domain <- nis_domain(pooled, ~ group == 0, "fail")
  single <- nis_factor(domain, "group", "one_level", 0, "Only")
  expect_identical(levels(single$design$variables$one_level), "Only")
  expect_true(all(as.integer(single$design$variables$one_level) == 1L))
  empty <- nis_domain(pooled, ~ group < -100, "fail")
  prepared <- nis_factor(empty, "group", "empty_factor", c(0, 1), c("A", "B"))
  expect_length(prepared$design$variables$empty_factor, 0L)
  expect_identical(levels(prepared$design$variables$empty_factor), c("A", "B"))
  expect_identical(prepared$domains, empty$domains)
})

test_that("undeclared values reject without exposing records or modifying callers", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group[c(1L, 2L)] <- -9
  design <- model_design(session, rows)
  before <- design
  error <- tryCatch(nis_factor(design, "group", "group_factor", c(0, 1), c("A", "B")), error = identity)
  expect_s3_class(error, "nis_factor_error")
  expect_identical(error$field, "group")
  expect_identical(error$affected, 2L)
  expect_false(any(c("records", "values", "result", "design") %in% names(error)))
  expect_false(grepl("-9", conditionMessage(error), fixed = TRUE))
  expect_identical(design, before)
  result <- nis_factor(design, "group", "group_factor", c(0, 1, -9), c("A", "B", "Declared sentinel"))
  expect_false(anyNA(result$design$variables$group_factor))
  expect_identical(result$design$variables$group, rows$group)
})

test_that("level order does not override the caller's chosen contrast scheme", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  saved <- options(contrasts = c("contr.sum", "contr.poly"))
  on.exit(options(saved), add = TRUE)
  before <- getOption("contrasts")
  result <- nis_factor(design, "group", "group_factor", c(1, 0), c("Exposed", "Comparator"))
  expect_null(attr(result$design$variables$group_factor, "contrasts"))
  expect_identical(getOption("contrasts"), before)
  fit <- nis_model(result, y ~ group_factor, "gaussian", "fail", 6, 0.95, "wr_unadjusted")
  expect_length(fit$factors$group_factor$zero_coded_levels, 0L)
  expect_equal(unname(fit$factors$group_factor$contrasts), unname(stats::contr.sum(2)))
})

test_that("factor declarations reject unsafe shapes, collisions and implicit mappings", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  expect_error(nis_factor(NULL, "group", "new", c(0, 1), c("A", "B")), "nis_survey")
  expect_error(nis_factor(design, "unknown", "new", c(0, 1), c("A", "B")), "not retained")
  for (name in c("group", "GROUP", "YEAR", " ", ".survey.prob.weights", "(weights)", "(offset)")) {
    expect_error(nis_factor(design, "group", name, c(0, 1), c("A", "B")), "new nonblank factor name")
  }
  expect_error(nis_factor(design, "group", "new"), "explicit raw levels")
  for (level in list(numeric(), c(0, 0), c(0, NA), c(0, Inf), c("0", "1"),
      matrix(c(0, 1)), structure(c(0, 1), class = "custom"), list(0, 1))) {
    expect_error(nis_factor(design, "group", "new", level, c("A", "B")), "Raw levels")
  }
  for (label in list(c("A", "A"), c("A", ""), c("A", " "), c("A", NA), "A",
      c(1, 2), factor(c("A", "B")), matrix(c("A", "B")))) {
    expect_error(nis_factor(design, "group", "new", c(0, 1), label), "unique nonblank")
  }
  invalid <- list(factor(design$design$variables$group), matrix(rep(TRUE, 64L)),
    structure(rep(TRUE, 64L), class = "custom"), rep(Inf, 64L), as.list(seq_len(64L)))
  for (value in invalid) {
    design$design$variables$bad <- value
    expect_error(nis_factor(design, "bad", "new", c(0, 1), c("A", "B")), "plain finite")
  }
})
