export_n <- 200L

# Independent exact decimal form: whole numbers in full, others with 17 digits.
nis_test_exact <- function(x) {
  if (x == trunc(x)) format(x, scientific = FALSE) else sprintf("%.17g", x)
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

export_review <- function(session, df = Inf, confidence = 0.9) {
  path <- write_invented_parquet(session, export_rows())
  on.exit(unlink(path))
  design <- nis_survey_design(nis_import(session, path, 2022), unique(export_spec$field),
    TRUE, "hospital_wr", "fail")
  table <- nis_descriptive_table(design, export_spec, "exclude", df, confidence, "wr_unadjusted")
  nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all", parts = c("cat_a", "cat_b", "cat_c"))))
}

escape_test <- function(x) gsub(">", "&gt;", gsub("<", "&lt;", x, fixed = TRUE), fixed = TRUE)

text_of <- function(path) paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")

test_that("HTML retains exact confidence levels when every row is suppressed", {
  session <- nis_open()
  on.exit(nis_close(session))
  path <- write_invented_parquet(session, export_rows())
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022), "c1", TRUE,
    "hospital_wr", "fail")
  output <- tempfile(fileext = ".html")
  on.exit(unlink(output), add = TRUE)
  # Avoid decimal-literal parsing differences at the upper boundary on macOS.
  near_one <- 1 - .Machine$double.eps / 2
  expect_lt(near_one, 1)
  for (confidence in c(0.9, 0.9123456789012345, near_one)) {
    table <- nis_descriptive_table(design, export_spec[1L, ], "exclude", Inf,
      confidence, "wr_unadjusted")
    review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
    expect_identical(review$presentation$disclosure_status, "suppressed_primary")
    for (digits in list(NULL, 3)) {
      nis_export_table(review, output, "html", digits, NULL, TRUE)
      html <- text_of(output)
      expect_match(html, "<th>Confidence level (0 to 1)</th>", fixed = TRUE)
      expect_match(html, paste0("<td>", sprintf("%.17g", confidence), "</td>"),
        fixed = TRUE)
      expect_false(grepl("(100%)", html, fixed = TRUE))
      expect_match(html, "Larger combinations of declared margins remain unchecked",
        fixed = TRUE)
    }
  }
})

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
  returned <- nis_export_table(review, path, "csv", NULL, "keep", FALSE)
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
    "\"c1\",\"Rare <b>event</b>\",\"total\",\"weighted discharges\",\"single_year_total\",,,,,Inf,0.90000000000000002,,\"suppressed_primary\"")
  expect_false(any(grepl("raw_missing|analysis_hospitals|weighted_denominator|included",
    lines[[1L]])))
})

test_that("CSV text that a spreadsheet could run as a formula needs an explicit policy", {
  session <- nis_open()
  on.exit(nis_close(session))
  path <- write_invented_parquet(session, export_rows())
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022), c("all", "stay"), TRUE,
    "hospital_wr", "fail")
  # Rows after "cr" also cover a line feed and full-width = + - @.
  wide <- "\uff20wide"
  spec <- data.frame(id = c("@all", "stay", "plain", "tab", "cr", "lf", wide, "plus"),
    field = c("all", rep("stay", 7)),
    statistic = c("total", rep("mean", 7)),
    label = c("=1+1", "+cmd|' /C calc'!A0", "Stay - days", "\tTabbed", "\rReturned",
      "\n=1+1", "\uff1d1+1", "\uff0bplus"),
    unit = c("weighted discharges", "-days", "days", "days", "days", "days",
      "\uff0ddays", "days"),
    stringsAsFactors = FALSE)
  table <- nis_descriptive_table(design, spec, "fail", Inf, 0.95, "wr_unadjusted")
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  expect_true(all(review$presentation$disclosure_status == "shown"))
  before <- review
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(output), add = TRUE)

  refused <- tryCatch(nis_export_table(review, output, "csv", NULL, "refuse", FALSE),
    error = conditionMessage)
  cells <- paste0(c("id", "id", rep("label", 7), "unit", "unit"), " in row '",
    c("@all", wide, "@all", "stay", "tab", "cr", "lf", wide, "plus", "stay", wide), "'")
  expect_identical(enc2utf8(refused), enc2utf8(paste0(
    "CSV text cells begin with a character that spreadsheets can run as a formula ",
    "(=, +, -, @, their full-width forms, tab, carriage return or line feed): ",
    paste(cells, collapse = ", "),
    ". Change the text or set `formula_text` to \"prefix\" or \"keep\".")))
  expect_false(file.exists(output))

  # utils::read.csv() splits a quoted carriage return, so compare file bytes.
  raw_text <- function() rawToChar(readBin(output, "raw", file.size(output)))
  starts <- function(text) {
    vapply(text, function(x) paste0("\"", x, "\""), character(1), USE.NAMES = FALSE)
  }
  nis_export_table(review, output, "csv", NULL, "prefix", FALSE)
  written <- raw_text()
  for (cell in c("'@all", "'=1+1", "'+cmd|' /C calc'!A0", "Stay - days", "'\tTabbed",
                 "'\rReturned", "'-days", "plain", "'\n=1+1", paste0("'", wide),
                 "'\uff1d1+1", "'\uff0bplus", "'\uff0ddays")) {
    expect_true(grepl(enc2utf8(starts(cell)), written, fixed = TRUE, useBytes = TRUE),
      info = cell)
  }
  expect_false(grepl("\"=1+1\"", written, fixed = TRUE))
  expect_false(grepl("\"\rReturned\"", written, fixed = TRUE))
  back <- utils::read.csv(output, encoding = "UTF-8", stringsAsFactors = FALSE)
  expect_identical(back$id[1:4], c("'@all", "stay", "plain", "tab"))
  expect_identical(back$label[1:4], c("'=1+1", "'+cmd|' /C calc'!A0", "Stay - days",
    "'\tTabbed"))
  expect_identical(as.double(back$estimate[1:4]),
    as.double(review$presentation$estimate[1:4]))

  nis_export_table(review, output, "csv", NULL, "keep", TRUE)
  written <- raw_text()
  for (cell in c("@all", "=1+1", "+cmd|' /C calc'!A0", "\tTabbed", "\rReturned", "-days",
                 "\n=1+1", wide, "\uff1d1+1", "\uff0bplus", "\uff0ddays")) {
    expect_true(grepl(enc2utf8(starts(cell)), written, fixed = TRUE, useBytes = TRUE),
      info = cell)
  }
  expect_false(grepl("\"'", written, fixed = TRUE))
  expect_identical(review, before)

  html <- sub("csv$", "html", output)
  on.exit(unlink(html), add = TRUE)
  expect_error(nis_export_table(review, html, "html", NULL, "prefix", FALSE),
    "`formula_text` must be NULL for HTML")
  nis_export_table(review, html, "html", NULL, NULL, FALSE)
  expect_match(text_of(html), "<td>=1+1</td>", fixed = TRUE)
})

test_that("HTML escapes text, records the policy and never shows hidden values", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session, df = 8)
  before <- review
  path <- tempfile(fileext = ".HTML")
  on.exit(unlink(path), add = TRUE)
  nis_export_table(review, path, "html", NULL, NULL, FALSE)
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
  expect_match(html, "<td>0.90000000000000002</td>", fixed = TRUE)
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
    cells <- regmatches(rows[[i]], gregexpr("<td>.*?</td>", rows[[i]]))[[1L]]
    expect_identical(cells[2:7], paste0("<td>", c(table$statistic[[i]],
      escape_test(table$unit[[i]]), table$estimand[[i]],
      nis_test_exact(table$weighted_estimate[[i]]), nis_test_exact(table$se[[i]]),
      paste0(nis_test_exact(table$lower[[i]]), " to ", nis_test_exact(table$upper[[i]]))), "</td>"))
  }
})

test_that("HTML rounds to significant digits without changing the review", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session, df = 8)
  before <- review
  path <- tempfile(fileext = ".html")
  on.exit(unlink(path), add = TRUE)
  nis_export_table(review, path, "html", 3, NULL, FALSE)
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
  expect_error(nis_export_table(review$table, path, "csv", NULL, "keep", FALSE),
    "Only a nis_disclosure_review")
  expect_error(nis_export_table(structure(list(), class = "nis_regression_table"), path,
    "csv", NULL, "keep", FALSE), "Regression tables have no disclosure review")
  expect_error(nis_export_table(review$presentation, path, "csv", NULL, "keep", FALSE),
    "unmodified nis_disclosure_review")
  revealed <- review
  hidden <- which(revealed$presentation$disclosure_status != "shown")[[1L]]
  revealed$presentation$estimate[[hidden]] <- revealed$table$data$weighted_estimate[[hidden]]
  expect_error(nis_export_table(revealed, path, "csv", NULL, "keep", FALSE), "unmodified")
  relabeled <- review
  relabeled$presentation$disclosure_status[[hidden]] <- "shown"
  expect_error(nis_export_table(relabeled, path, "csv", NULL, "keep", FALSE), "unmodified")
  changed <- review
  shown <- which(changed$presentation$disclosure_status == "shown")[[1L]]
  changed$presentation$estimate[[shown]] <- changed$presentation$estimate[[shown]] + 1e-9
  expect_error(nis_export_table(changed, path, "csv", NULL, "keep", FALSE), "unmodified")
  extra <- review
  extra$presentation$raw_missing <- 0
  expect_error(nis_export_table(extra, path, "csv", NULL, "keep", FALSE), "unmodified")
  attributed <- review
  attr(attributed$presentation, "audit") <- review$audit
  expect_error(nis_export_table(attributed, path, "csv", NULL, "keep", FALSE), "unmodified")
  count <- review
  count$presentation$unweighted_n[[shown]] <- count$presentation$unweighted_n[[shown]] - 1
  expect_error(nis_export_table(count, path, "csv", NULL, "keep", FALSE), "unmodified")
  hidden_row <- function(x, i) {
    x$presentation$disclosure_status[[i]] <- "shown"
    x$audit$disclosure_status[[i]] <- "shown"
    for (column in c("estimate", "se", "lower", "upper")) {
      x$presentation[[column]][[i]] <- x$table$data[[if (column == "estimate")
        "weighted_estimate" else column]][[i]]
    }
    x$presentation$unweighted_n[[i]] <- x$audit$included[[i]]
    x
  }
  expect_error(nis_export_table(hidden_row(review, hidden), path, "csv", NULL, "keep", FALSE),
    "unmodified")
  forged_policy <- review
  forged_policy$provenance$policy <- list(suppress = c(1, 3), zero = "display",
    min_hospitals = 1, margins = list())
  expect_error(nis_export_table(forged_policy, path, "csv", NULL, "keep", FALSE), "unmodified")
  forged_count <- review
  forged_count$audit$included[[shown]] <- forged_count$audit$included[[shown]] + 1
  forged_count$presentation$unweighted_n[[shown]] <- forged_count$audit$included[[shown]]
  expect_error(nis_export_table(forged_count, path, "csv", NULL, "keep", FALSE), "unmodified")
  forged_estimate <- review
  forged_estimate$table$data$weighted_estimate[[shown]] <- 1
  forged_estimate$presentation$estimate[[shown]] <- 1
  expect_error(nis_export_table(forged_estimate, path, "csv", NULL, "keep", FALSE), "unmodified")
  factor_status <- review
  factor_status$presentation$disclosure_status <- factor(review$presentation$disclosure_status)
  factor_status$audit$disclosure_status <- factor_status$presentation$disclosure_status
  expect_error(nis_export_table(factor_status, path, "csv", NULL, "keep", FALSE), "unmodified")
  expect_false(file.exists(path))
})

test_that("arguments and file handling are explicit", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session)
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  expect_error(nis_export_table(review, path, "csv", NULL, "keep"), "explicitly")
  expect_error(nis_export_table(review, path, "pdf", NULL, "keep", FALSE), "`format`")
  expect_error(nis_export_table(review, path, c("csv", "html"), NULL, "keep", FALSE), "`format`")
  expect_error(nis_export_table(review, sub("csv$", "html", path), "csv", NULL, "keep", FALSE),
    "ending in .csv")
  expect_error(nis_export_table(review, c(path, path), "csv", NULL, "keep", FALSE), "one file path")
  expect_error(nis_export_table(review, path, "csv", 3, "keep", FALSE), "NULL for CSV")
  html <- sub("csv$", "html", path)
  for (digits in list(0, 16, 2.5, "3", NA_real_, c(2, 3))) {
    expect_error(nis_export_table(review, html, "html", digits, NULL, FALSE), "`digits`")
  }
  for (formula_text in list(NULL, "Keep", NA_character_, c("keep", "prefix"), TRUE)) {
    expect_error(nis_export_table(review, path, "csv", NULL, formula_text, FALSE),
      "`formula_text` must be \"refuse\", \"prefix\" or \"keep\" for CSV")
  }
  expect_error(nis_export_table(review, path, "csv", NULL, "keep", NA), "`overwrite`")
  expect_error(nis_export_table(review, file.path(tempfile(), "x.csv"), "csv", NULL, "keep", FALSE),
    "directory does not exist")
  expect_false(file.exists(path))
  writeLines("keep", path)
  expect_error(nis_export_table(review, path, "csv", NULL, "keep", FALSE), "overwrite = TRUE")
  expect_identical(readLines(path), "keep")
  nis_export_table(review, path, "csv", NULL, "keep", TRUE)
  expect_identical(utils::read.csv(path)$id, review$presentation$id)
  expect_identical(list.files(dirname(path), pattern = "^easyNIS-export-"), character())
})

html_cells <- function(path) {
  html <- text_of(path)
  unescape <- function(x) {
    for (pair in list(c("&lt;", "<"), c("&gt;", ">"), c("&quot;", "\""), c("&#39;", "'"),
                      c("&amp;", "&"))) {
      x <- gsub(pair[[1L]], pair[[2L]], x, fixed = TRUE)
    }
    x
  }
  cell_text <- function(row, tag) {
    unescape(gsub(paste0("</?", tag, ">"), "",
      regmatches(row, gregexpr(paste0("<", tag, ">.*?</", tag, ">"), row))[[1L]]))
  }
  rows <- regmatches(html, gregexpr("<tr>.*?</tr>", html))[[1L]]
  notes <- regmatches(html, gregexpr("<li>.*?</li>", html))[[1L]]
  list(header = cell_text(rows[[1L]], "th"),
    cells = lapply(rows[-1L], cell_text, tag = "td"),
    notes = unescape(gsub("</?li>", "", notes)))
}

docx_cells <- function(path) {
  summary <- officer::docx_summary(officer::read_docx(path))
  table <- summary[summary$content_type == "table cell", ]
  table <- table[order(table$row_id, table$cell_id), ]
  rows <- split(table$text, table$row_id)
  paragraphs <- summary$text[summary$content_type == "paragraph" & nzchar(summary$text)]
  list(header = rows[[1L]], cells = unname(rows[-1L]), paragraphs = paragraphs)
}

# Every XML part of the document, and the unescaped text of every w:t node in them.
docx_xml <- function(path) {
  directory <- tempfile("docx-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  parts <- utils::unzip(path, exdir = directory)
  parts <- parts[grepl("[.](xml|rels)$", parts)]
  xml <- vapply(parts, function(part) {
    paste(readLines(part, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  }, character(1), USE.NAMES = FALSE)
  names(xml) <- basename(parts)
  text <- unlist(lapply(xml, function(x) {
    nodes <- regmatches(x, gregexpr("<w:t(?: [^>]*)?>[^<]*</w:t>", x, perl = TRUE))[[1L]]
    nodes <- sub("^<w:t[^>]*>", "", sub("</w:t>$", "", nodes))
    for (pair in list(c("&lt;", "<"), c("&gt;", ">"), c("&quot;", "\""), c("&apos;", "'"),
                      c("&amp;", "&"))) {
      nodes <- gsub(pair[[1L]], pair[[2L]], nodes, fixed = TRUE)
    }
    nodes
  }), use.names = FALSE)
  list(xml = xml, text = text)
}

test_that("Word contains the HTML cells and notes and no hidden value", {
  session <- nis_open()
  on.exit(nis_close(session))
  review <- export_review(session, df = 8)
  before <- review
  html <- tempfile(fileext = ".html")
  docx <- tempfile(fileext = ".DOCX")
  on.exit(unlink(c(html, docx)), add = TRUE)
  for (digits in list(NULL, 3)) {
    nis_export_table(review, html, "html", digits, NULL, TRUE)
    returned <- nis_export_table(review, docx, "docx", digits, NULL, TRUE)
    expect_identical(returned, normalizePath(docx))
    expect_identical(review, before)
    expected <- html_cells(html)
    word <- docx_cells(docx)
    expect_identical(word$header, expected$header)
    expect_length(word$cells, nrow(review$presentation))
    expect_identical(word$cells, expected$cells)
    expect_identical(word$paragraphs,
      c("easyNIS experimental descriptive table", expected$notes))
  }
  expect_identical(word$cells[[which(review$presentation$id == "cat_c")]][[1L]], "Category\nC")
  expect_identical(word$cells[[which(review$presentation$id == "c1")]][c(1L, 5:7, 9:10)],
    c("Rare <b>event</b>", rep("Suppressed", 4), "Suppressed (primary)"))
  expect_true(any(grepl("rounded to 3 significant digits", word$paragraphs, fixed = TRUE)))

  table <- review$table$data
  shown <- review$presentation$disclosure_status == "shown"
  hidden <- c(table$weighted_estimate[!shown], table$se[!shown], table$lower[!shown],
    table$upper[!shown])
  expect_true(length(hidden) > 0L)
  for (digits in list(NULL, 3, 15)) {
    nis_export_table(review, html, "html", digits, NULL, TRUE)
    nis_export_table(review, docx, "docx", digits, NULL, TRUE)
    expected <- html_cells(html)
    document <- docx_xml(docx)
    # Every text node in every part is a caption, header, cell or note string.
    expect_true(all(document$text %in% c("easyNIS experimental descriptive table",
      expected$header, unlist(expected$cells), expected$notes)))
    tokens <- unlist(strsplit(document$text, "\\s+"))
    for (value in hidden) {
      expect_false(nis_test_exact(value) %in% tokens, info = nis_test_exact(value))
    }
    body <- document$xml[["document.xml"]]
    expect_match(body, "w:orient=\"landscape\"", fixed = TRUE)
    expect_match(body, "Rare &lt;b&gt;event&lt;/b&gt;", fixed = TRUE)
    expect_false(grepl("<b>event", body, fixed = TRUE))
    # No row may split across pages.
    expect_identical(lengths(gregexpr("<w:cantSplit/>", body, fixed = TRUE)),
      nrow(review$presentation) + 1L)
    expect_identical(lengths(gregexpr("<w:tr>|<w:tr ", body)), nrow(review$presentation) + 1L)
  }
})

test_that("Word export needs officer and text that a Word document can hold", {
  session <- nis_open()
  on.exit(nis_close(session))
  path <- write_invented_parquet(session, export_rows())
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022), "stay", TRUE,
    "hospital_wr", "fail")
  spec <- data.frame(id = c("bell", "plain", "space", "fffe", "ffff"), field = "stay",
    statistic = "mean", label = c("Stay\a", "Tab\there\r\nand line", "Stay", "Stay",
      "Stay￿"),
    unit = c("days", "days", "days\v", "days￾", "days"), stringsAsFactors = FALSE)
  table <- nis_descriptive_table(design, spec, "fail", Inf, 0.95, "wr_unadjusted")
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  output <- tempfile(fileext = ".docx")
  on.exit(unlink(output), add = TRUE)

  expect_identical(
    tryCatch(nis_export_table(review, output, "docx", NULL, NULL, FALSE),
      error = conditionMessage),
    paste0("Word documents cannot contain control characters other than tab, ",
      "carriage return and line feed, or U+FFFE and U+FFFF: label in row 'bell', ",
      "label in row 'ffff', unit in row 'space', unit in row 'fffe'."))
  expect_false(file.exists(output))
  html <- sub("docx$", "html", output)
  on.exit(unlink(html), add = TRUE)
  nis_export_table(review, html, "html", NULL, NULL, FALSE)
  expect_true(file.exists(html))

  plain <- nis_descriptive_table(design, spec[2L, ], "fail", Inf, 0.95, "wr_unadjusted")
  plain <- nis_disclosure_review(plain, c(1, 10), "display", 2, list())
  nis_export_table(plain, output, "docx", NULL, NULL, FALSE)
  # officer writes a carriage return and line feed as one line feed.
  expect_identical(docx_cells(output)$cells[[1L]][[1L]], "Tab\there\nand line")

  expect_error(nis_export_table(plain, output, "docx", NULL, "keep", TRUE),
    "`formula_text` must be NULL for HTML and Word")
  for (digits in list(0, 16, 2.5)) {
    expect_error(nis_export_table(plain, output, "docx", digits, NULL, TRUE), "`digits`")
  }
  expect_error(nis_export_table(plain, sub("docx$", "html", output), "docx", NULL, NULL,
    TRUE), "ending in .docx")
  expect_error(nis_export_table(plain, output, "docx", NULL, NULL, FALSE), "overwrite = TRUE")

  unlink(output)
  local_mocked_bindings(officer_available = function() FALSE)
  expect_error(nis_export_table(plain, output, "docx", NULL, NULL, FALSE),
    "Word export needs the optional officer package, version 0.5.0 or later. Install it with install.packages(\"officer\"), or export CSV or HTML.",
    fixed = TRUE)
  expect_false(file.exists(output))
  expect_identical(list.files(dirname(output), pattern = "^easyNIS-export-"), character())
})
