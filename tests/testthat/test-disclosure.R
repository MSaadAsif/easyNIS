disclosure_n <- 200L

# Hospital h holds rows 20 * (h - 1) + 1:20; strata split hospitals 1-5 and 6-10.
disclosure_base <- function() {
  n <- disclosure_n
  rows <- nis_synthetic_data()$core[rep(1L, n), ]
  rows$KEY_NIS <- sprintf("%06d", seq_len(n))
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(n) - 1L) %/% 20L + 1L)
  rows$NIS_STRATUM <- rep(1:2, each = 100L)
  rows$DISCWT <- 5
  rows
}

# An indicator for explicit row numbers.
at <- function(index) as.integer(seq_len(disclosure_n) %in% index)
# k events spaced 18 rows apart, so k > 1 events span more than one hospital.
spread <- function(k) at((seq_len(k) - 1L) * 18L + 1L)
# Partition the rows outside `taken` into consecutive groups of the given sizes.
partition <- function(taken, sizes) {
  free <- setdiff(seq_len(disclosure_n), taken)
  ends <- cumsum(sizes)
  lapply(seq_along(sizes), function(i) at(free[(ends[[i]] - sizes[[i]] + 1L):ends[[i]]]))
}

disclosure_rows <- function() {
  rows <- disclosure_base()
  for (k in c(0L, 1L, 9L, 10L, 11L)) rows[[paste0("c", k)]] <- spread(k)
  rows$rare <- spread(3L)
  rows$DISCWT[rows$rare == 1L] <- 5000
  rows$single <- at(1:20)
  rows$common <- 1L - spread(5L)
  rows$stay <- as.double(seq_len(disclosure_n) %% 7L + 1L)
  rows$stay_missing <- rows$stay
  rows$stay_missing[c(3, 50, 90, 140)] <- NA_real_
  rows$all <- 1L
  rows$cat_a <- spread(5L)
  categories <- partition(which(rows$cat_a == 1L), c(95L, 100L))
  rows$cat_b <- categories[[1]]
  rows$cat_c <- categories[[2]]
  rows$p1 <- spread(4L)
  rows$p2 <- at(c(10, 40, 80, 120, 160))
  parts <- partition(which(rows$p1 + rows$p2 == 1L), c(91L, 100L))
  rows$p3 <- parts[[1]]
  rows$p4 <- parts[[2]]
  events <- seq(6L, 180L, by = 6L)
  rows$v1 <- at(events[1:15])
  rows$v2 <- at(events[16:30])
  rows$v <- as.double(rows$v1 + rows$v2)
  rows$v[c(1, 2, 4, 5, 7)] <- NA_real_
  rows
}

disclosure_fields <- c("c0", "c1", "c9", "c10", "c11", "rare", "single", "common", "stay",
  "stay_missing", "all", "cat_a", "cat_b", "cat_c", "p1", "p2", "p3", "p4", "v", "v1", "v2")

disclosure_spec <- function(fields, statistic = "total", id = fields) {
  data.frame(id = id, field = fields, statistic = statistic,
    label = paste("Invented", id), unit = ifelse(statistic == "proportion", "proportion",
      "weighted discharges"), stringsAsFactors = FALSE)
}

disclosure_table <- function(session, rows = disclosure_rows(), fields = disclosure_fields,
                             spec = disclosure_spec(fields)) {
  path <- write_invented_parquet(session, rows)
  on.exit(unlink(path))
  design <- nis_survey_design(nis_import(session, path, 2022), unique(spec$field), TRUE,
    "hospital_wr", "fail")
  nis_descriptive_table(design, spec, "exclude", 8, 0.95, "wr_unadjusted")
}

review_status <- function(review) {
  stats::setNames(review$presentation$disclosure_status, review$presentation$id)
}

review_reasons <- function(review) stats::setNames(review$audit$reasons, review$audit$id)

disclosure_margins <- list(
  list(total = "all", parts = c("cat_a", "cat_b", "cat_c")),
  list(total = "all", parts = c("p1", "p2", "p3", "p4")),
  list(total = "v", parts = c("v1", "v2")))

test_that("invented fixture has the declared raw counts", {
  rows <- disclosure_rows()
  counts <- vapply(rows[c("c0", "c1", "c9", "c10", "c11", "rare", "single", "common")], sum, numeric(1))
  expect_identical(counts + 0, c(c0 = 0, c1 = 1, c9 = 9, c10 = 10, c11 = 11,
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
  status <- review_status(review)
  reasons <- review_reasons(review)
  expect_identical(unname(status[c("c0", "c1", "c9", "c10", "c11")]),
    c("shown", "suppressed_primary", "suppressed_primary", "suppressed_primary", "shown"))
  expect_identical(unname(reasons[c("c0", "c1", "c10", "c11")]),
    c("", "nonzero;hospitals_nonzero", "nonzero", ""))
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

test_that("rows sharing a field are suppressed together", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$all <- 1L
  rows$x <- spread(5L)
  groups <- partition(which(rows$x == 1L), c(60L, 135L))
  rows$y <- groups[[1]]
  rows$z <- groups[[2]]
  rows$DISCWT <- rep(c(5, 7), length.out = disclosure_n)
  spec <- disclosure_spec(c("all", "x", "x", "y", "y", "z", "z"),
    c("total", "total", "proportion", "total", "proportion", "total", "proportion"),
    c("all_n", "x_n", "x_pct", "y_n", "y_pct", "z_n", "z_pct"))
  table <- disclosure_table(session, rows, spec = spec)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all_n", parts = c("x_n", "y_n", "z_n"))))
  expect_identical(unname(review_status(review)), c("shown", "suppressed_primary",
    "suppressed_primary", "suppressed_complementary", "suppressed_complementary", "shown", "shown"))
  expect_identical(unname(review_reasons(review)[c("y_n", "y_pct")]), c("margin:1", "field:y_n"))
})

test_that("combinations of declared margins cannot determine a suppressed row", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(disclosure_n) - 1L) %% 10L + 1L)
  rows$NIS_STRATUM <- ifelse(rows$HOSP_NIS <= "0005", 1L, 2L)
  rows$all <- 1L
  rows$m_a <- at(1:8)
  rows$m_b <- at(21:27)
  rows$m_d <- at(41:46)
  rows$m_c <- 1L - rows$m_a - rows$m_b
  rows$m_e <- 1L - rows$m_a - rows$m_d
  rows$m_f <- 1L - rows$m_b - rows$m_d
  table <- disclosure_table(session, rows,
    fields = c("all", "m_a", "m_b", "m_c", "m_d", "m_e", "m_f"))
  margins <- list(list(total = "all", parts = c("m_a", "m_b", "m_c")),
    list(total = "all", parts = c("m_a", "m_d", "m_e")),
    list(total = "all", parts = c("m_b", "m_d", "m_f")))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_identical(unname(review_status(review)), c("shown", "suppressed_primary",
    "suppressed_primary", "suppressed_complementary", "suppressed_primary", "shown", "shown"))
  expect_identical(unname(review_reasons(review)[["m_c"]]), "margins:m_a")
  # Each relation alone leaves a nondisclosive suppressed pair.
  single <- nis_disclosure_review(table, c(1, 10), "display", 2, margins[1])
  expect_identical(unname(review_status(single)[["m_c"]]), "shown")
})

test_that("suppressed sums, unweighted n differences and other codings are checked", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$all <- 1L
  rows$h1 <- at(1:6)
  rows$h2 <- at(7:12)
  sums <- partition(1:12, c(88L, 100L))
  rows$h3 <- sums[[1]]
  rows$h4 <- sums[[2]]
  rows$s1 <- as.double(seq_len(disclosure_n) %% 5L)
  rows$s1[seq(2L, by = 13L, length.out = 15L)] <- NA_real_
  rows$s2 <- rows$s1
  rows$s2[seq(3L, by = 13L, length.out = 5L)] <- NA_real_
  rows$coded <- 1 + spread(3L)
  rows$coded_hospital <- 1 + at(1:12)
  rows$zeros <- 1L - at(1:12)
  rows$flag <- spread(5L) == 1L
  rows$big <- DBI::dbGetQuery(session$connection, paste0(
    "SELECT CAST(CASE WHEN i % 18 = 0 AND i < 72 THEN 1 ELSE 0 END AS BIGINT) x ",
    "FROM range(", disclosure_n, ") t(i)"))$x
  expect_s3_class(rows$big, "integer64")
  table <- disclosure_table(session, rows,
    fields = c("all", "h1", "h2", "h3", "h4", "s1", "s2", "coded", "coded_hospital",
      "zeros", "flag", "big"))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all", parts = c("h1", "h2", "h3", "h4"))))
  status <- review_status(review)
  reasons <- review_reasons(review)
  expect_identical(unname(status[c("all", "h1", "h2", "h3", "h4")]), c("shown",
    "suppressed_primary", "suppressed_primary", "suppressed_complementary", "shown"))
  expect_identical(unname(reasons[["h3"]]), "margin:1")
  expect_identical(table$data$raw_missing[6:7], c(15, 20))
  expect_identical(unname(status[c("s1", "s2")]), c("shown", "suppressed_complementary"))
  expect_identical(unname(reasons[["s2"]]), "n_difference:s1")
  expect_identical(unname(reasons[["coded"]]), "two_level")
  expect_identical(unname(status[["coded_hospital"]]), "suppressed_primary")
  expect_identical(unname(reasons[["coded_hospital"]]), "hospitals_two_level")
  expect_identical(unname(reasons[["zeros"]]), "hospitals_zero_valued")
  expect_identical(unname(reasons[c("flag", "big")]), c("nonzero", "nonzero"))
  expect_identical(review$audit$nonzero[review$audit$id %in% c("flag", "big")], c(5, 4))
})

test_that("subtotals cannot restore a disclosive primary-hidden sum", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  # Disjoint indicators; hospital membership does not itself force suppression.
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(disclosure_n) - 1L) %% 10L + 1L)
  rows$NIS_STRATUM <- ifelse(rows$HOSP_NIS <= "0005", 1L, 2L)
  rows$all <- 1L
  rows$a <- at(1:3)
  rows$b <- at(4:7)
  rows$c <- at(8:37)
  rows$d <- at(38:67)
  rows$s <- rows$c + rows$d
  rows$e <- 1L - rows$a - rows$b - rows$s
  fields <- c("all", "a", "b", "c", "d", "s", "e")
  table <- disclosure_table(session, rows, fields)
  margins <- list(list(total = "all", parts = c("a", "b", "c", "d", "e")),
    list(total = "s", parts = c("c", "d")))
  expect_identical(sum(rows$a + rows$b) + 0, 7)
  expect_identical(sum(rows$all - rows$s - rows$e) + 0, 7)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  status <- review_status(review)
  # all - s - e recovered the hidden pair before the combined-sum repair.
  expect_true(any(status[c("all", "s", "e")] != "shown"))
  expect_identical(unname(status[["s"]]), "suppressed_complementary")
  expect_match(unname(review_reasons(review)[["s"]]), "^margins_sum:")
  expect_true(all(is.na(review$presentation$estimate[status != "shown"])))

  # Three primary-hidden parts require the frozen relation subset, not pairs.
  rows$a <- at(1:3)
  rows$b <- at(4:6)
  rows$g <- at(7:9)
  rows$c <- at(10:39)
  rows$d <- at(40:69)
  rows$s <- rows$c + rows$d
  rows$e <- 1L - rows$a - rows$b - rows$g - rows$s
  margins[[1]]$parts <- c("a", "b", "g", "c", "d", "e")
  table <- disclosure_table(session, rows, c(fields, "g"))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_true(any(review_status(review)[c("all", "s", "e")] != "shown"))
})

test_that("primary pairs are protected even without a shared relation", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(disclosure_n) - 1L) %% 10L + 1L)
  rows$NIS_STRATUM <- ifelse(rows$HOSP_NIS <= "0005", 1L, 2L)
  rows$a <- at(1:3)
  rows$b <- at(4:7)
  rows$c <- at(8:37)
  rows$d <- at(38:67)
  rows$e <- at(68:127)
  rows$f <- at(128:200)
  rows$x <- rows$a + rows$c + rows$e
  rows$y <- rows$b + rows$d + rows$f
  rows$s <- rows$c + rows$d
  rows$t <- rows$e + rows$f
  table <- disclosure_table(session, rows, c("a", "b", "c", "d", "e", "f", "x", "y", "s", "t"))
  margins <- list(list(total = "x", parts = c("a", "c", "e")),
    list(total = "y", parts = c("b", "d", "f")),
    list(total = "s", parts = c("c", "d")),
    list(total = "t", parts = c("e", "f")))
  expect_identical(sum(rows$x + rows$y - rows$s - rows$t) + 0, 7)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_true(any(review_status(review)[c("x", "y", "s", "t")] != "shown"))
  expect_match(paste(review$audit$reasons, collapse = ";"), "margins_sum:pair:")
})

test_that("combined-margin sums apply zero and hospital policies", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$all <- 1L
  rows$a <- at(1:6)
  rows$b <- at(7:12)
  rows$c <- at(13:42)
  rows$d <- at(43:72)
  rows$s <- rows$c + rows$d
  rows$e <- 1L - rows$a - rows$b - rows$s
  fields <- c("all", "a", "b", "c", "d", "s", "e")
  margins <- list(list(total = "all", parts = c("a", "b", "c", "d", "e")),
    list(total = "s", parts = c("c", "d")))
  expect_identical(sum(rows$a + rows$b) + 0, 12)
  expect_identical(length(unique(rows$HOSP_NIS[rows$a + rows$b > 0])), 1L)
  table <- disclosure_table(session, rows, fields)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_identical(unname(review_status(review)[["s"]]), "suppressed_complementary")
  expect_match(unname(review_reasons(review)[["s"]]), "^margins_sum:")
  # With one hospital permitted, the recoverable sum of 12 passes this policy.
  review <- nis_disclosure_review(table, c(1, 10), "display", 1, margins)
  expect_identical(unname(review_status(review)[["s"]]), "shown")

  rows$HOSP_NIS <- sprintf("%04d", (seq_len(disclosure_n) - 1L) %% 10L + 1L)
  rows$NIS_STRATUM <- ifelse(rows$HOSP_NIS <= "0005", 1L, 2L)
  rows$all <- at(1:180)
  rows$a <- 0L
  rows$b <- 0L
  rows$c <- at(1:30)
  rows$d <- at(31:60)
  rows$s <- rows$c + rows$d
  rows$e <- rows$all - rows$s
  table <- disclosure_table(session, rows, fields)
  review <- nis_disclosure_review(table, c(1, 10), "suppress", 2, margins)
  expect_identical(unname(review_status(review)[["s"]]), "suppressed_complementary")
  expect_match(unname(review_reasons(review)[["s"]]), "^margins_sum:")
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_true(all(review_status(review) == "shown"))
})

test_that("declarations that alone determine hidden values fail closed", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- disclosure_base()
  rows$x <- at(1:100)
  rows$z <- 0L
  spec <- disclosure_spec(c("x", "x", "z"), c("total", "proportion", "total"),
    c("x_n", "x_pct", "z"))
  table <- disclosure_table(session, rows, spec = spec)
  # x = x + z declares z = 0 regardless of any published values.
  margins <- list(list(total = "x_n", parts = c("x_pct", "z")))
  expect_error(nis_disclosure_review(table, c(1, 10), "suppress", 2, margins),
    "declarations alone determine.*z")
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
