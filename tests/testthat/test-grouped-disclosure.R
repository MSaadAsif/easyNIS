grouped_disclosure_rows <- function(n = 100L) {
  rows <- nis_synthetic_data()$core[rep(1L, 2L * n), ]
  rows$KEY_NIS <- sprintf("%06d", seq_len(2L * n))
  rows$HOSP_NIS <- sprintf("%04d", (seq_len(2L * n) - 1L) %% 10L + 1L)
  rows$NIS_STRATUM <- rep(rep(1:2, each = 5L), length.out = 2L * n)
  rows$DISCWT <- 5
  rows$group_source <- rep(c("one", "two"), each = n)
  rows$T <- 1L
  rows
}

grouped_disclosure_table <- function(session, rows, fields, statistic = "total",
                                     id = fields, parent = FALSE) {
  path <- write_invented_parquet(session, rows)
  on.exit(unlink(path))
  design <- nis_survey_design(nis_import(session, path, 2022),
    unique(c(fields, "group_source", if (parent) "parent")), TRUE, "hospital_wr", "fail")
  design <- nis_factor(design, "group_source", "group `field", c("one", "two", "unused"),
    c("one'`\\ | d1.f1", "two", "unused"))
  if (parent) design <- nis_domain(design, "parent", "fail")
  spec <- data.frame(id = id, field = fields, statistic = statistic,
    label = paste("Invented", id), unit = ifelse(statistic == "proportion", "proportion", "count"))
  nis_descriptive_table(design, spec, "exclude", 8, 0.95, "wr_unadjusted",
    by = "group `field", group_missing = "exclude")
}

grouped_partition_rows <- function() {
  rows <- grouped_disclosure_rows()
  rows$a <- as.integer(c(1:100 <= 40, 1:100 <= 45))
  rows$b <- as.integer(c(1:100 > 40, 1:100 > 45 & 1:100 <= 97))
  rows$c <- as.integer(c(rep(FALSE, 100), 1:100 > 97))
  rows
}

test_that("joint grouped review keeps independent partitions and repeated statistics distinct", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_partition_rows()
  expect_true(all(rows$a + rows$b + rows$c == rows$T))
  expect_identical(vapply(split(rows[c("T", "a", "b", "c")], rows$group_source),
    function(x) as.double(colSums(x)), numeric(4)),
    matrix(c(100, 40, 60, 0, 100, 45, 52, 3), 4, dimnames = list(NULL, c("one", "two"))))
  table <- grouped_disclosure_table(session, rows, c("T", "a", "b", "c", "a", "c"),
    c(rep("total", 4), "proportion", "proportion"), c("T", "a", "b", "c", "ap", "cp"))
  before <- table
  margins <- list(list(total = "g1.T", parts = c("g1.a", "g1.b")),
    list(total = "g2.T", parts = c("g2.a", "g2.b", "g2.c")))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_identical(table, before)
  expect_identical(review$presentation$disclosure_status,
    c(rep("shown", 6), "shown", "suppressed_complementary", "shown",
      "suppressed_primary", "suppressed_complementary", "suppressed_primary"))
  expect_identical(review$audit$field, rep(c("T", "a", "b", "c", "a", "c"), 2))
  expect_identical(review$audit$count_identity,
    c("d1.f1", "d1.f2", "d1.f3", "d1.f4", "d1.f2", "d1.f4",
      "d2.f1", "d2.f2", "d2.f3", "d2.f4", "d2.f2", "d2.f4"))
  # After publication the only hidden equation is a2+c2 = T2-b2.
  # Both (45,3) and (44,4) satisfy it: neither hidden count is determined.
  expect_equal(c(45 + 3, 44 + 4), rep(100 - 52, 2))
  zero <- nis_disclosure_review(table, c(1, 10), "suppress", 2, margins)
  expect_identical(zero$presentation$disclosure_status[c(4, 6)], rep("suppressed_primary", 2))
  bad <- c(margins, list(list(total = "g1.a", parts = c("g1.ap", "g1.c"))))
  expect_error(nis_disclosure_review(table, c(1, 10), "suppress", 2, bad),
    "declarations alone determine")
})

test_that("cross-group primary pairs protect a recoverable small sum", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_disclosure_rows(300)
  rows$a <- as.integer(c(1:300 <= 3, 1:300 <= 4))
  rows$b <- as.integer(c(1:300 > 3 & 1:300 <= 100, 1:300 > 4 & 1:300 <= 100))
  rows$c <- as.integer(rep(1:300 > 100, 2))
  rows$s <- as.integer(c(1:300 <= 193, 1:300 <= 50))
  table <- grouped_disclosure_table(session, rows, c("T", "a", "b", "c", "s"))
  margins <- list(list(total = "g1.T", parts = c("g1.a", "g1.b", "g1.c")),
    list(total = "g2.T", parts = c("g2.a", "g2.b", "g2.c")),
    list(total = "g1.s", parts = c("g1.b", "g2.b")))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_identical(review$presentation$disclosure_status,
    c("shown", "suppressed_primary", "suppressed_complementary", "shown",
      "suppressed_complementary", "shown", "suppressed_primary",
      "suppressed_complementary", "shown", "shown"))
  expect_match(review$audit$reasons[[5]], "margins_sum:pair:", fixed = TRUE)
  # Publishing s1 would recover a1+a2=7. Hiding it allows a1+a2=8 too.
  expect_equal(300 + 300 - 200 - 200 - 193, 7)
  expect_equal(c(3 + 97, 4 + 96, 4 + 96, 4 + 96), rep(100, 4))
  expect_identical(review, nis_disclosure_review(table, c(1, 10), "display", 2, margins))
})

test_that("group-specific binary scales, missingness and joint n differences remain checked", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_disclosure_rows()
  rows$x <- c(rep(c(0, 1), 50), rep(c(0, 2), 50))
  rows$y <- c(rep(c(0, 1), 50), rep(1, 100))
  rows[["d1.f1"]] <- rows$x
  rows$stay <- rep(2:6, 40)
  rows$stay[101:104] <- NA_real_
  rows$group_source[1] <- NA_character_
  rows$parent <- TRUE
  table <- grouped_disclosure_table(session, rows, c("x", "y", "d1.f1", "stay"), parent = TRUE)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  expect_identical(review$audit$binary[c(1, 5)], c(TRUE, FALSE))
  expect_identical(review$audit$margin_count[c(1, 5)], c(50, 100))
  expect_identical(review$audit$missing[c(4, 8)], c(0, 4))
  expect_identical(table$provenance$grouping$unknown, 1)
  expect_identical(review$audit$field[c(3, 7)], rep("d1.f1", 2))
  expect_false(review$audit$count_identity[[1]] == review$audit$count_identity[[3]])
  expect_error(nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "g2.x", parts = "g1.x"))), "does not equal")
  expect_identical(review$presentation$disclosure_status[[8]], "suppressed_primary")
  expect_true(any(grepl("n_difference:", review$audit$reasons, fixed = TRUE)))
})

test_that("nested grouped margins protect sums without suppressing a safe other group", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_disclosure_rows(200)
  rows$a <- as.integer(c(1:200 <= 3, 1:200 <= 20))
  rows$b <- as.integer(c(1:200 > 3 & 1:200 <= 7, 1:200 > 20 & 1:200 <= 50))
  rows$c <- as.integer(c(1:200 > 7 & 1:200 <= 37, 1:200 > 50 & 1:200 <= 80))
  rows$d <- as.integer(c(1:200 > 37 & 1:200 <= 67, 1:200 > 80 & 1:200 <= 120))
  rows$s <- rows$c + rows$d
  rows$e <- rows$T - rows$a - rows$b - rows$s
  fields <- c("T", "a", "b", "c", "d", "s", "e", "a")
  table <- grouped_disclosure_table(session, rows, fields,
    c(rep("total", 7), "proportion"), c("T", "a", "b", "c", "d", "s", "e", "ap"))
  margins <- unlist(lapply(1:2, function(g) {
    id <- function(x) paste0("g", g, ".", x)
    list(list(total = id("T"), parts = id(c("a", "b", "c", "d", "e"))),
      list(total = id("s"), parts = id(c("c", "d"))))
  }), recursive = FALSE)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, margins)
  expect_identical(review$presentation$disclosure_status[9:16], rep("shown", 8))
  expect_identical(review$presentation$disclosure_status[c(2, 8)], rep("suppressed_primary", 2))
  expect_identical(review$presentation$disclosure_status[[6]], "suppressed_complementary")
  expect_match(review$audit$reasons[[6]], "margins_sum:", fixed = TRUE)
  expect_equal(sum(rows$T[1:200] - rows$s[1:200] - rows$e[1:200]), 7)
})

test_that("protected cross-group hospitals use unions and preserve pooled year identities", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_disclosure_rows(300)
  rare <- 1:300 %in% seq(1, 51, 10)
  rows$a <- as.integer(rep(rare, 2))
  rows$b <- as.integer(rep(1:300 <= 100 & !rare, 2))
  rows$c <- as.integer(rep(1:300 > 100, 2))
  rows$s <- as.integer(c(1:300 <= 188, 1:300 <= 50))
  designs <- lapply(2021:2022, function(year) {
    annual <- rows
    annual$YEAR <- year
    path <- write_invented_parquet(session, annual)
    on.exit(unlink(path))
    design <- nis_survey_design(nis_import(session, path, year),
      c("T", "a", "b", "c", "s", "group_source"), TRUE, "hospital_wr", "fail")
    nis_factor(design, "group_source", "group", c("one", "two"), c("one", "two"))
  })
  fields <- c("T", "a", "b", "c", "s")
  pool <- nis_pool_design(designs, c(fields, "group"), "combined_total")
  spec <- data.frame(id = fields, field = fields, statistic = "total", label = fields, unit = "count")
  table <- nis_descriptive_table(pool, spec, "fail", 8, 0.95, "wr_unadjusted",
    by = "group", group_missing = "fail")
  margins <- list(list(total = "g1.T", parts = c("g1.a", "g1.b", "g1.c")),
    list(total = "g2.T", parts = c("g2.a", "g2.b", "g2.c")),
    list(total = "g1.s", parts = c("g1.b", "g2.b")))
  review <- nis_disclosure_review(table, c(1, 20), "display", 3, margins)
  expect_identical(review$audit$hospitals_nonzero[c(2, 7)], c(2, 2))
  expect_identical(review$audit$margin_count[c(2, 7)], c(12, 12))
  # The two groups share one hospital per year: their union has two, not four.
  hospitals <- lapply(table$results[c(2, 7)], function(x) {
    as.character(x$design$cluster[[1]][x$design$variables$a != 0])
  })
  expect_length(unique(unlist(hospitals)), 2)
  expect_identical(review$presentation$disclosure_status[[5]], "suppressed_complementary")
  expect_match(review$audit$reasons[[5]], "margins_sum:pair:", fixed = TRUE)
  less <- nis_disclosure_review(table, c(1, 20), "display", 2, margins)
  expect_identical(less$presentation$disclosure_status[[5]], "shown")
  expect_identical(review$presentation$disclosure_status[[10]], "shown")
})

test_that("inconsistent grouped provenance rejects the entire review", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- grouped_partition_rows()
  rows$parent <- TRUE
  table <- grouped_disclosure_table(session, rows, c("T", "a"), parent = TRUE)
  mutations <- list(
    function(x) { x$provenance$grouping$observed_levels <- c("one", "one"); x },
    function(x) { x$provenance$grouping$unused_levels <- "two"; x },
    function(x) { x$provenance$grouping$unknown <- -1; x },
    function(x) { x$results[[1]]$provenance$domains <- list(); x },
    function(x) { x$results[[1]]$provenance$domains[[1]]$missing <- "exclude"; x },
    function(x) { x$results[[1]]$provenance$domains[[2]]$fields <- "wrong"; x },
    function(x) { x$results[[1]]$provenance$domains[[2]]$included <- 99L; x },
    function(x) { x$results[[1]]$provenance$design <- list(); x },
    function(x) { x$results[[1]]$provenance$population <- list(); x },
    function(x) { x$results[[1]]$provenance$missing <- "fail"; x },
    function(x) { x$results[[3]]$provenance$domains <- x$results[[1]]$provenance$domains; x },
    function(x) { x$results[[1]]$design$variables[["group `field"]][1] <- "two"; x })
  for (change in mutations) {
    expect_error(nis_disclosure_review(change(table), c(1, 10), "display", 2, list()),
      "inconsistent grouping")
  }
})

test_that("one grouped review exports only shown presentation and defends caller text", {
  session <- nis_open()
  on.exit(nis_close(session))
  table <- grouped_disclosure_table(session, grouped_partition_rows(), c("T", "a", "b", "c"))
  table$data$label[[1]] <- "=formula <&>"
  review <- nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "g2.T", parts = c("g2.a", "g2.b", "g2.c"))))
  paths <- c(tempfile(fileext = ".csv"), tempfile(fileext = ".csv"),
    tempfile(fileext = ".html"), tempfile(fileext = ".html"), tempfile(fileext = ".docx"))
  on.exit(unlink(paths), add = TRUE)
  expect_error(nis_export_table(review, paths[[1]], "csv", NULL, "refuse", FALSE), "formula")
  expect_false(file.exists(paths[[1]]))
  for (path in paths[1:2]) nis_export_table(review, path, "csv", NULL, "prefix", FALSE)
  classes <- ifelse(vapply(review$presentation, is.numeric, logical(1)), "numeric", "character")
  csv <- utils::read.csv(paths[[1]], check.names = FALSE, colClasses = classes)
  expect_identical(names(csv), names(review$presentation))
  expect_length(csv, 13)
  expect_identical(csv$label[[1]], "'=formula <&>")
  hidden <- review$presentation$disclosure_status != "shown"
  for (column in c("estimate", "se", "lower", "upper", "unweighted_n")) {
    expect_true(all(is.na(csv[[column]][hidden])))
    expect_identical(csv[[column]][!hidden], review$presentation[[column]][!hidden])
  }
  for (path in paths[3:4]) nis_export_table(review, path, "html", NULL, NULL, FALSE)
  expect_identical(readBin(paths[[1]], "raw", file.info(paths[[1]])$size),
    readBin(paths[[2]], "raw", file.info(paths[[2]])$size))
  expect_identical(readLines(paths[[3]]), readLines(paths[[4]]))
  html <- xml2::read_html(paths[[3]])
  cells <- lapply(xml2::xml_find_all(html, "//tbody/tr"), function(row) {
    xml2::xml_text(xml2::xml_find_all(row, "td"))
  })
  expect_identical(cells[[1]][[1]], "=formula <&>")
  for (i in which(hidden)) expect_identical(cells[[i]][c(5:7, 9)], rep("Suppressed", 4))
  expect_false(any(grepl("count_identity|margin_count|group_source|predicate|.parquet",
    readLines(paths[[3]]))))
  if (requireNamespace("officer", quietly = TRUE) && utils::packageVersion("officer") >= "0.5.0") {
    nis_export_table(review, paths[[5]], "docx", NULL, NULL, FALSE)
    word <- officer::docx_summary(officer::read_docx(paths[[5]]))
    expect_identical(word$text[word$content_type == "table cell"],
      c(xml2::xml_text(xml2::xml_find_all(html, "//thead/tr/th")), unlist(cells, use.names = FALSE)))
  }
  changed <- review
  changed$audit$count_identity[[1]] <- "forged"
  expect_error(nis_export_table(changed, tempfile(fileext = ".csv"), "csv", NULL, "prefix", FALSE),
    "unmodified")
})
