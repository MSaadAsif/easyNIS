# HCUP NIS Summary Statistics (Core Weighted and Hospital Weights PDFs, page 1):
# https://hcup-us.ahrq.gov/db/nation/nis/nissummstats.jsp
# Uses the V2 reports for 2019 and 2020. Hospital counts are the nonmissing
# HOSP_NIS counts in the Hospital reports, also reported as Core clusters.
nis_release_reference <- data.frame(
  year = 2012:2024,
  rows = c(
    7296968, 7119563, 7071762, 7153989, 7135090, 7159694, 7105498,
    7083805, 6471165, 6666752, 6578372, 6743716, 7003015
  ),
  weight = c(
    36484846, 35597792, 35358818, 35769942, 35675421, 35798453, 35527481,
    35419023, 32355827, 33333720, 32891849, 33718585, 35015079
  ),
  hospitals = c(4378, 4363, 4411, 4573, 4575, 4584, 4550, 4568, 4580, 4558, 4544, 4181, 4061)
)

nis_open_check_release <- function(plan, dataset) {
  years <- dataset$years
  fields <- nis_sql_identifier_key(colnames(plan$query))
  has_year <- "year" %in% fields

  expected <- nis_release_reference[nis_release_reference$year %in% years, ]
  result <- tryCatch(nis_explain_invalid_utf8(list(
    empty = nis_release_empty_years(dbplyr::remote_con(plan$query), dataset$parts),
    observed = nis_release_totals(plan$query, years, fields, compare = has_year && nrow(expected) > 0L)
  )), error = identity)
  if (inherits(result, "error")) {
    cli::cli_warn(c(
      "NIS annual release check could not run.",
      i = "{conditionMessage(result)}"
    ), class = "easynis_release_check_failed")
    return(invisible(NULL))
  }

  observed <- result$observed
  fields_by_year <- split(lapply(plan$names_by_part, nis_sql_identifier_key), dataset$parts$year)
  references <- match(observed$release_year, expected$year)
  matched <- which(!is.na(references))
  details <- vapply(matched, function(i) {
    year <- observed$release_year[[i]]
    annual_fields <- Reduce(intersect, fields_by_year[[as.character(year)]])
    mismatches <- nis_release_mismatches(expected[references[[i]], ], observed[i, ], annual_fields)
    if (!length(mismatches)) return("")
    paste0(year, ": ", paste(mismatches, collapse = ", "))
  }, character(1))
  details <- c(details, paste0(result$empty, ": 0 unweighted discharges in the opened Parquet files",
    recycle0 = TRUE))
  details <- details[order(c(observed$release_year[matched], result$empty))]
  details <- c(details[nzchar(details)], nis_release_integrity_details(observed, years, has_year))
  if (length(details)) {
    cli::cli_warn(c(
      "NIS annual release check found discrepancies.",
      stats::setNames(details, rep("x", length(details))),
      i = "Cohort extracts are expected to differ. Set {.code check_release = FALSE} to skip the check."
    ), class = "easynis_release_mismatch")
  }
  invisible(NULL)
}

nis_release_empty_years <- function(con, parts) {
  # File metadata can distinguish an empty year from rows whose YEAR is missing or wrong.
  paths <- nis_parquet_paths(con, parts$path)
  metadata <- DBI::dbGetQuery(con, paste0(
    "SELECT file_name, num_rows FROM parquet_file_metadata(", paths, ")"
  ))
  files <- normalizePath(metadata$file_name, winslash = "/", mustWork = TRUE)
  rows <- metadata$num_rows[match(parts$path, files)]
  if (anyNA(rows)) stop("Could not determine the row count for every opened Parquet file.")
  setdiff(parts$year, parts$year[rows > 0])
}

nis_release_integrity_details <- function(observed, years, has_year) {
  details <- character()
  # Unrecognized values share one group, even if many distinct values are corrupt.
  unexpected <- observed[is.na(observed$release_year), ]
  if (has_year && nrow(unexpected)) {
    example <- if (is.na(unexpected$example_year)) "missing" else unexpected$example_year
    details <- paste0("YEAR missing or outside opened years on ", unexpected$rows, " rows",
      " (found ", example, ", expected ", paste(years, collapse = ", "), ")")
  }
  invalid_strata <- sum(observed$invalid_strata, na.rm = TRUE)
  if (invalid_strata > 0) {
    details <- c(details, paste0("Rows with NIS_STRATUM <= 0: ", invalid_strata, " (expected 0)"))
  }
  details
}

nis_release_totals <- function(query, years, fields, compare) {
  if (!any(c("year", "nis_stratum") %in% fields)) return(data.frame())
  con <- dbplyr::remote_con(query)
  year <- if ("year" %in% fields) "YEAR" else "NULL::INTEGER"
  weight <- if (compare && "discwt" %in% fields) "fsum(TRY_CAST(DISCWT AS DOUBLE))" else "NULL"
  hospitals <- if (compare && "hosp_nis" %in% fields) {
    valid <- nis_is_positive_finite_expr(query, dbplyr::sql("TRY_CAST(HOSP_NIS AS DOUBLE)"))
    predicate <- dbplyr::translate_sql(!!valid, con = con)
    paste0("count(DISTINCT HOSP_NIS) FILTER (WHERE ", predicate, ")")
  } else {
    "NULL"
  }
  strata <- if ("nis_stratum" %in% fields) "count_if(TRY_CAST(NIS_STRATUM AS DOUBLE) <= 0)" else "0"
  sql <- paste0(
    "SELECT CASE WHEN ", year, " IN (", paste(years, collapse = ", "), ") THEN ", year,
    " END AS release_year, min(", year, ") AS example_year, count(*) AS rows, ",
    weight, " AS weight, ", hospitals, " AS hospitals, ", strata, " AS invalid_strata ",
    "FROM (", dbplyr::sql_render(query), ") GROUP BY 1 ORDER BY 1"
  )
  DBI::dbGetQuery(con, sql)
}

nis_release_mismatches <- function(expected, observed, annual_fields) {
  fields <- c(rows = "unweighted discharges", weight = "sum of DISCWT", hospitals = "distinct HOSP_NIS")
  # HCUP's Core PDFs publish Sum of Weights rounded to the nearest whole
  # discharge. fsum compensates for floating-point error, and the extra
  # millionth covers arithmetic at the half-discharge boundary.
  tolerance <- c(rows = 0, weight = 0.500001, hospitals = 0)
  available <- c(TRUE, c("discwt", "hosp_nis") %in% annual_fields)
  details <- vapply(names(fields)[available], function(field) {
    target <- expected[[field]]
    actual <- as.numeric(observed[[field]])
    if (is.finite(actual) && abs(actual - target) <= tolerance[[field]]) return("")
    paste0(fields[[field]], " ", format(actual, scientific = FALSE, digits = 15),
      " (expected ", format(target, scientific = FALSE), ")")
  }, character(1))
  details[nzchar(details)]
}
