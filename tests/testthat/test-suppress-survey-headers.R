survey_header_fixture <- function(sizes, one_hospital = character()) {
  data <- data.frame(
    group = rep(c("Rare", "Mid", "Common"), sizes),
    age = seq_len(sum(sizes)),
    YEAR = 2020L,
    HOSP_NIS = rep(1:2, length.out = sum(sizes)),
    weight = rep(c(17, 23, 29), sizes)
  )
  data$HOSP_NIS[data$group %in% one_hospital] <- 1L
  design <- survey::svydesign(ids = ~1, weights = ~weight, data = data)
  gtsummary::tbl_svysummary(
    design,
    by = group,
    include = age,
    type = age ~ "continuous",
    statistic = age ~ "{mean}"
  )
}

test_that("protected survey group headers stay masked through exports", {
  table <- survey_header_fixture(c(9, 14, 18))
  original <- names(tibble::as_tibble(table))
  safe <- nis_suppress(table)
  exported <- tibble::as_tibble(safe)
  expect_match(names(exported)[4], "Rare.*Masked")
  expect_identical(names(exported)[1:3], original[1:3])
  expect_identical(exported[[4]], "\u226410")

  csv <- tempfile(fileext = ".csv")
  utils::write.csv(exported, csv, row.names = FALSE)
  expect_identical(names(utils::read.csv(csv, check.names = FALSE)), names(exported))

  html <- gt::as_raw_html(gtsummary::as_gt(safe))
  expect_match(html, "Rare[^<]*</[^>]+>.*Masked")
  expect_no_match(html, "N = 153", fixed = TRUE)

  word <- tempfile(fileext = ".docx")
  flextable::save_as_docx(gtsummary::as_flex_table(safe), path = word)
  document <- paste(readLines(unz(word, "word/document.xml"), warn = FALSE), collapse = " ")
  expect_match(document, ">Rare<")
  expect_match(document, ">N = Masked<")
  expect_no_match(document, "N = 153", fixed = TRUE)
})

test_that("formatted overall and spanning totals cannot reveal a protected group", {
  table <- survey_header_fixture(c(9, 14, 18)) |>
    gtsummary::add_overall(col_label = "**Overall**  \nTotal N = {N}; sampled N = {N_unweighted}") |>
    gtsummary::modify_header(
      stat_3 ~ "**{level}**  \nSampled = {n_unweighted}; weighted = {n}",
      stat_1 ~ "**{level}**  \nTotal N = {N}; sampled N = {N_unweighted}",
      label ~ "Records: {as.roman(N_unweighted)}"
    ) |>
    gtsummary::modify_spanning_header(
      c(stat_1, stat_2) ~ "Population = {N}; sampled = {N_unweighted}"
    ) |>
    gtsummary::modify_spanning_header(stat_3 ~ "Weighted = {n}; sampled = {n_unweighted}", level = 2)

  safe <- nis_suppress(table)
  headers <- paste(names(tibble::as_tibble(safe)), collapse = " ")
  expect_match(headers, "Overall.*Masked")
  expect_match(headers, "Rare.*Masked")
  expect_no_match(headers, "997|153|Records: XLI|sampled.*41|[Ss]ampled = 9")
  html <- gt::as_raw_html(gtsummary::as_gt(safe))
  expect_no_match(html, "Population = 997|Weighted = 153|Total N = 997|Sampled = 9")

  word <- tempfile(fileext = ".docx")
  flextable::save_as_docx(gtsummary::as_flex_table(safe), path = word)
  document <- paste(readLines(unz(word, "word/document.xml"), warn = FALSE), collapse = " ")
  expect_no_match(document, "Population = 997|Weighted = 153|Total N = 997|Sampled = 9")
})

test_that("group header masks use both discharge and hospital support", {
  table <- survey_header_fixture(c(9, 14, 18), one_hospital = "Common")
  original <- names(tibble::as_tibble(table))
  safe <- nis_suppress(table)
  headers <- names(tibble::as_tibble(safe))
  expect_match(headers[2], "Common.*Masked")
  expect_identical(headers[3], original[3])
  expect_match(headers[4], "Rare.*Masked")

  data <- data.frame(age = 1:14, YEAR = 2020L, HOSP_NIS = 1L, weight = 17)
  design <- survey::svydesign(ids = ~1, weights = ~weight, data = data)
  table <- gtsummary::tbl_svysummary(design, include = age, type = age ~ "continuous")
  expect_match(names(tibble::as_tibble(nis_suppress(table)))[2], "Masked")
})
