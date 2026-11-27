.nis_design_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
.nis_design_invalid_fields <- stats::setNames(paste0(".nis_bad_", .nis_design_fields), .nis_design_fields)

nis_design_sample <- function(
  data,
  cohort,
  selected,
  quarter_prototype,
  annualize,
  call,
  inspect_quarters = annualize,
  saved = FALSE
) {
  cohort_quo <- nis_design_cohort_expr(cohort, call)
  prepared <- nis_sample_fields(data, cohort_quo)
  quarters <- if (inspect_quarters) quarter_prototype
  summary <- nis_sample_summary(prepared, if (!saved) quarters, call)
  check_transition <- !is.null(quarters) && 2015L %in% summary$years
  collected_fields <- if (check_transition) union(selected, "DQTR") else selected
  collected <- nis_design_collect_cohort(prepared, collected_fields, call)
  if (annualize) {
    if (saved && check_transition) {
      nis_design_2015_warning(summary$years, collected)
    } else {
      nis_sample_annual_warnings(summary, collected)
    }
  }
  list(
    cohort_rows = collected[selected],
    hospital_rows = summary$hospital_rows,
    years = summary$years,
    input_rows = summary$input_rows,
    excluded = summary$excluded,
    coverage = summary$coverage,
    cohort_2015_quarters = if (check_transition) nis_cohort_2015_quarters(collected) else integer()
  )
}

nis_sample_fields <- function(data, cohort_quo) {
  nis_sample_design_fields(dplyr::mutate(data, .nis_cohort = !!cohort_quo))
}

nis_sample_design_fields <- function(data) {
  invalid <- nis_design_invalid_exprs(data)
  any_invalid <- reduce_or(rlang::syms(names(invalid)))
  dplyr::mutate(data, !!!invalid, .nis_valid = !(!!any_invalid))
}

nis_design_invalid_exprs <- function(data) {
  invalid <- lapply(.nis_design_fields, function(field) {
    valid <- nis_is_positive_finite_expr(data, field)
    rlang::expr(!dplyr::coalesce(!!valid, FALSE))
  })
  rlang::set_names(invalid, unname(.nis_design_invalid_fields))
}

nis_sample_summary <- function(prepared, quarter_prototype, call, require_year = FALSE) {
  invalid_year <- rlang::sym(.nis_design_invalid_fields[["YEAR"]])
  keys <- c(".nis_valid", unname(.nis_design_invalid_fields), setdiff(.nis_design_fields, "DISCWT"))
  quarter_flags <- nis_sample_quarter_flags(quarter_prototype)
  # Invalid discharges need only their defect flags and, when valid, their year.
  # Keeping their raw hospital and stratum IDs can make the summary as large as the input.
  design_groups <- prepared |>
    dplyr::mutate(
      YEAR = dplyr::if_else(!(!!invalid_year), YEAR, NA),
      HOSP_NIS = dplyr::if_else(.nis_valid, HOSP_NIS, NA),
      NIS_STRATUM = dplyr::if_else(.nis_valid, NIS_STRATUM, NA)
    ) |>
    nis_sample_group_rows(keys, quarter_flags) |>
    nis_collect()
  excluded <- nis_sample_exclusions(design_groups)
  if (require_year && excluded$by_field[["YEAR"]] > 0L) {
    cli::cli_abort("Annual totals require nonmissing, finite `YEAR` values.", call = call)
  }
  valid <- design_groups$.nis_valid
  hospital_rows <- design_groups[valid, .nis_design_fields]
  if (nrow(hospital_rows) == 0L) {
    cli::cli_abort("No discharges have valid design fields.", call = call)
  }
  stratum_counts <- dplyr::count(hospital_rows, YEAR, HOSP_NIS)
  if (any(stratum_counts$n != 1L)) {
    cli::cli_abort("Each hospital must map to one stratum within a year.", call = call)
  }
  years <- sort(unique(hospital_rows$YEAR))
  coverage <- nis_sample_quarter_coverage(design_groups[valid, ], years, names(quarter_flags))
  input_rows <- sum(as.numeric(design_groups$n))
  list(hospital_rows = hospital_rows, years = years, excluded = excluded, coverage = coverage, input_rows = input_rows)
}

nis_sample_group_rows <- function(prepared, keys, quarter_flags = list()) {
  prepared |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(
      DISCWT = min(dplyr::if_else(.nis_valid, as.double(DISCWT), Inf), na.rm = TRUE),
      n = dplyr::n(),
      !!!quarter_flags,
      .groups = "drop"
    )
}

nis_sample_quarter_flags <- function(prototype) {
  if (is.null(prototype)) {
    return(list())
  }
  flags <- lapply(1:4, function(quarter) {
    matches <- if (is.character(prototype) || is.factor(prototype)) {
      rlang::expr(as.character(DQTR) %in% !!c(as.character(quarter), paste0("Q", quarter)))
    } else {
      rlang::expr(DQTR == !!quarter)
    }
    rlang::expr(any(.nis_valid & dplyr::coalesce(!!matches, FALSE), na.rm = TRUE))
  })
  stats::setNames(flags, paste0(".nis_quarter_", 1:4))
}

nis_sample_quarter_coverage <- function(summary, years, flags) {
  if (!length(flags)) {
    return(NULL)
  }
  lapply(years, function(year) {
    matches <- summary[summary$YEAR == year, flags, drop = FALSE]
    which(vapply(matches, any, logical(1)))
  })
}

nis_sample_exclusions <- function(design_groups) {
  excluded_count <- sum(design_groups$n[!design_groups$.nis_valid])
  excluded_by_field <- vapply(
    .nis_design_invalid_fields,
    function(column) {
      as.integer(sum(design_groups$n[design_groups[[column]]]))
    },
    integer(1)
  )
  year_counts <- design_groups |>
    dplyr::filter(!.nis_valid, !is.na(YEAR)) |>
    dplyr::group_by(YEAR) |>
    dplyr::summarise(n = sum(!!rlang::sym("n")), .groups = "drop") |>
    dplyr::arrange(YEAR)
  excluded <- list(total = excluded_count, by_field = excluded_by_field, by_year = year_counts)
  if (excluded_count > 0L) {
    fields <- names(excluded_by_field)[excluded_by_field > 0L]
    cli::cli_warn(c(
      "Excluded discharges with invalid design fields ({.field {fields}}) before cohort filtering.",
      i = "A discharge can fail more than one field. See the design's `nis_excluded` attribute for the audit."
    ))
  }
  excluded
}

nis_design_cohort_expr <- function(cohort_quo, call) {
  cohort_expr <- rlang::get_expr(cohort_quo)
  if (rlang::is_atomic(cohort_expr) && !is.logical(cohort_expr) && !inherits(cohort_expr, "sql")) {
    cli::cli_abort("`cohort` must evaluate to a logical vector.", call = call)
  }
  cohort_quo
}

nis_design_cohort_type <- function(prepared, call) {
  if (
    inherits(prepared, "tbl_sql") &&
      inherits(dbplyr::remote_con(prepared), "duckdb_connection")
  ) {
    # LIMIT 0 inspects the expression's bound SQL type without reading rows.
    # Collection alone loses the distinction between SQL NULL and typed NA.
    query <- paste0(
      "SELECT typeof((SELECT \".nis_cohort\" FROM (",
      dbplyr::sql_render(prepared),
      ") AS cohort_type LIMIT 0)) AS cohort_type"
    )
    type <- nis_duckdb_translate_errors(
      DBI::dbGetQuery(dbplyr::remote_con(prepared), query)
    )$cohort_type
    if (identical(type, "\"NULL\"")) {
      return(dplyr::mutate(prepared, .nis_cohort = as.logical(!!rlang::sym(".nis_cohort"))))
    }
    logical_cohort <- identical(type, "BOOLEAN")
  } else if (is.data.frame(prepared)) {
    logical_cohort <- is.logical(prepared$.nis_cohort)
  } else {
    return(prepared)
  }
  if (!logical_cohort) {
    cli::cli_abort("`cohort` must evaluate to a logical vector.", call = call)
  }
  prepared
}

nis_design_collect_cohort <- function(prepared, collected_fields, call) {
  prepared <- nis_design_cohort_type(prepared, call)
  # Scan 2 keeps valid discharges whose cohort value is TRUE or missing, so
  # the cohort expression runs once per discharge. Missing values are counted
  # here and dropped.
  collected <- prepared |>
    dplyr::filter(.nis_valid, dplyr::coalesce(.nis_cohort, TRUE)) |>
    dplyr::select(dplyr::all_of(collected_fields), .nis_cohort) |>
    nis_collect()
  if (!is.logical(collected$.nis_cohort)) {
    cli::cli_abort("`cohort` must evaluate to a logical vector.", call = call)
  }
  if (inherits(collected$DISCWT, "integer64")) {
    collected$DISCWT <- as.double(collected$DISCWT)
  }
  missing <- which(is.na(collected$.nis_cohort))
  if (length(missing)) {
    cli::cli_inform("Treated missing cohort values as outside the cohort.")
    collected <- collected[-missing, , drop = FALSE]
  }
  collected
}

nis_sample_annual_warnings <- function(summary, collected) {
  if (!is.null(summary$coverage)) {
    nis_design_quarter_warning(summary$coverage)
    nis_design_2015_warning(summary$years, collected)
  } else if (2015L %in% summary$years) {
    cli::cli_inform(paste0(
      "Cannot check the 2015 ICD-9/ICD-10 split because `DQTR` is ",
      "unavailable; 2015 counts as a whole year in annualization."
    ))
  }
}

nis_design_quarter_warning <- function(quarter_coverage) {
  if (any(lengths(quarter_coverage) < 4L)) {
    cli::cli_warn(c(
      "Annualization includes incomplete quarter coverage in `DQTR`.",
      i = paste0(
        "Partial years count as whole years. Exclude partial years or set ",
        "`annualize = FALSE` and apply a fractional-year factor with `nis_reweight()`."
      )
    ))
  }
}

nis_cohort_2015_quarters <- function(collected) {
  quarters <- collected$DQTR[collected$YEAR == 2015L]
  unique(match(sub("^Q", "", as.character(quarters)), as.character(1:4)))
}

nis_design_2015_warning <- function(design_years, collected) {
  if (2015L %in% design_years) {
    cohort_quarters <- sort(nis_cohort_2015_quarters(collected))
    if (length(cohort_quarters) == 1L && cohort_quarters == 4L) {
      cli::cli_warn(c(
        paste0(
          "The cohort includes only ICD-10-coded 2015 discharges (Q4); ",
          "2015 counts as a whole year in annualization, although the ",
          "cohort covers about one quarter of the year."
        ),
        i = "Exclude 2015 or set `annualize = FALSE` and apply a fractional-year factor with `nis_reweight()`."
      ))
    } else if (length(cohort_quarters) > 0L && all(cohort_quarters %in% 1:3)) {
      cli::cli_warn(c(
        paste0(
          "The cohort includes only ICD-9-coded 2015 discharges (Q1-Q3); ",
          "2015 counts as a whole year in annualization, although the ",
          "cohort covers about three quarters of the year."
        ),
        i = "Exclude 2015 or set `annualize = FALSE` and apply a fractional-year factor with `nis_reweight()`."
      ))
    }
  }
}
