export_n <- 200L

# Independent shortest exact decimal form of a double.
nis_test_exact <- function(x) {
  for (digits in 15:17) {
    text <- sprintf("%.*g", digits, x)
    if (as.numeric(text) == x) return(text)
  }
}

# Hospital h holds rows 20 * (h - 1) + 1:20; strata split hospitals 1-5 and 6-10.
export_rows <- function() {
  n <- export_n
  rows <- nis_synthetic_data()$core[rep(1L, n), ]
  rows$KEY_NIS <- sprintf("%06d", seq_len(n))
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(n) - 1L) %/% 20L + 1L)
  rows$NIS_STRATUM <- rep(1:2, each = 100L)
  rows$DISCWT <- 5 + (seq_len(n) %% 3L) / 3
  at <- function(index) as.integer(seq_len(n) %in% index)
  rows$c1 <- at(7L)
  rows$cat_a <- at(c(1L, 41L, 81L, 121L, 161L))
  rows$cat_b <- at(setdiff(1:100, which(rows$cat_a == 1L))[1:95])
  rows$cat_c <- 1L - rows$cat_a - rows$cat_b
  rows$all <- 1L
  rows$stay <- as.double(seq_len(n) %% 7L + 1L) / 3
  rows
}

export_spec <- data.frame(
  id = c("c1", "all", "cat_a", "cat_b", "cat_c", "stay", "share"),
  field = c("c1", "all", "cat_a", "cat_b", "cat_c", "stay", "cat_c"),
  statistic = c("total", "total", "total", "total", "total", "mean", "proportion"),
  label = c("Rare <b>event</b>", "All \"discharges\", total", "Category A",
    "Category B & C's sibling", "Category\nC", "Durée de séjour", "=Share of C"),
  unit = c("weighted discharges", "weighted discharges", "weighted discharges",
    "weighted discharges", "weighted discharges", "days <script>", "proportion"),
  stringsAsFactors = FALSE)

export_review <- function(session, df = Inf) {
  path <- write_invented_parquet(session, export_rows())
  on.exit(unlink(path))
  design <- nis_survey_design(nis_import(session, path, 2022), unique(export_spec$field),
    TRUE, "hospital_wr", "fail")
  table <- nis_descriptive_table(design, export_spec, "exclude", df, 0.9, "wr_unadjusted")
  nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all", parts = c("cat_a", "cat_b", "cat_c"))))
}

text_of <- function(path) paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")

test_that("CSV round-trips shown values exactly and leaves suppressed cells empty", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session)
  before <- review
  status <- stats::setNames(review$presentation$disclosure_status, review$presentation$id)
  expect_identical(unname(status[c("c1", "cat_a", "cat_b", "all", "cat_c", "stay")]),
    c("suppressed_primary", "suppressed_primary", "suppressed_complementary",
      "shown", "shown", "shown"))
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  returned <- nis_export_table(review, path, "csv", NULL, FALSE)
  expect_identical(returned, normalizePath(path))
  expect_identical(review, before)
  back <- utils::read.csv(path, encoding = "UTF-8", stringsAsFactors = FALSE)
  out <- review$presentation
  expect_identical(names(back), names(out))
  for (column in c("id", "label", "statistic", "unit", "estimand", "disclosure_status")) {
    expect_identical(back[[column]], out[[column]])
  }
  for (column in c("estimate", "se", "lower", "upper", "df", "confidence", "unweighted_n")) {
    expect_identical(as.double(back[[column]]), as.double(out[[column]]))
  }
  expect_true(all(is.infinite(back$df)))
  shown_values <- unlist(out[status == "shown", c("estimate", "se", "lower", "upper")])
  expect_true(any(as.numeric(sprintf("%.15g", shown_values)) != shown_values))
  lines <- readLines(path, encoding = "UTF-8")
  hidden_line <- lines[[which(out$id == "c1") + 1L]]
  expect_identical(hidden_line,
    "\"c1\",\"Rare <b>event</b>\",\"total\",\"weighted discharges\",\"single_year_total\",,,,,Inf,0.9,,\"suppressed_primary\"")
  expect_false(any(grepl("raw_missing|analysis_hospitals|weighted_denominator|included",
    lines[[1L]])))
})

test_that("HTML escapes text, records the policy and never shows hidden values", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session, df = 8)
  before <- review
  path <- tempfile(fileext = ".HTML")
  on.exit(unlink(path), add = TRUE)
  nis_export_table(review, path, "html", NULL, FALSE)
  expect_identical(review, before)
  html <- text_of(path)
  expect_match(html, "Rare &lt;b&gt;event&lt;/b&gt;", fixed = TRUE)
  expect_match(html, "All &quot;discharges&quot;, total", fixed = TRUE)
  expect_match(html, "Category B &amp; C&#39;s sibling", fixed = TRUE)
  expect_match(html, "Durée de séjour", fixed = TRUE)
  expect_match(html, "days &lt;script&gt;", fixed = TRUE)
  expect_false(grepl("<script", html, fixed = TRUE))
  expect_false(grepl("<b>", html, fixed = TRUE))
  expect_match(html, "Suppressed (primary)", fixed = TRUE)
  expect_match(html, "Suppressed (complementary)", fixed = TRUE)
  expect_match(html, "not analysis ready", fixed = TRUE)
  expect_match(html, "from 1 to 10 inclusive; zero counts: display; minimum contributing hospitals: 2; declared margins: 1.",
    fixed = TRUE)
  expect_match(html, "Values are exact.", fixed = TRUE)
  expect_match(html, "(90%)", fixed = TRUE)
  table <- review$table$data
  shown <- review$presentation$disclosure_status == "shown"
  hidden_values <- c(table$weighted_estimate[!shown], table$se[!shown],
    table$lower[!shown], table$upper[!shown])
  for (value in hidden_values) {
    for (digits in c(3, 6, 15)) {
      expect_false(grepl(formatC(value, digits = digits, format = "g"), html, fixed = TRUE))
    }
  }
  rows <- regmatches(html, gregexpr("<tr>.*?</tr>", html))[[1L]][-1L]
  expect_length(rows, nrow(table))
  for (i in which(!shown)) {
    cells <- regmatches(rows[[i]], gregexpr("<td>.*?</td>", rows[[i]]))[[1L]]
    expect_identical(cells[c(5:7, 9)], rep("<td>Suppressed</td>", 4))
  }
  for (i in which(shown)) {
    expect_match(rows[[i]], paste0("<td>", nis_test_exact(table$weighted_estimate[[i]]),
      "</td>"), fixed = TRUE)
  }
})

test_that("HTML rounds to significant digits without changing the review", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session, df = 8)
  before <- review
  path <- tempfile(fileext = ".html")
  on.exit(unlink(path), add = TRUE)
  nis_export_table(review, path, "html", 3, FALSE)
  expect_identical(review, before)
  html <- text_of(path)
  table <- review$table$data
  shown <- which(review$presentation$disclosure_status == "shown")
  for (i in shown) {
    expected <- sub("\\.$", "", formatC(signif(table$weighted_estimate[[i]], 3), digits = 3,
      format = "fg", flag = "#"))
    expect_match(html, paste0("<td>", expected, "</td>"), fixed = TRUE)
  }
  stay <- table$weighted_estimate[table$id == "stay"]
  expect_false(grepl(nis_test_exact(stay), html, fixed = TRUE))
  expect_match(html, "rounded to 3 significant digits", fixed = TRUE)
  n_all <- review$presentation$unweighted_n[review$presentation$id == "all"]
  expect_identical(n_all, 200)
  expect_match(html, "<td>200</td>", fixed = TRUE)
})

test_that("only unmodified disclosure reviews can be exported", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session)
  path <- tempfile(fileext = ".csv")
  expect_error(nis_export_table(review$table, path, "csv", NULL, FALSE),
    "Only a nis_disclosure_review")
  expect_error(nis_export_table(structure(list(), class = "nis_regression_table"), path,
    "csv", NULL, FALSE), "Regression tables have no disclosure review")
  expect_error(nis_export_table(review$presentation, path, "csv", NULL, FALSE),
    "unmodified nis_disclosure_review")
  revealed <- review
  hidden <- which(revealed$presentation$disclosure_status != "shown")[[1L]]
  revealed$presentation$estimate[[hidden]] <- revealed$table$data$weighted_estimate[[hidden]]
  expect_error(nis_export_table(revealed, path, "csv", NULL, FALSE), "unmodified")
  relabeled <- review
  relabeled$presentation$disclosure_status[[hidden]] <- "shown"
  expect_error(nis_export_table(relabeled, path, "csv", NULL, FALSE), "unmodified")
  changed <- review
  shown <- which(changed$presentation$disclosure_status == "shown")[[1L]]
  changed$presentation$estimate[[shown]] <- changed$presentation$estimate[[shown]] + 1e-9
  expect_error(nis_export_table(changed, path, "csv", NULL, FALSE), "unmodified")
  extra <- review
  extra$presentation$raw_missing <- 0
  expect_error(nis_export_table(extra, path, "csv", NULL, FALSE), "unmodified")
  attributed <- review
  attr(attributed$presentation, "audit") <- review$audit
  expect_error(nis_export_table(attributed, path, "csv", NULL, FALSE), "unmodified")
  count <- review
  count$presentation$unweighted_n[[shown]] <- count$presentation$unweighted_n[[shown]] - 1
  expect_error(nis_export_table(count, path, "csv", NULL, FALSE), "unmodified")
  expect_false(file.exists(path))
})

test_that("arguments and file handling are explicit", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session)
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  expect_error(nis_export_table(review, path, "csv", NULL), "explicitly")
  expect_error(nis_export_table(review, path, "docx", NULL, FALSE), "`format`")
  expect_error(nis_export_table(review, path, c("csv", "html"), NULL, FALSE), "`format`")
  expect_error(nis_export_table(review, sub("csv$", "html", path), "csv", NULL, FALSE),
    "ending in .csv")
  expect_error(nis_export_table(review, c(path, path), "csv", NULL, FALSE), "one file path")
  expect_error(nis_export_table(review, path, "csv", 3, FALSE), "NULL for CSV")
  html <- sub("csv$", "html", path)
  for (digits in list(0, 16, 2.5, "3", NA_real_, c(2, 3))) {
    expect_error(nis_export_table(review, html, "html", digits, FALSE), "`digits`")
  }
  expect_error(nis_export_table(review, path, "csv", NULL, NA), "`overwrite`")
  expect_error(nis_export_table(review, file.path(tempfile(), "x.csv"), "csv", NULL, FALSE),
    "directory does not exist")
  expect_false(file.exists(path))
  writeLines("keep", path)
  expect_error(nis_export_table(review, path, "csv", NULL, FALSE), "overwrite = TRUE")
  expect_identical(readLines(path), "keep")
  nis_export_table(review, path, "csv", NULL, TRUE)
  expect_identical(utils::read.csv(path)$id, review$presentation$id)
  expect_identical(list.files(dirname(path), pattern = "^easyNIS-export-"), character())
})
