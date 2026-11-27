expect_gtsummary_statistics <- function(card, expected) {
  for (statistic in names(expected)) {
    actual <- unlist(card$stat[card$stat_name == statistic], use.names = FALSE)
    expect_length(actual, length(expected[[statistic]]))
    expect_true(all(abs(actual - expected[[statistic]]) <= 1e-8), info = statistic)
  }
}

expect_gtsummary_model <- function(body, reference, exponentiate = FALSE) {
  coefficients <- summary(reference)$coefficients
  terms <- setdiff(rownames(coefficients), "(Intercept)")
  body <- body[!is.na(body$estimate), ]
  expect_setequal(body$term, terms)
  coefficients <- coefficients[body$term, , drop = FALSE]
  interval <- stats::confint(reference)[body$term, , drop = FALSE]
  estimate <- coefficients[, 1L]
  if (exponentiate) {
    estimate <- exp(estimate)
    interval <- exp(interval)
  }
  expect_lt(max(abs(body$estimate - estimate)), 1e-8)
  expect_lt(max(abs(body$std.error - coefficients[, 2L])), 1e-8)
  expect_lt(max(abs(body$p.value - coefficients[, 4L])), 1e-8)
  expect_lt(max(abs(cbind(body$conf.low, body$conf.high) - interval)), 1e-8)
}

test_that("gtsummary tables preserve cohort counts and full-sample survey results", {
  skip_if_not_installed("gtsummary", minimum_version = "2.6.1")
  skip_if_not_installed("broom.helpers")
  skip_if_not_installed("cardx")

  query <- nis_open(shared_design_example(2019:2020)) |>
    nis_flag_dx(eligible = "I50", exposure = "Z515") |>
    dplyr::mutate(
      age_years = dplyr::if_else(LOS == 0L, NA_real_, as.double(AGE)),
      category = dplyr::case_when(LOS == 1L ~ NA_character_, FEMALE == 1L ~ "Female", TRUE ~ "Male"),
      event = as.integer(LOS %in% c(2L, 5L, 9L))
    )
  expect_s3_class(query, "tbl_lazy")
  design <- nis_design(query, eligible, keep = c(exposure, age_years, category, LOS, event))
  expect_gt(nrow(attr(design, "nis_placeholder_rows")), 0L)

  sample <- query |>
    dplyr::select(YEAR, HOSP_NIS, NIS_STRATUM, DISCWT, eligible, exposure, age_years, category, LOS, event) |>
    dplyr::collect() |>
    dplyr::mutate(
      psu = interaction(YEAR, HOSP_NIS),
      stratum = interaction(YEAR, NIS_STRATUM),
      exposure = factor(exposure, levels = c(FALSE, TRUE), labels = c("No", "Yes"))
    )
  reference <- survey::svydesign(~psu, strata = ~stratum, weights = ~DISCWT, data = sample, nest = TRUE) |>
    subset(eligible)

  table <- gtsummary::tbl_svysummary(
    design,
    by = exposure,
    include = c(age_years, category),
    statistic = list(age_years ~ "{mean} ({mean.std.error})", category ~ "{n_unweighted} ({p}%)"),
    missing = "always",
    missing_stat = "{N_miss_unweighted}"
  ) |>
    gtsummary::add_p(test = list(age_years ~ "svy.t.test", category ~ "svy.chisq.test")) |>
    gtsummary::add_overall() |>
    gtsummary::modify_header(gtsummary::all_stat_cols() ~ "{level}: {n_unweighted}")

  groups <- list(
    Overall = reference,
    No = subset(reference, exposure == "No"),
    Yes = subset(reference, exposure == "Yes")
  )
  header <- table$table_styling$header
  body <- table$table_body
  for (group in names(groups)) {
    domain <- groups[[group]]
    rows <- domain$variables
    heading <- header[which(header$modify_stat_level == group), ]
    expect_equal(heading$label, paste0(group, ": ", nrow(rows)))
    expect_lt(abs(heading$modify_stat_n - sum(stats::weights(domain))), 1e-8)
    expect_equal(
      body[[heading$column]][body$row_type == "missing"],
      as.character(colSums(is.na(rows[c("age_years", "category")])))
    )

    card <- if (group == "Overall") {
      table$cards$add_overall
    } else {
      dplyr::filter(table$cards$tbl_svysummary, vapply(group1_level, function(x) isTRUE(x == group), logical(1)))
    }
    age <- survey::svymean(~age_years, domain, na.rm = TRUE)
    expect_gtsummary_statistics(
      dplyr::filter(card, variable == "age_years"),
      list(mean = coef(age), mean.std.error = survey::SE(age))
    )
    proportions <- survey::svymean(~category, domain, na.rm = TRUE)
    totals <- survey::svytotal(~category, domain, na.rm = TRUE)
    for (level in c("Female", "Male")) {
      term <- paste0("category", level)
      count <- sum(rows$category == level, na.rm = TRUE)
      display <- body[[heading$column]][body$row_type == "level" & body$label == level]
      expect_equal(sub(" .*", "", display), as.character(count))
      expect_gtsummary_statistics(
        dplyr::filter(card, variable == "category", vapply(variable_level, function(x) isTRUE(x == level), logical(1))),
        list(
          n_unweighted = count,
          n = coef(totals)[[term]],
          p = coef(proportions)[[term]],
          p.std.error = survey::SE(proportions)[[term]]
        )
      )
    }
  }
  expect_lt(
    abs(
      body$p.value[body$variable == "age_years" & body$row_type == "label"] -
        survey::svyttest(age_years ~ exposure, reference)$p.value
    ),
    1e-8
  )
  expect_lt(
    abs(
      body$p.value[body$variable == "category" & body$row_type == "label"] -
        survey::svychisq(~ category + exposure, reference)$p.value
    ),
    1e-8
  )

  logistic <- survey::svyglm(event ~ age_years + exposure, design, family = stats::quasibinomial())
  logistic_ref <- survey::svyglm(event ~ age_years + exposure, reference, family = stats::quasibinomial())
  expect_gtsummary_model(gtsummary::tbl_regression(logistic, exponentiate = TRUE)$table_body, logistic_ref, TRUE)

  linear <- survey::svyglm(LOS ~ age_years + exposure, design)
  linear_ref <- survey::svyglm(LOS ~ age_years + exposure, reference)
  expect_gtsummary_model(gtsummary::tbl_regression(linear)$table_body, linear_ref)

  univariable <- gtsummary::tbl_uvregression(design, y = LOS, include = c(age_years, exposure), method = survey::svyglm)
  expect_gtsummary_model(
    univariable$table_body[univariable$table_body$variable == "age_years", ],
    survey::svyglm(LOS ~ age_years, reference)
  )
  expect_gtsummary_model(
    univariable$table_body[univariable$table_body$variable == "exposure", ],
    survey::svyglm(LOS ~ exposure, reference)
  )
})
