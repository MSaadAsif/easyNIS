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

test_that("codes map to the conditions in medicalcoder's own tables", {
  skip_if_not_installed("medicalcoder")
  conditions <- c("AIDS", "DEMENTIA", "PSYCHOSES")
  codes <- single_codes(conditions)
  data <- dplyr::tibble(
    I10_DX1 = "ZZZ99",
    I10_DX2 = unname(codes),
    I10_DX3 = NA_character_
  )

  out <- nis_comorbidity(data)

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

  out <- nis_comorbidity(data)

  expect_identical(out$KEY, 1:6)
  expect_identical(out$cmrb_aids, c(FALSE, FALSE, FALSE, TRUE, FALSE, TRUE))
  expect_identical(out$cmrb_dementia, c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE))
  expect_identical(out$cmrb_n, c(0L, 0L, 0L, 1L, 1L, 2L))

  one_at_a_time <- do.call(rbind, lapply(seq_len(nrow(data)), function(i) {
    nis_comorbidity(data[i, ])
  }))
  expect_identical(out, one_at_a_time)
  expect_identical(nis_comorbidity(data[rev(seq_len(6)), ]),
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
  out <- nis_comorbidity(data)

  expected <- direct(data.frame(
    id = c(1L, 2L, 2L),
    code = c(hf, "ZZZ99", hf),
    primary = c(1L, 1L, 0L)
  ))
  expect_identical(out$cmrb_hf, expected$HF == 1L)
  expect_true(out$cmrb_hf[[2L]])
})

test_that("a discharge with no usable code gets zeros, including malformed text", {
  skip_if_not_installed("medicalcoder")
  malformed <- rawToChar(as.raw(c(0x49, 0x35, 0x30, 0xff, 0xfe)))
  data <- dplyr::tibble(
    I10_DX1 = c(NA_character_, malformed, "ZZZ99"),
    I10_DX2 = NA_character_
  )
  out <- nis_comorbidity(data)
  expect_identical(out$cmrb_n, c(0L, 0L, 0L))
  expect_false(any(out$cmrb_any))
  expect_identical(out$cmrb_mortality_index, c(0L, 0L, 0L))

  empty <- nis_comorbidity(data[0, ])
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), names(out))
})

test_that("method and prefix options and input errors are explicit", {
  skip_if_not_installed("medicalcoder")
  codes <- single_codes("AIDS", "elixhauser_ahrq2026")
  data <- dplyr::tibble(I10_DX1 = "ZZZ99", I10_DX2 = unname(codes))

  pinned <- nis_comorbidity(data, method = "elixhauser_ahrq2026", prefix = "e_")
  expect_true(pinned$e_aids)
  expect_false(any(grepl("^cmrb_", names(pinned))))

  expect_error(nis_comorbidity(data, method = "charlson_quan2011"), "Elixhauser")
  expect_error(nis_comorbidity(data, method = "elixhauser_nonsense"))
  expect_error(nis_comorbidity(data, prefix = NA_character_), "prefix")
  expect_error(nis_comorbidity(nis_comorbidity(data)), "replace existing")
  expect_error(nis_comorbidity(dplyr::tibble(AGE = 1)), "diagnosis columns")
  expect_error(nis_comorbidity(dplyr::tibble(I10_DX2 = "ZZZ99")), "I10_DX1")
  expect_error(nis_comorbidity(list(I10_DX1 = "ZZZ99")), "collected")

  path <- tempfile("nis-comorbidity-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(path, "part-0.parquet"))
  expect_error(nis_comorbidity(arrow::open_dataset(path)), "collect")
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

  enriched <- nis_comorbidity(design)

  expect_s3_class(enriched, "tbl_svy")
  expect_identical(enriched$cluster, design$cluster)
  expect_identical(enriched$strata, design$strata)
  expect_identical(enriched$prob, design$prob)
  expected <- nis_comorbidity(design$variables)
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
  enriched <- nis_comorbidity(design)

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
