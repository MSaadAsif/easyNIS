nis_code_stem <- function(type, system) {
  paste0(if (system == "icd10") "I10_", type)
}

nis_code_slots <- function(columns, stem, canonical = TRUE) {
  suffix <- if (canonical) "[1-9][0-9]*" else "[0-9]+"
  names <- grep(paste0("^", stem, suffix, "$"), columns, value = TRUE)
  stats::setNames(substring(names, nchar(stem) + 1L), names)
}

nis_diagnosis_fields <- function(data) {
  columns <- nis_names(data)
  slots <- c(nis_code_slots(columns, "I10_DX", canonical = FALSE), nis_code_slots(columns, "DXPOA", canonical = FALSE))
  intersect(columns, names(slots))
}

nis_flag_slot_names <- function(data_names, slots, system, position) {
  stem <- nis_code_stem(slots, system)
  slot_names <- names(nis_code_slots(data_names, stem))
  principal <- paste0(stem, "1")
  if (position == "principal") {
    slot_names <- slot_names[slot_names == principal]
  } else if (position == "secondary") {
    slot_names <- slot_names[slot_names != principal]
  }
  if (length(slot_names) == 0L) {
    cli::cli_abort(paste(
      "No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} {slots} columns",
      "({stem}<n>) match the requested position.",
      "Slot suffixes must be positive integers without leading zeros."
    ))
  }
  slot_names
}

code_system_year <- function(data) {
  if (inherits(data, "tbl_sql")) {
    # DuckDB folds typeof() at bind time. Keep decimal fractions exact
    # instead of rounding a high-precision calendar year to DOUBLE.
    return(dbplyr::sql(paste(
      "(CASE WHEN typeof(\"YEAR\") = 'VARCHAR' OR starts_with(typeof(\"YEAR\"), 'ENUM(')",
      "THEN CASE WHEN regexp_full_match(CAST(\"YEAR\" AS VARCHAR), '[0-9]+')",
      "THEN TRY_CAST(CAST(\"YEAR\" AS VARCHAR) AS INTEGER) END",
      "WHEN starts_with(typeof(\"YEAR\"), 'DECIMAL(')",
      "AND regexp_matches(CAST(\"YEAR\" AS VARCHAR), '[.][0-9]*[1-9]') THEN NULL",
      "WHEN typeof(\"YEAR\") IN ('FLOAT', 'DOUBLE')",
      "AND (NOT isfinite(TRY_CAST(\"YEAR\" AS DOUBLE))",
      "OR TRY_CAST(\"YEAR\" AS DOUBLE) <> floor(TRY_CAST(\"YEAR\" AS DOUBLE))) THEN NULL",
      "ELSE TRY_CAST(\"YEAR\" AS DOUBLE) END)"
    )))
  }
  rlang::expr(code_system_year_value(YEAR))
}

code_system_year_value <- function(year) {
  if (is.factor(year)) {
    year <- as.character(year)
  }
  if (is.character(year)) {
    year[!grepl("^[0-9]+\\z", year, perl = TRUE)] <- NA_character_
    return(suppressWarnings(as.integer(year)))
  }
  if (!is.numeric(year) || is.complex(year)) {
    return(rep(NA_real_, length(year)))
  }
  replace(year, !is.finite(year) | year != floor(year), NA)
}

code_system_year_range <- function(data, columns, system) {
  year <- code_system_year(data)
  icd9 <- system == "icd9"
  cutoff <- 2015L
  if ("DQTR" %in% columns) {
    quarters <- if (icd9) 1:3 else 4L
    missing_quarter <- nis_is_missing_expr(data, "DQTR")
    other_year <- if (icd9) 2014L else 2016L
    cutoff <- rlang::expr(dplyr::case_when(
      (!!missing_quarter | DQTR %in% !!quarters) ~ 2015L,
      .default = !!other_year
    ))
  }
  if (icd9) {
    return(rlang::expr(dplyr::between(!!year, 2012L, !!cutoff)))
  }
  rlang::expr(!!year >= !!cutoff)
}

code_system_filter <- function(data, columns, slots, system) {
  conditions <- list()
  version_name <- paste0(slots, "VER")
  version <- if (system == "icd9") 9L else 10L
  if (version_name %in% columns) {
    field <- rlang::sym(version_name)
    missing_version <- nis_is_missing_expr(data, version_name)
    conditions <- c(
      conditions,
      list(rlang::expr(
        !!missing_version | !!field == !!version
      ))
    )
  }
  if ("YEAR" %in% columns) {
    missing_year <- nis_is_missing_expr(data, "YEAR")
    year_range <- code_system_year_range(data, columns, system)
    conditions <- c(
      conditions,
      list(rlang::expr(
        !!missing_year | dplyr::coalesce(!!year_range, FALSE)
      ))
    )
  }
  if (length(conditions) == 0L) {
    return(NULL)
  }
  Reduce(nis_gate_expr, conditions)
}

nis_in_code_system <- function(value, eligibility) {
  if (is.null(eligibility)) value else nis_gate_expr(eligibility, value)
}
