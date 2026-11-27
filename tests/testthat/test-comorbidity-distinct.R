# Use medicalcoder's emitted flags as the oracle inputs, with separate
# hand-labeled counts to catch errors shared by the public map and scorer.
reference_distinct <- function(method, flags, ids, exclude = character()) {
  map <- nis_comorbidity_condition_map(method, prefix = "")
  fields <- setdiff(
    names(flags),
    c("id", "num_cmrb", "cmrb_flag", "mortality_index", "readmission_index", "cci", "age_score")
  )
  expect_setequal(map$output, tolower(fields))
  flags <- flags[match(ids, flags$id), fields, drop = FALSE]
  vapply(
    seq_along(ids),
    function(i) {
      active <- fields[which(unlist(flags[i, ]) == 1L)]
      length(setdiff(map$condition[map$output %in% tolower(active)], exclude))
    },
    integer(1)
  )
}

test_that("refined Elixhauser counts the union of output components in DuckDB", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  method <- "elixhauser_ahrq2026"
  codes <- c(
    "I132",
    "I132",
    "I132",
    "K7010",
    "I69359",
    "F11150",
    "I110",
    "I120",
    "K7682",
    "I27840",
    "G9345",
    "M3211",
    "E119",
    "ZZZ99",
    NA
  )
  fixture <- data.frame(
    KEY_NIS = seq_along(codes),
    I10_DX1 = c(rep("I132", length(codes) - 1L), NA),
    I10_DX2 = codes,
    I10_DX3 = c("I509", rep(NA, 11L), "E1122", NA, NA),
    I10_DX4 = c("N186", rep(NA, 11L), "D0500", NA, NA),
    I10_DX5 = c("I10", rep(NA, 11L), "C50919", NA, NA),
    I10_DX6 = c(rep(NA, 12L), "C7800", NA, NA),
    I10_DX7 = c(rep(NA, 12L), "C9200", NA, NA),
    DXPOA1 = "Y",
    DXPOA2 = c("Y", "N", NA, rep("Y", 12L)),
    DXPOA3 = "Y",
    DXPOA4 = "Y",
    DXPOA5 = "Y",
    DXPOA6 = "Y",
    DXPOA7 = "Y"
  )
  long <- do.call(
    rbind,
    lapply(2:7, function(i) {
      data.frame(
        id = fixture$KEY_NIS,
        code = fixture[[paste0("I10_DX", i)]],
        poa = unname(c(Y = 1L, N = 0L)[fixture[[paste0("DXPOA", i)]]])
      )
    })
  )
  flags <- medicalcoder::comorbidities(
    long[!is.na(long$code), ],
    icd.codes = "code",
    id.vars = "id",
    icdv = 10L,
    dx = 1L,
    primarydx = 0L,
    poa.var = "poa",
    method = method
  )

  map <- nis_comorbidity_condition_map(method)
  combinations <- list(
    hfhtn_cxrenlfl_sev = c("hf", "hypertension", "renal_failure"),
    alcoholliver_mld = c("alcohol", "liver_disease"),
    cbvd_sqlaparalysis = c("cbvd", "paralysis"),
    drug_abusepsychoses = c("drug_abuse", "psychoses"),
    hfhtn_cx = c("hf", "hypertension"),
    htn_cxrenlfl_sev = c("hypertension", "renal_failure"),
    liver_mld_neuro = c("liver_disease", "neuro_oth"),
    liver_mld_pulmcirc = c("liver_disease", "pulmcirc"),
    neuro_oth_seiz = c("neuro_oth", "neuro_seiz"),
    valve_autoimmune = c("valve", "autoimmune")
  )
  for (output in names(combinations)) {
    expect_setequal(map$condition[map$output == paste0("cmrb_", output)], combinations[[output]])
  }

  expected <- c(3L, 1L, 1L, rep(2L, 9L), 3L, 0L, NA_integer_)
  usable <- seq_len(nrow(fixture) - 1L)
  expect_identical(reference_distinct(method, flags, usable), expected[usable])
  expect_warning(default <- nis_comorbidity(fixture, method), "1 row.*no usable")
  expect_warning(frame <- nis_comorbidity(fixture, method, count_distinct = TRUE), "1 row.*no usable")
  expect_identical(frame$cmrb_n_distinct, expected)
  expect_identical(frame[names(default)], default)

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  query <- dplyr::copy_to(con, fixture, "discharges")
  exclude <- c("hypertension", "diabetes", "liver_disease")
  filtered <- c(2L, 0L, 0L, 1L, 2L, 2L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 0L, NA_integer_)
  expect_identical(reference_distinct(method, flags, usable, exclude), filtered[usable])
  expect_warning(
    lazy <- nis_comorbidity(query, method, count_distinct = TRUE, exclude_conditions = exclude),
    "1 row.*no usable"
  )
  expect_warning(
    excluded_frame <- nis_comorbidity(fixture, method, count_distinct = TRUE, exclude_conditions = exclude),
    "1 row.*no usable"
  )
  expect_s3_class(lazy, "tbl_sql")
  types <- DBI::dbGetQuery(con, paste("DESCRIBE", dbplyr::sql_render(lazy)))
  expect_identical(
    types$column_type[match(c("cmrb_hf", "cmrb_n_distinct"), types$column_name)],
    c("BOOLEAN", "INTEGER")
  )
  observed <- lazy |> dplyr::arrange(KEY_NIS) |> dplyr::collect() |> as.data.frame()
  expect_identical(excluded_frame$cmrb_n_distinct, filtered)
  expect_identical(excluded_frame[names(default)], default)
  expect_identical(observed, excluded_frame)

  expect_warning(
    all_excluded <- nis_comorbidity(query, method, count_distinct = TRUE, exclude_conditions = unique(map$condition)),
    "1 row.*no usable"
  )
  empty <- all_excluded |> dplyr::arrange(KEY_NIS) |> dplyr::pull(cmrb_n_distinct)
  expect_identical(empty, c(rep(0L, length(usable)), NA_integer_))
})

test_that("Quan Elixhauser and Charlson counts work across the ICD transition", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  icdv <- c(9L, 10L)
  codes9 <- c("25000", "25040", "1969", "1749", "4019", "40291", "42731")
  codes10 <- c("E119", "E1122", "C7800", "C50919", "I10", "I132", "I4891")
  fixture <- data.frame(KEY_NIS = 1:2, YEAR = c(2014L, 2016L), DX1 = "00000", I10_DX1 = "ZZZ99", DXPOA1 = "Y")
  for (i in seq_along(codes9)) {
    fixture[[paste0("DX", i + 1L)]] <- codes9[i]
    fixture[[paste0("I10_DX", i + 1L)]] <- codes10[i]
    fixture[[paste0("DXPOA", i + 1L)]] <- "Y"
  }
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  query <- dplyr::copy_to(con, fixture, "discharges")
  counts <- list(
    elixhauser_quan2005 = c(5L, 5L),
    charlson_quan2005 = c(3L, 3L),
    charlson_quan2011 = c(3L, 3L),
    charlson_deyo1992 = c(2L, NA_integer_)
  )
  long <- data.frame(
    id = rep(1:2, each = length(codes9)),
    icdv = rep(icdv, each = length(codes9)),
    code = c(codes9, codes10)
  )
  for (method in names(counts)) {
    rows <- which(!is.na(counts[[method]]))
    flags <- medicalcoder::comorbidities(
      long[long$id %in% rows, ],
      icd.codes = "code",
      id.vars = "id",
      icdv.var = "icdv",
      dx = 1L,
      primarydx = 0L,
      poa = 1L,
      method = method
    )
    expect_identical(reference_distinct(method, flags, rows), counts[[method]][rows], info = method)
    frame <- suppressWarnings(nis_comorbidity(fixture, method, count_distinct = TRUE))
    lazy <- suppressWarnings(nis_comorbidity(query, method, count_distinct = TRUE))
    expect_s3_class(lazy, "tbl_sql")
    observed <- lazy |> dplyr::arrange(KEY_NIS) |> dplyr::collect() |> as.data.frame()
    expect_identical(frame$cmrb_n_distinct, counts[[method]], info = method)
    expect_identical(observed, frame, info = method)
  }
})

test_that("the count validates options and uses the selected output prefix", {
  method <- "elixhauser_ahrq2027"
  fixture <- data.frame(I10_DX1 = "ZZZ99", I10_DX2 = "E119", DXPOA1 = "Y", DXPOA2 = "Y")
  map <- nis_comorbidity_condition_map(method, prefix = "risk_")
  expect_setequal(map$output[map$condition == "diabetes"], c("risk_diab_cx", "risk_diab_uncx"))
  expect_identical(nis_comorbidity(fixture, method, "risk_", count_distinct = TRUE)$risk_n_distinct, 1L)
  expect_error(nis_comorbidity(fixture, method, count_distinct = NA), "`count_distinct`")
  expect_error(nis_comorbidity(fixture, method, exclude_conditions = "diabetes"), "requires")
  expect_error(nis_comorbidity(fixture, method, count_distinct = TRUE, exclude_conditions = NA_character_), "missing")
  expect_error(nis_comorbidity(fixture, method, count_distinct = TRUE, exclude_conditions = "diab_cx"), "Unknown")
  fixture$cmrb_n_distinct <- 123L
  expect_error(nis_comorbidity(fixture, method, count_distinct = TRUE), "would replace")
})
