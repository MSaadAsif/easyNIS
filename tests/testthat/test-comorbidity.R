# Expected values come from medicalcoder's own lookup tables, never from
# code lists written here. Codes outside the tables are invented placeholders.
method <- "elixhauser_ahrq_icd10"

single_codes <- function(conditions, method = "elixhauser_ahrq_icd10") {
  tables <- medicalcoder::get_elixhauser_codes()
  tables <- tables[tables$icdv == 10 & tables$dx == 1 &
    tables[[method]] %in% 1, ]
  unique_codes <- names(which(table(tables$code) == 1L))
  tables <- tables[tables$code %in% unique_codes, ]
  vapply(conditions, function(condition) {
    tables$code[tables$condition == condition][[1L]]
  }, character(1))
}

direct <- function(rows, method = "elixhauser_ahrq_icd10") {
  medicalcoder::comorbidities(
    rows, icd.codes = "code", id.vars = "id", method = method,
    icdv = 10L, dx = 1L, poa = 1L, primarydx.var = "primary"
  )
}

without_poa_warning <- function(expr) {
  withCallingHandlers(expr, warning = function(warning) {
    if (grepl("No matching POA column", conditionMessage(warning))) {
      invokeRestart("muffleWarning")
    }
  })
}

test_that("codes map to the conditions in medicalcoder's own tables", {
  skip_if_not_installed("medicalcoder")
  conditions <- c("AIDS", "DEMENTIA", "PSYCHOSES")
  codes <- single_codes(conditions)
  data <- dplyr::tibble(
    I10_DX1 = "ZZZ99",
    I10_DX2 = unname(codes),
    I10_DX3 = NA_character_
  )

  out <- suppressWarnings(nis_comorbidity(data))

  for (i in seq_along(conditions)) {
    expect_true(out[[paste0("cmrb_", tolower(conditions[[i]]))]][[i]])
  }
  expect_identical(out$cmrb_n, c(1L, 1L, 1L))
  expect_identical(out$cmrb_any, c(TRUE, TRUE, TRUE))

  scores <- medicalcoder::get_elixhauser_index_scores()
  for (i in seq_along(conditions)) {
    for (index in c("mortality", "readmission")) {
      expected <- scores[[method]][scores$condition == conditions[[i]] &
        scores$index == index]
      expect_equal(out[[paste0("cmrb_", index, "_index")]][[i]], expected)
    }
  }
})

test_that("wide-to-long reshaping keeps row order and tolerates messy codes", {
  skip_if_not_installed("medicalcoder")
  codes <- single_codes(c("AIDS", "DEMENTIA"))
  data <- dplyr::tibble(
    KEY = 1:6,
    I10_DX1 = c("ZZZ99", NA, "", "ZZZ99", "zzz99", "ZZZ99"),
    I10_DX2 = c(NA, NA, NA, tolower(codes[["AIDS"]]), NA, codes[["DEMENTIA"]]),
    I10_DX3 = c(NA, NA, NA, NA, paste0(" ", codes[["DEMENTIA"]], " "),
      codes[["AIDS"]])
  )

  expect_warning(out <- without_poa_warning(nis_comorbidity(data)), "2 rows")

  expect_identical(out$KEY, 1:6)
  expect_identical(out$cmrb_aids, c(FALSE, NA, NA, TRUE, FALSE, TRUE))
  expect_identical(out$cmrb_dementia, c(FALSE, NA, NA, FALSE, TRUE, TRUE))
  expect_identical(out$cmrb_n, c(0L, NA, NA, 1L, 1L, 2L))

  one_at_a_time <- suppressWarnings(do.call(rbind, lapply(seq_len(nrow(data)),
    function(i) nis_comorbidity(data[i, ]))))
  expect_identical(out, one_at_a_time)
  expect_identical(suppressWarnings(nis_comorbidity(data[rev(seq_len(6)), ])),
    out[rev(seq_len(6)), ])
  expect_s3_class(out, "tbl_df")
  expect_identical(names(out)[1:4], names(data))
})

test_that("I10_DX1 is passed as the principal diagnosis", {
  skip_if_not_installed("medicalcoder")
  hf <- single_codes("HF")
  data <- dplyr::tibble(
    I10_DX1 = c(hf, "ZZZ99"),
    I10_DX2 = c(NA, hf)
  )
  out <- suppressWarnings(nis_comorbidity(data))

  expected <- direct(data.frame(
    id = c(1L, 2L, 2L),
    code = c(hf, "ZZZ99", hf),
    primary = c(1L, 1L, 0L)
  ))
  expect_identical(out$cmrb_hf, expected$HF == 1L)
  expect_true(out$cmrb_hf[[2L]])
})

test_that("diagnosis POA indicators exclude secondary in-hospital conditions", {
  skip_if_not_installed("medicalcoder")
  hf <- single_codes("HF")
  data <- dplyr::tibble(
    I10_DX1 = "ZZZ99",
    I10_DX2 = hf,
    DXPOA1 = "Y",
    DXPOA2 = "N"
  )

  expect_false(nis_comorbidity(data)$cmrb_hf)

  data$DXPOA2 <- "Y"
  expect_true(nis_comorbidity(data)$cmrb_hf)

  data$DXPOA2 <- "U"
  expect_false(nis_comorbidity(data)$cmrb_hf)

  data$DXPOA2 <- "W"
  expect_true(nis_comorbidity(data)$cmrb_hf)

  data <- dplyr::select(data, -dplyr::starts_with("DXPOA"))
  expect_warning(out <- nis_comorbidity(data), "I10_DX1.*I10_DX2")
  expect_true(out$cmrb_hf)
})

test_that("partial and absent POA columns warn and assume present", {
  skip_if_not_installed("medicalcoder")
  hf <- single_codes("HF")
  partial <- dplyr::tibble(
    I10_DX1 = "ZZZ99", I10_DX2 = "ZZZ99", I10_DX3 = hf,
    DXPOA1 = "Y", DXPOA2 = "Y"
  )
  expect_warning(partial_out <- nis_comorbidity(partial), "I10_DX3")
  expect_true(partial_out$cmrb_hf)

  absent <- dplyr::select(partial, -dplyr::starts_with("DXPOA"))
  expect_warning(absent_out <- nis_comorbidity(absent), "I10_DX1.*I10_DX2.*I10_DX3")
  expect_true(absent_out$cmrb_hf)
})

test_that("POA-exempt conditions follow medicalcoder's mapping", {
  skip_if_not_installed("medicalcoder")
  aids <- single_codes("AIDS")
  data <- dplyr::tibble(I10_DX1 = "ZZZ99", I10_DX2 = aids,
    DXPOA1 = "Y", DXPOA2 = "N")

  expect_true(nis_comorbidity(data)$cmrb_aids)
})

test_that("a discharge with no usable code gets NA and a warning, not zeros", {
  skip_if_not_installed("medicalcoder")
  malformed <- rawToChar(as.raw(c(0x49, 0x35, 0x30, 0xff, 0xfe)))
  data <- dplyr::tibble(
    I10_DX1 = c(NA_character_, malformed, "ZZZ99", ""),
    I10_DX2 = NA_character_
  )
  expect_warning(out <- without_poa_warning(nis_comorbidity(data)), "3 rows")
  expect_identical(out$cmrb_n[c(1, 2, 4)], rep(NA_integer_, 3L))
  expect_identical(out$cmrb_n[[3L]], 0L)
  expect_identical(out$cmrb_any, c(NA, NA, FALSE, NA))
  expect_identical(out$cmrb_mortality_index[[3L]], 0L)
  expect_true(all(is.na(out$cmrb_hf[c(1, 2, 4)])))
  expect_identical(out$cmrb_hf[[3L]], FALSE)
  expect_true(all(vapply(out[grepl("^cmrb_", names(out))][c(1, 2, 4), ],
    function(column) all(is.na(column)), logical(1))))

  all_usable <- dplyr::tibble(I10_DX1 = "ZZZ99", DXPOA1 = "Y")
  expect_no_warning(nis_comorbidity(all_usable))

  empty <- suppressWarnings(nis_comorbidity(data[0, ]))
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), names(suppressWarnings(nis_comorbidity(data))))
})

test_that("ICD-9-era rows are NA while ICD-10 rows in the same data are scored", {
  skip_if_not_installed("medicalcoder")
  codes <- single_codes("AIDS")
  data <- dplyr::tibble(
    YEAR = c(2014L, 2016L),
    I10_DX1 = c(NA_character_, "ZZZ99"),
    I10_DX2 = c(NA_character_, codes[["AIDS"]])
  )
  expect_warning(out <- without_poa_warning(nis_comorbidity(data)), "no usable")
  expect_identical(out$cmrb_any, c(NA, TRUE))
  expect_identical(out$cmrb_n, c(NA, 1L))
})

test_that("method and prefix options and input errors are explicit", {
  skip_if_not_installed("medicalcoder")
  codes <- single_codes("AIDS", "elixhauser_ahrq2026")
  data <- dplyr::tibble(I10_DX1 = "ZZZ99", I10_DX2 = unname(codes))

  pinned <- suppressWarnings(nis_comorbidity(data, method = "elixhauser_ahrq2026", prefix = "e_"))
  expect_true(pinned$e_aids)
  expect_false(any(grepl("^cmrb_", names(pinned))))

  expect_error(nis_comorbidity(data, method = "charlson_quan2011"), "Elixhauser")
  expect_error(suppressWarnings(nis_comorbidity(data, method = "elixhauser_nonsense")))
  expect_error(nis_comorbidity(data, prefix = NA_character_), "prefix")
  expect_error(suppressWarnings(nis_comorbidity(suppressWarnings(nis_comorbidity(data)))), "replace existing")
  expect_error(nis_comorbidity(dplyr::tibble(AGE = 1)), "diagnosis columns")
  expect_error(nis_comorbidity(dplyr::tibble(I10_DX2 = "ZZZ99")), "I10_DX1")
  expect_error(nis_comorbidity(list(I10_DX1 = "ZZZ99")), "collected")

  path <- tempfile("nis-comorbidity-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  expect_error(nis_comorbidity(open_duckdb_dataset(path)), "collect")
})

test_that("a nis_design keeps its design and gains comorbidity columns", {
  skip_if_not_installed("medicalcoder")
  path <- nis_example(2017:2018)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  design <- suppressMessages(nis_design(
    query, heart_failure,
    keep = c(AGE, dplyr::starts_with("I10_DX"))
  ))

  enriched <- suppressWarnings(nis_comorbidity(design))

  labelled_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "AGE")
  labels <- lapply(labelled_fields, function(field) {
    attr(design$variables[[field]], "label", exact = TRUE)
  })
  names(labels) <- labelled_fields
  expect_true(all(vapply(labels, Negate(is.null), logical(1))))
  for (field in labelled_fields) {
    expect_identical(
      attr(enriched$variables[[field]], "label", exact = TRUE), labels[[field]]
    )
  }

  expect_s3_class(enriched, "tbl_svy")
  expect_identical(enriched$cluster, design$cluster)
  expect_identical(enriched$strata, design$strata)
  expect_identical(enriched$prob, design$prob)
  expected <- suppressWarnings(nis_comorbidity(design$variables))
  expect_identical(enriched$variables, expected)
  expect_true(all(c("cmrb_hf", "cmrb_n", "cmrb_mortality_index") %in%
    names(enriched$variables)))
  total <- survey::svytotal(~cmrb_any, enriched)
  expect_true(is.finite(stats::coef(total)[["cmrb_anyTRUE"]]))
})

test_that("nis_reweight works on a design that went through nis_comorbidity", {
  skip_if_not_installed("medicalcoder")
  path <- nis_example(2017:2018)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  design <- suppressMessages(nis_design(
    query, heart_failure,
    keep = c(AGE, dplyr::starts_with("I10_DX"))
  ))
  enriched <- suppressWarnings(nis_comorbidity(design))

  labelled_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "AGE")
  labels <- lapply(labelled_fields, function(field) {
    attr(design$variables[[field]], "label", exact = TRUE)
  })
  names(labels) <- labelled_fields
  expect_true(all(vapply(labels, Negate(is.null), logical(1))))

  expect_identical(
    attr(enriched, "nis_placeholder_rows"),
    attr(design, "nis_placeholder_rows")
  )
  expect_identical(
    attr(enriched, "nis_cohort_rows"),
    attr(design, "nis_cohort_rows")
  )

  multipliers <- 0.6 + (seq_len(nrow(enriched$variables)) %% 7) / 10
  reweighted <- nis_reweight(enriched, multipliers)
  reference <- nis_reweight(design, multipliers)
  for (field in labelled_fields) {
    expect_identical(
      attr(reweighted$variables[[field]], "label", exact = TRUE), labels[[field]]
    )
  }
  comorbid_after_reweight <- suppressWarnings(nis_comorbidity(reference))
  for (field in labelled_fields) {
    expect_identical(
      attr(comorbid_after_reweight$variables[[field]], "label", exact = TRUE),
      labels[[field]]
    )
  }

  expect_s3_class(reweighted, "tbl_svy")
  expect_true(all(c("cmrb_hf", "cmrb_n") %in% names(reweighted$variables)))
  expect_equal(
    as.numeric(stats::weights(reweighted)),
    as.numeric(stats::weights(reference))
  )
  expect_equal(
    survey::svymean(~AGE, reweighted) |> stats::coef(),
    survey::svymean(~AGE, reference) |> stats::coef()
  )
  expect_equal(
    survey::SE(survey::svymean(~AGE, reweighted)),
    survey::SE(survey::svymean(~AGE, reference))
  )
  expect_identical(survey::degf(reweighted), survey::degf(reference))
})
