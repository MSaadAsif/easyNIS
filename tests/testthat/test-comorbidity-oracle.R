test_that("the lazy ICD-10 SQL results agree with the medicalcoder scorer", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  map <- medicalcoder::get_elixhauser_codes()
  methods <- c("elixhauser_ahrq_icd10", paste0("elixhauser_ahrq", 2022:2026))
  codes <- unique(map$code[map[[methods[[1L]]]] %in% 1L])
  fixture <- expand.grid(
    I10_DX2 = codes,
    DXPOA2 = c("Y", "N", "U", "W", "1", "", NA),
    stringsAsFactors = FALSE
  ) |>
    dplyr::as_tibble() |>
    dplyr::mutate(
      KEY_NIS = dplyr::row_number(),
      I10_DX1 = "ZZZ99",
      DXPOA1 = "Y",
      I10_DX3 = dplyr::case_when(
        KEY_NIS %% 7L == 0L ~ "I69359",
        KEY_NIS %% 7L == 1L ~ "C7800",
        KEY_NIS %% 7L == 2L ~ "E119",
        KEY_NIS %% 7L == 3L ~ "I10",
        KEY_NIS %% 7L == 4L ~ "K7460",
        KEY_NIS %% 7L == 5L ~ "N186"
      ),
      DXPOA3 = "Y"
    )
  long <- rbind(
    data.frame(
      id = fixture$KEY_NIS,
      code = fixture$I10_DX2,
      poa = unname(c(Y = 1L, W = 1L, N = 0L, U = 0L)[fixture$DXPOA2])
    ),
    data.frame(id = fixture$KEY_NIS, code = fixture$I10_DX3, poa = 1L)
  )
  long <- long[!is.na(long$code), ]
  con <- DBI::dbConnect(duckdb::duckdb(), config = list(threads = 2L))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  query <- dplyr::copy_to(con, fixture, "discharges")

  for (method in methods) {
    expected <- medicalcoder::comorbidities(
      long,
      icd.codes = "code",
      id.vars = "id",
      icdv = 10L,
      dx = 1L,
      primarydx = 0L,
      poa.var = "poa",
      method = method
    )
    result <- nis_comorbidity(query, method, prefix = "")
    expect_s3_class(result, "tbl_sql")
    observed <- result |>
      dplyr::arrange(KEY_NIS) |>
      dplyr::collect()
    reference <- expected[match(observed$KEY_NIS, expected$id), ]
    fields <- setdiff(names(reference), c("id", "num_cmrb", "cmrb_flag", "mortality_index", "readmission_index"))
    for (field in fields) {
      expect_identical(observed[[tolower(field)]], reference[[field]] == 1L, info = paste(method, field))
    }
    expect_identical(observed$n, reference$num_cmrb, info = method)
    expect_identical(observed$any, reference$cmrb_flag == 1L, info = method)
    expect_identical(observed$mortality_index, reference$mortality_index, info = method)
    expect_identical(observed$readmission_index, reference$readmission_index, info = method)
  }
})
test_that("Charlson methods choose the codes and weights by discharge era", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  fixture <- data.frame(
    YEAR = c(2014L, 2015L, 2015L, 2016L),
    DQTR = c(1L, 3L, 4L, 1L),
    DX1 = "00000",
    DX2 = "042",
    I10_DX1 = "ZZZ99",
    I10_DX2 = "B20",
    DXPOA1 = "Y",
    DXPOA2 = "Y"
  )
  original <- nis_comorbidity(fixture, "charlson_quan2005")
  updated <- nis_comorbidity(fixture, "charlson_quan2011")
  expect_identical(original$cmrb_cci, rep(6L, 4L))
  expect_identical(updated$cmrb_cci, rep(4L, 4L))
  expect_warning(deyo <- nis_comorbidity(fixture, "charlson_deyo1992"), "2 rows")
  expect_identical(deyo$cmrb_cci, c(6L, 6L, NA_integer_, NA_integer_))

  fixture$DX2 <- "4280"
  fixture$I10_DX2 <- "I509"
  expect_identical(nis_comorbidity(fixture, "charlson_quan2005")$cmrb_cci, rep(1L, 4L))
  expect_identical(nis_comorbidity(fixture, "charlson_quan2011")$cmrb_cci, rep(2L, 4L))
})
test_that("AHRQ FY2027 uses its published measures, hierarchies and weights", {
  input <- data.frame(
    I10_DX1 = "ZZZ99",
    I10_DX2 = c("C78.31", "F0670", "D6911", "D6911", "Z6818", "C7832"),
    I10_DX3 = c(NA, NA, NA, NA, NA, "C9200"),
    DXPOA1 = "Y",
    DXPOA2 = c("N", "Y", "W", "1", "N", "Y"),
    DXPOA3 = "Y",
    YEAR = c(2027L, 2027L, 2027L, 2027L, 2027L, 2027L)
  )
  out <- nis_comorbidity(input, "elixhauser_ahrq2027")
  expect_identical(out$cmrb_n, c(1L, 0L, 1L, 0L, 1L, 2L))
  expect_identical(out$cmrb_mortality_index, c(22L, 0L, 14L, 0L, 13L, 31L))
  expect_identical(out$cmrb_readmission_index, c(11L, 0L, 3L, 0L, 6L, 21L))

  input$YEAR[5L] <- 2026L
  input$DQTR <- 3L
  expect_false(nis_comorbidity(input, "elixhauser_ahrq2027")$cmrb_wghtloss[5L])
})

test_that("bundled AHRQ FY2027 scores work without medicalcoder", {
  input <- data.frame(
    I10_DX1 = "ZZZ99",
    I10_DX2 = "C78.31",
    DXPOA1 = "Y",
    DXPOA2 = "N",
    YEAR = 2027L
  )
  detect_installed <- getFromNamespace("detect_installed", "rlang")
  local_mocked_bindings(
    detect_installed = function(info) detect_installed(info) & info$pkg != "medicalcoder",
    .package = "rlang"
  )
  expect_identical(nis_comorbidity(input, "elixhauser_ahrq2027")$cmrb_mortality_index, 22L)
  methods <- c("elixhauser_ahrq_icd10", "elixhauser_ahrq2026", "charlson_quan2005", "elixhauser_quan2005")
  for (method in methods) {
    expect_error(nis_comorbidity(input, method), "medicalcoder.*required", class = "rlib_error_package_not_found")
  }
})

test_that("Charlson and legacy Elixhauser agree with the ICD-9 and ICD-10 reference", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  methods <- list(
    charlson_quan2005 = c(9L, 10L),
    charlson_quan2011 = c(9L, 10L),
    charlson_deyo1992 = 9L,
    elixhauser_quan2005 = c(9L, 10L),
    elixhauser_ahrq_web = 9L,
    elixhauser_elixhauser1998 = 9L
  )
  for (method in names(methods)) {
    charlson <- startsWith(method, "charlson")
    map <- if (charlson) medicalcoder::get_charlson_codes() else medicalcoder::get_elixhauser_codes()
    cases <- unique(map[map[[method]] %in% 1L & map$icdv %in% methods[[method]], c("icdv", "dx", "code")])
    n <- nrow(cases)
    fixture <- data.frame(
      YEAR = ifelse(cases$icdv == 9L, 2014L, 2016L),
      DX1 = if (9L %in% methods[[method]]) "00000" else NA_character_,
      DX2 = ifelse(cases$icdv == 9L & cases$dx == 1L, cases$code, NA_character_),
      I10_DX1 = "ZZZ99",
      I10_DX2 = ifelse(cases$icdv == 10L, cases$code, NA_character_),
      PR1 = ifelse(cases$dx == 0L, cases$code, NA_character_),
      DXPOA1 = "Y",
      DXPOA2 = "Y"
    )
    long <- data.frame(id = seq_len(n), cases)
    expected <- medicalcoder::comorbidities(
      long,
      icd.codes = "code",
      id.vars = "id",
      icdv.var = "icdv",
      dx.var = "dx",
      poa = 1L,
      primarydx = 0L,
      method = method
    )
    expected <- expected[match(long$id, expected$id), ]
    actual <- nis_comorbidity(fixture, method, prefix = "")
    fields <- setdiff(
      names(expected),
      c("id", "num_cmrb", "cmrb_flag", "mortality_index", "readmission_index", "cci", "age_score")
    )
    for (field in fields) {
      expect_identical(actual[[tolower(field)]], expected[[field]] == 1L, info = paste(method, field))
    }
    expect_identical(actual$n, expected$num_cmrb, info = method)
    expect_identical(actual$any, expected$cmrb_flag == 1L, info = method)
    for (index in intersect(c("cci", "mortality_index", "readmission_index"), names(expected))) {
      expect_identical(actual[[index]], expected[[index]], info = paste(method, index))
    }
  }
})
