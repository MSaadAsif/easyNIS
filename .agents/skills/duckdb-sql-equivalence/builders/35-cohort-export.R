# An export can drop patients, treat missing membership as true, retain an
# invalid patient, omit an empty hospital-year, or use its wrong weight.
export_cases <- function(con) {
  masks <- fixture(a = c(FALSE, TRUE, NA), b = c(FALSE, TRUE, NA), c = c(FALSE, TRUE, NA), d = c(FALSE, TRUE, NA))
  rows <- data.frame(
    YEAR = rep(c(2019L, 2020L), length.out = nrow(masks) * 4L),
    HOSP_NIS = rep(c(1L, 1L, 2L, 2L), nrow(masks)) +
      rep((seq_len(nrow(masks)) - 1L) * 2L, each = 4L),
    NIS_STRATUM = 1L,
    DISCWT = rep(c(4, 2, 6, 3), nrow(masks)),
    keep = as.vector(t(as.matrix(masks[1:4]))),
    id = seq_len(nrow(masks) * 4L)
  )
  # Reuse IDs across years, with unequal sample weights and an invalid
  # always-selected record that must never become a patient or placeholder.
  extra <- rows
  extra$id <- extra$id + nrow(rows)
  extra$DISCWT <- extra$DISCWT - 1
  extra$keep <- FALSE
  invalid <- transform(rows[1:2, ], id = max(extra$id) + 1:2, DISCWT = -1, keep = TRUE)
  all <- rbind(rows, extra, invalid)
  list(case(all), case(transform(all, keep = NA)))
}

export_order <- function(out) {
  out[order(out$YEAR, out$HOSP_NIS, out$id), , drop = FALSE]
}

export_sql <- function(con, rows, args) {
  root <- tempfile("cohort-export-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  source <- file.path(root, "source")
  dir.create(source)
  duck_table(con, rows)
  for (year in unique(rows$YEAR)) {
    part <- DBI::dbQuoteString(con, file.path(source, sprintf("NIS_%d.parquet", year)))
    DBI::dbExecute(con, sprintf("COPY (FROM fixture WHERE YEAR = %d) TO %s (FORMAT PARQUET)", year, part))
  }
  input <- easyNIS::nis_open(source, check_release = FALSE)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(input), shutdown = TRUE), add = TRUE, after = FALSE)
  dest <- easyNIS::nis_write_cohort(input, keep, file.path(root, "export"), keep = id)
  output <- easyNIS::nis_open(dest)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(output), shutdown = TRUE), add = TRUE, after = FALSE)
  out <- as.data.frame(dplyr::collect(output))
  export_order(out[c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "id", ".in_cohort")])
}

export_reference <- function(rows, args) {
  rows <- rows[valid_design(rows)$ok, ]
  patients <- rows[rows$keep %in% TRUE, ]
  roster <- stats::aggregate(DISCWT ~ YEAR + HOSP_NIS + NIS_STRATUM, rows, min)
  represented <- paste(patients$YEAR, patients$HOSP_NIS)
  placeholders <- roster[!paste(roster$YEAR, roster$HOSP_NIS) %in% represented, ]
  placeholders$id <- rep(NA_integer_, nrow(placeholders))
  placeholders$.in_cohort <- rep(FALSE, nrow(placeholders))
  patients$.in_cohort <- rep(TRUE, nrow(patients))
  columns <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "id", ".in_cohort")
  export_order(rbind(patients[columns], placeholders[columns]))
}

export_years <- function(x) {
  pair <- split_years(x)
  pair$combine <- function(outputs) export_order(do.call(rbind, outputs))
  pair
}

register(
  "cohort-export",
  export_cases,
  export_sql,
  export_reference,
  mutation("write-cohort.R", "nis_cohort_placeholders", " ANTI JOIN ", " SEMI JOIN "),
  relations = list(years = export_years, rows = shuffle_rows)
)
