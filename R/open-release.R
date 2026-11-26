# HCUP Introduction to the NIS, 2021, Table 3 (2012-2021):
# https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2021.jsp
# HCUP Introduction to the NIS, 2024, Table A2 (2022-2024):
# https://hcup-us.ahrq.gov/db/nation/nis/NISIntroduction2024.pdf
# Both retrieved 2026-11-26. The introduction tables and the Core File
# statistics disagree for 2021; this comparison uses the introduction tables.
nis_release_reference <- data.frame(
  year = 2012:2024,
  rows = c(
    7296968, 7119563, 7071762, 7153989, 7135090, 7159694, 7105498,
    7083805, 6471165, 6666817, 6578372, 6743716, 7003015
  ),
  weight = c(
    36484846, 35597792, 35358818, 35769942, 35675421, 35798453, 35527481,
    35419023, 32355827, 33334053, 32891849, 33718585, 35015079
  ),
  hospitals = c(4378, 4363, 4411, 4573, 4575, 4584, 4550, 4568, 4580, 4558, 4544, 4181, 4061)
)

nis_open_check_release <- function(query, years) {
  expected <- nis_release_reference[nis_release_reference$year %in% years, ]
  if (!nrow(expected)) return(invisible(NULL))

  observed <- nis_release_totals(query, years)
  details <- vapply(seq_len(nrow(expected)), function(i) {
    year <- expected$year[[i]]
    year_totals <- observed[observed$release_year %in% year, ]
    mismatches <- nis_release_mismatches(expected[i, ], year_totals)
    if (length(mismatches)) paste0(year, ": ", paste(mismatches, collapse = ", ")) else ""
  }, character(1))

  # Unrecognized values share one group, even if many distinct values are corrupt.
  unexpected <- observed[is.na(observed$release_year), ]
  if (nrow(unexpected)) {
    example <- if (is.na(unexpected$example_year)) "missing" else unexpected$example_year
    detail <- paste0("YEAR missing or outside opened years on ", unexpected$rows, " rows",
      " (found ", example, ", expected ", paste(years, collapse = ", "), ")")
    details <- c(details, paste(c(detail, nis_release_invalid_strata(unexpected)), collapse = ", "))
  }

  details <- details[nzchar(details)]
  if (length(details)) {
    cli::cli_warn(c(
      "NIS annual release check found discrepancies against HCUP's introduction tables.",
      stats::setNames(details, rep("x", length(details)))
    ), class = "easynis_release_mismatch")
  }
  invisible(NULL)
}

nis_release_totals <- function(query, years) {
  fields <- toupper(colnames(query))
  year <- if ("YEAR" %in% fields) "YEAR" else "NULL::INTEGER"
  weight <- if ("DISCWT" %in% fields) "fsum(TRY_CAST(DISCWT AS DOUBLE))" else "NULL"
  hospitals <- if ("HOSP_NIS" %in% fields) "count(DISTINCT HOSP_NIS)" else "NULL"
  strata <- if ("NIS_STRATUM" %in% fields) "count_if(TRY_CAST(NIS_STRATUM AS DOUBLE) <= 0)" else "0"
  sql <- paste0(
    "SELECT CASE WHEN ", year, " IN (", paste(years, collapse = ", "), ") THEN ", year,
    " END AS release_year, min(", year, ") AS example_year, count(*) AS rows, ",
    weight, " AS weight, ", hospitals, " AS hospitals, ", strata, " AS invalid_strata ",
    "FROM (", dbplyr::sql_render(query), ") GROUP BY 1"
  )
  DBI::dbGetQuery(dbplyr::remote_con(query), sql)
}

nis_release_mismatches <- function(expected, observed) {
  fields <- c(rows = "unweighted discharges", weight = "sum of DISCWT", hospitals = "distinct HOSP_NIS")
  # fsum compensates for floating-point error. Allow a millionth of a
  # discharge beyond the half-discharge rounding interval.
  tolerance <- c(rows = 0, weight = 0.500001, hospitals = 0)
  details <- vapply(names(fields), function(field) {
    target <- expected[[field]]
    actual <- if (nrow(observed)) as.numeric(observed[[field]]) else 0
    if (is.finite(actual) && abs(actual - target) <= tolerance[[field]]) return("")
    paste0(fields[[field]], " ", format(actual, scientific = FALSE, digits = 15),
      " (expected ", format(target, scientific = FALSE), ")")
  }, character(1))
  c(details[nzchar(details)], nis_release_invalid_strata(observed))
}

nis_release_invalid_strata <- function(observed) {
  count <- observed$invalid_strata
  if (!length(count) || is.na(count) || count == 0) return(character())
  paste0("rows with NIS_STRATUM <= 0: ", count, " (expected 0)")
}
