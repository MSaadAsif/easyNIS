disclosure_rows <- function() {
  n <- 200L
  rows <- nis_synthetic_data()$core[rep(1L, n), ]
  rows$KEY_NIS <- sprintf("%06d", seq_len(n))
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(n) - 1L) %/% 20L + 1L)
  rows$NIS_STRATUM <- rep(1:2, each = 100L)
  rows$DISCWT <- 5
  spread <- function(k) as.integer(seq_len(n) %in% ((seq_len(k) - 1L) * 18L + 1L))
  first <- function(rows_set) as.integer(seq_len(n) %in% rows_set)
  for (k in c(0L, 1L, 9L, 10L, 11L)) rows[[paste0("c", k)]] <- spread(k)
  rows$rare <- spread(3L)
  rows$DISCWT[rows$rare == 1L] <- 5000
  rows$single <- first(1:20)
  rows$common <- 1L - spread(5L)
  rows$stay <- as.double(seq_len(n) %% 7L + 1L)
  rows$stay_missing <- rows$stay
  rows$stay_missing[c(3, 50, 90, 140)] <- NA_real_
  rows$all <- 1L
  rows$cat_a <- spread(5L)
  rows$cat_b <- first(c(2:96, 190:200))[seq_len(n)] * (1L - rows$cat_a)
  rows$cat_b[cumsum(rows$cat_b) > 95L] <- 0L
  rows$cat_c <- 1L - rows$cat_a - rows$cat_b
  rows$p1 <- spread(4L)
  rows$p2 <- as.integer(seq_len(n) %in% c(10, 40, 80, 120, 160))
  rows$p3 <- as.integer(seq_len(n) %in% seq(3L, by = 2L, length.out = 120L)[!seq(3L, by = 2L,
    length.out = 120L) %in% which(rows$p1 + rows$p2 > 0L)][1:91])
  rows$p4 <- 1L - rows$p1 - rows$p2 - rows$p3
  rows$v <- as.integer(seq_len(n) %% 6L == 0L)[seq_len(n)]
  rows$v[seq_len(n) > 180L] <- 0L
  rows$v1 <- rows$v * as.integer(cumsum(rows$v) <= 15L)
  rows$v2 <- rows$v - rows$v1
  rows$v <- as.double(rows$v)
  rows$v[c(1, 2, 4, 5, 7)] <- NA_real_
  rows
}

disclosure_fields <- c("c0", "c1", "c9", "c10", "c11", "rare", "single", "common", "stay",
  "stay_missing", "all", "cat_a", "cat_b", "cat_c", "p1", "p2", "p3", "p4", "v", "v1", "v2")

disclosure_table <- function(session, rows = disclosure_rows(), fields = disclosure_fields,
                             statistic = "total") {
  path <- write_invented_parquet(session, rows)
  on.exit(unlink(path))
  design <- nis_survey_design(nis_import(session, path, 2022), fields, TRUE, "hospital_wr", "fail")
  spec <- data.frame(id = fields, field = fields, statistic = statistic,
    label = paste("Invented", fields), unit = "weighted discharges", stringsAsFactors = FALSE)
  nis_descriptive_table(design, spec, "exclude", 8, 0.95, "wr_unadjusted")
}

disclosure_margins <- list(
  list(total = "all", parts = c("cat_a", "cat_b", "cat_c")),
  list(total = "all", parts = c("p1", "p2", "p3", "p4")),
  list(total = "v", parts = c("v1", "v2")))

test_that("invented fixture has the declared raw counts", {
  rows <- disclosure_rows()
  expect_identical(vapply(rows[c("c0", "c1", "c9", "c10", "c11", "rare", "single", "common")],
    function(x) sum(x), numeric(1)) + 0, c(c0 = 0, c1 = 1, c9 = 9, c10 = 10, c11 = 11,
    rare = 3, single = 20, common = 195))
  expect_identical(c(sum(rows$cat_a), sum(rows$cat_b), sum(rows$cat_c)) + 0, c(5, 95, 100))
  expect_identical(c(sum(rows$p1), sum(rows$p2), sum(rows$p3), sum(rows$p4)) + 0, c(4, 5, 91, 100))
  expect_true(all(rows$p1 + rows$p2 + rows$p3 + rows$p4 == 1L))
  expect_true(all(rows$cat_a + rows$cat_b + rows$cat_c == 1L))
  expect_identical(c(sum(rows$v, na.rm = TRUE), sum(rows$v1), sum(rows$v2)) + 0, c(30, 15, 15))
  expect_identical(length(unique(rows$HOSP_NIS[rows$single == 1L])), 1L)
})

test_that("primary and complementary suppression follow unweighted counts and margins", {
  session <- nis_open()
  on.exit(nis_close(session))
  table <- disclosure_table(session)
  before <- table
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, disclosure_margins)
  expect_s3_class(review, "nis_disclosure_review")
  expect_identical(table, before)
  expect_identical(review$table, table)
  status <- stats::setNames(review$presentation$disclosure_status, review$presentation$id)
  reasons <- stats::setNames(review$audit$reasons, review$audit$id)
  expect_identical(unname(status[c("c0", "c1", "c9", "c10", "c11")]),
    c("shown", "suppressed_primary", "suppressed_primary", "suppressed_primary", "shown"))
  expect_identical(unname(reasons[c("c0", "c1", "c10", "c11")]), c("", "nonzero;hospitals_nonzero", "nonzero", ""))
  expect_identical(unname(status[["rare"]]), "suppressed_primary")
  expect_gt(table$data$weighted_estimate[table$data$id == "rare"], 10000)
  expect_identical(unname(reasons[["single"]]), "hospitals_nonzero")
  expect_identical(unname(reasons[["common"]]), "zero_valued")
  expect_identical(unname(status[["stay"]]), "shown")
  expect_identical(unname(reasons[["stay_missing"]]), "missing")
  expect_identical(unname(status[c("all", "cat_a", "cat_b", "cat_c")]),
    c("shown", "suppressed_primary", "suppressed_complementary", "shown"))
  expect_identical(unname(reasons[["cat_b"]]), "margin:1")
  expect_identical(unname(status[c("p1", "p2", "p3", "p4")]),
    c("suppressed_primary", "suppressed_primary", "suppressed_complementary", "shown"))
  expect_identical(unname(reasons[["p3"]]), "margin:2")
  expect_identical(unname(status[c("v", "v1", "v2")]),
    c("suppressed_primary", "suppressed_complementary", "shown"))
  expect_identical(unname(reasons[["v"]]), "missing")
  expect_identical(review$audit$margin_count[review$audit$id == "v"], 30)
})

test_that("presentation preserves shown values and carries no raw fields", {
  session <- nis_open()
  on.exit(nis_close(session))
  table <- disclosure_table(session)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, disclosure_margins)
  out <- review$presentation
  expect_identical(names(out), c("id", "label", "statistic", "unit", "estimand", "estimate",
    "se", "lower", "upper", "df", "confidence", "unweighted_n", "disclosure_status"))
  expect_identical(sort(names(attributes(out))), c("class", "names", "row.names"))
  expect_identical(class(out), "data.frame")
  shown <- out$disclosure_status == "shown"
  expect_identical(out$estimate[shown], table$data$weighted_estimate[shown])
  expect_identical(out$se[shown], table$data$se[shown])
  expect_identical(out$lower[shown], table$data$lower[shown])
  expect_identical(out$upper[shown], table$data$upper[shown])
  expect_identical(out$unweighted_n[shown], table$data$raw_included[shown])
  expect_identical(out$estimate[out$id == "c0"], 0)
  for (column in c("estimate", "se", "lower", "upper", "unweighted_n")) {
    expect_true(all(is.na(out[[column]][!shown])))
  }
  expect_identical(out$id, table$data$id)
  expect_false(review$provenance$analysis_ready)
  expect_identical(review$provenance$scope, "experimental_disclosure_review")
  expect_identical(review$provenance$policy$suppress, c(1, 10))
  expect_identical(review$provenance$table, table$provenance)
})

test_that("zero policy, ranges and hospital thresholds are explicit", {
  session <- nis_open()
  on.exit(nis_close(session))
  table <- disclosure_table(session, fields = c("c0", "c11", "stay"))
  status <- function(...) nis_disclosure_review(table, ...)$presentation$disclosure_status
  expect_identical(status(c(1, 10), "display", 2, list()), c("shown", "shown", "shown"))
  expect_identical(status(c(1, 10), "suppress", 2, list()),
    c("suppressed_primary", "shown", "shown"))
  expect_identical(status(c(1, 11), "display", 2, list()),
    c("shown", "suppressed_primary", "shown"))
  expect_identical(status(c(1, 10), "display", 10, list()), rep("shown", 3))
  expect_identical(status(c(1, 10), "display", 11, list()), rep("suppressed_primary", 3))
})

test_that("pooled reviews keep reused hospital identifiers distinct by year", {
  session <- nis_open()
  on.exit(nis_close(session))
  designs <- lapply(c(2021, 2022), function(year) {
    core <- nis_synthetic_data(year)$core
    core$event <- as.integer(core$HOSP_NIS == "0001")
    path <- write_invented_parquet(session, core)
    on.exit(unlink(path), add = TRUE)
    nis_survey_design(nis_import(session, path, year), "event", TRUE, "hospital_wr", "fail")
  })
  pool <- nis_pool_design(designs, "event", "combined_total")
  spec <- data.frame(id = "event", field = "event", statistic = "total",
    label = "Invented events", unit = "weighted discharges")
  table <- nis_descriptive_table(pool, spec, "fail", 2, 0.95, "wr_unadjusted")
  expect_gt(table$data$raw_included, 0)
  review <- nis_disclosure_review(table, c(1, 1), "display", 2, list())
  expect_identical(review$audit$hospitals_nonzero, 2)
  expect_identical(review$presentation$disclosure_status, "shown")
  expect_identical(nis_disclosure_review(table, c(1, 1), "display", 3, list())$audit$reasons,
    "hospitals_nonzero")
})

test_that("invalid policies, inputs and margins are refused", {
  session <- nis_open()
  on.exit(nis_close(session))
  table <- disclosure_table(session, fields = c("all", "cat_a", "cat_b", "cat_c"))
  ok <- list(list(total = "all", parts = c("cat_a", "cat_b", "cat_c")))
  expect_error(nis_disclosure_review(table, c(1, 10), "display", 2), "explicit")
  expect_error(nis_disclosure_review(table$data, c(1, 10), "display", 2, ok), "nis_descriptive_table")
  for (bad in list(c(0, 10), c(10, 1), c(1.5, 10), 10, c(1, NA), c(1, Inf), "1")) {
    expect_error(nis_disclosure_review(table, bad, "display", 2, ok), "suppress")
  }
  expect_error(nis_disclosure_review(table, c(1, 10), "hide", 2, ok), "zero")
  for (bad in list(0, 1.5, c(1, 2), NA_real_, "2")) {
    expect_error(nis_disclosure_review(table, c(1, 10), "display", bad, ok), "min_hospitals")
  }
  invalid <- list(
    "x",
    list(list(total = "all")),
    list(list(total = "all", parts = c("cat_a", "missing_row"))),
    list(list(total = "all", parts = c("cat_a", "cat_a"))),
    list(list(total = "all", parts = c("all", "cat_a"))),
    list(list(total = c("all", "cat_a"), parts = "cat_b")),
    list(list(total = "all", parts = character())),
    list(list(total = "all", parts = c("cat_a", "cat_b", "cat_c"), extra = "x")))
  for (bad in invalid) {
    expect_error(nis_disclosure_review(table, c(1, 10), "display", 2, bad), "margin")
  }
  expect_error(nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all", parts = c("cat_a", "cat_b")))), "does not equal")
  expect_s3_class(nis_disclosure_review(table, c(1, 10), "display", 2, ok),
    "nis_disclosure_review")
})
