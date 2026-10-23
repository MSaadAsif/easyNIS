test_that("nis_cost validates each input boundary", {
  valid <- data.frame(YEAR = 2020, TOTCHG = 1000, CCR_NIS = 0.25)

  expect_error(nis_cost(list(), 2020), "collected data frame")
  expect_error(nis_cost(valid, 2020, charges = character()), "single column name")
  expect_error(nis_cost(valid, 2020, charges = c("TOTCHG", "OTHER")),
    "single column name")
  expect_error(nis_cost(valid, 2020, charges = NA_character_),
    "single column name")
  expect_error(nis_cost(valid, NA_real_), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, 2020.5), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, c(2020, 2021)), "one year from 2012 through 2024")

  valid$YEAR <- "2020"
  expect_error(nis_cost(valid, 2020), "must be numeric")
})

test_that("nis_cost_provenance validates its supported inputs", {
  expect_null(nis_cost_provenance(data.frame()))
  expect_error(nis_cost_provenance(list()), "data frame or survey design")
})

nis_example_test_digest <- function(data) {
  encode <- function(value) {
    if (is.na(value)) return("N;")
    text <- if (is.character(value)) {
      enc2utf8(value)
    } else if (is.double(value)) {
      format(value, digits = 15, scientific = TRUE, trim = TRUE)
    } else {
      as.character(value)
    }
    paste0("V", nchar(text, type = "bytes"), ":", text, ";")
  }
  columns <- paste0(nchar(names(data), type = "bytes"), ":", names(data), ";")
  rows <- vapply(seq_len(nrow(data)), function(i) {
    paste0(vapply(data, function(column) encode(column[[i]]), character(1)),
      collapse = "")
  }, character(1))
  content <- paste0(paste(columns, collapse = ""), "\n",
    paste(rows, collapse = "\n"), "\n")
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  connection <- file(path, "wb")
  writeBin(charToRaw(enc2utf8(content)), connection)
  close(connection)
  unname(tools::md5sum(path))
}

test_that("nis_example keeps annual layouts and invented values stable", {
  configs <- list(2012L, c(2015L, 2016L), c(2022L, 2023L))
  expected_years <- unlist(configs, use.names = FALSE)
  paths <- lapply(configs, nis_example)
  on.exit(unlink(unlist(paths), recursive = TRUE), add = TRUE)

  records <- do.call(c, Map(function(path, years) {
    lapply(years, function(year) {
      open_duckdb_dataset(file.path(path, paste0("NIS_", year, ".parquet"))) |>
        dplyr::collect()
    })
  }, paths, configs))

  expected <- data.frame(
    year = expected_years,
    rows = rep(96L, 5L),
    columns = c(80L, 137L, 108L, 108L, 108L),
    data_digest = c(
      "f52c3ef14dea917d33b2b710579cc403",
      "7475953cbae9aac5322739e942ede8c4",
      "4753b5b1c07725c07610534b36fb10ff",
      "43d9a1be3738ab4f3c25a95e3e84f7e3",
      "3d0e1aa5ea49f31d78528008a7f77fa5"
    ),
    schema_digest = c(
      "0e23d0cc44c11c5832c1fb67ac2476dc",
      "c120bfe98c6b6fe70386ad6d70737851",
      "c766aba2324e55ab976c7d755743f148",
      "41a23bc0e1ef0458e689c5cf520c942d",
      "c766aba2324e55ab976c7d755743f148"
    )
  )
  schema_digest <- function(data) {
    schema <- paste(names(data), vapply(data, typeof, character(1)),
      sep = ":", collapse = "|")
    nis_example_test_digest(data.frame(schema = schema))
  }
  expect_identical(vapply(records, nrow, integer(1)), expected$rows)
  expect_identical(vapply(records, ncol, integer(1)), expected$columns)
  expect_identical(vapply(records, nis_example_test_digest, character(1)),
    expected$data_digest)
  expect_identical(vapply(records, schema_digest, character(1)),
    expected$schema_digest)

  expect_false(any(grepl("^I10_", names(records[[1L]]))))
  expect_true(all(c("DXVER", "PRVER", "DX1", "PR1", "NDX", "NPR") %in%
    names(records[[2L]])))
  expect_true(all(c("I10_DX1", "I10_PR1", "DXVER", "PRVER") %in%
    names(records[[2L]])))
  expect_false("I10_DX31" %in% names(records[[2L]]))
  expect_true(all(c("I10_DX40", "I10_PR25") %in% names(records[[3L]])))
  expect_true(all(c("APRDRG_RISK_MORTALITY", "APRDRG_SEVERITY", "DRG_NOPOA",
    "MDC_NOPOA") %in% names(records[[4L]])))
  expect_true(all(c("APRDRG_Risk_Mortality", "APRDRG_Severity", "DRG_NoPOA",
    "MDC_NoPOA") %in% names(records[[5L]])))
  expect_identical(records[[1L]]$YEAR, rep(2012L, 96L))
  expect_identical(records[[4L]]$I10_DX1[1:4], c("I5022", "I5022", "J189", "I5022"))

  duplicate_path <- nis_example(c(2023, 2012, 2023))
  on.exit(unlink(duplicate_path, recursive = TRUE), add = TRUE)
  expect_setequal(list.files(duplicate_path), c("NIS_2023.parquet", "NIS_2012.parquet"))
  duplicate_records <- open_duckdb_dataset(file.path(
    duplicate_path, "NIS_2023.parquet"
  )) |> dplyr::collect()
  expect_identical(duplicate_records, records[[5L]])
})
