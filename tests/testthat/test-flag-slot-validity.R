flag_slot_cases <- function() {
  lapply(c("I10_DX", "DX", "I10_PR", "PR"), function(stem) {
    diagnosis <- grepl("DX$", stem)
    list(stem = stem, system = if (startsWith(stem, "I10_")) "icd10" else "icd9",
      slots = if (diagnosis) "DX" else "PR",
      flag = if (diagnosis) nis_flag_dx else nis_flag_pr,
      positions = if (diagnosis) c("any", "principal", "secondary") else c("any", "principal"))
  })
}

test_that("malformed flag slots cannot set flags in canonical positions", {
  for (case in flag_slot_cases()) {
    flag <- case$flag
    system <- case$system
    slots <- case$slots
    positions <- case$positions
    stem <- case$stem
    for (suffix in c("0", "01", "02", "00", "-1", "1x", "1.0")) {
      data <- data.frame(id = 1L)
      data[[paste0(stem, "1")]] <- NA_character_
      data[[paste0(stem, "12")]] <- NA_character_
      data[[paste0(stem, suffix)]] <- "TOKEN"
      query <- duckdb_query_fixture(data)
      for (position in positions) {
        local <- flag(data, hit = "TOKEN", position = position, system = system)
        lazy <- flag(query, hit = "TOKEN", position = position, system = system)
        expect_s3_class(lazy, "tbl_sql")
        expect_identical(local$hit, FALSE)
        expect_identical(local[names(data)], data)
        expect_equal(dplyr::collect(lazy), dplyr::as_tibble(local))
      }
    }
  }
})

test_that("canonical sparse and reordered flag slots retain their positions", {
  for (case in flag_slot_cases()) {
    flag <- case$flag
    system <- case$system
    slots <- case$slots
    stem <- case$stem
    data <- data.frame(id = 1:4)
    data[[paste0(stem, "12")]] <- c(NA, "TOKEN", NA, NA)
    data[[paste0(stem, "01")]] <- rep("TOKEN", 4)
    data[[paste0(stem, "1")]] <- c("TOKEN", NA, NA, NA)
    data[[paste0(stem, "2147483648")]] <- c(NA, NA, "TOKEN", NA)
    other_stem <- paste0(if (system == "icd9") "I10_", slots)
    data[[paste0(other_stem, "1")]] <- rep("TOKEN", 4)
    query <- duckdb_query_fixture(data)
    expected <- list(any = c(TRUE, TRUE, TRUE, FALSE),
      principal = c(TRUE, FALSE, FALSE, FALSE))
    if (slots == "DX") expected$secondary <- c(FALSE, TRUE, TRUE, FALSE)
    for (position in names(expected)) {
      local <- flag(data, hit = "TOKEN", position = position, system = system)
      lazy <- flag(query, hit = "TOKEN", position = position, system = system)
      expect_identical(local$hit, expected[[position]])
      expect_identical(local[names(data)], data)
      expect_equal(dplyr::collect(lazy), dplyr::as_tibble(local))
    }

    sparse <- data[paste0(stem, "12")]
    expect_identical(flag(sparse, hit = "TOKEN", system = system)$hit,
      c(FALSE, TRUE, FALSE, FALSE))
    for (input in list(sparse, duckdb_query_fixture(sparse))) {
      expect_error(flag(input, hit = "TOKEN", position = "principal", system = system),
        "No ICD-.*columns.*match the requested position")
    }
  }
})

test_that("malformed-only flag schemas give a clear error", {
  for (case in flag_slot_cases()) {
    flag <- case$flag
    system <- case$system
    slots <- case$slots
    positions <- case$positions
    stem <- case$stem
    data <- data.frame(id = 1L)
    for (suffix in c("0", "01", "02", "-1", "1x")) {
      data[[paste0(stem, suffix)]] <- "TOKEN"
    }
    for (input in list(data, duckdb_query_fixture(data))) {
      for (position in positions) {
        expect_error(flag(input, hit = "TOKEN", position = position, system = system),
          "Slot suffixes must be positive integers without leading zeros")
      }
    }
  }
})
