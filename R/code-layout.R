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

code_system_valid_year <- function(data) {
  schema <- if (inherits(data, "tbl_sql")) {
    nis_collect(utils::head(dplyr::select(data, dplyr::all_of("YEAR")), 0L))
  } else {
    data
  }
  if (!is.numeric(schema$YEAR)) {
    return(rlang::expr(TRUE))
  }
  finite_year <- nis_is_finite_expr(data, "YEAR") # nolint: object_usage_linter
  rlang::expr(!!finite_year & YEAR == floor(YEAR)) # nolint: object_usage_linter
}

code_system_filter <- function(data, columns, slots, system) {
  conditions <- list()
  version_name <- paste0(slots, "VER")
  version <- if (system == "icd9") 9L else 10L
  if (version_name %in% columns) {
    field <- rlang::sym(version_name)
    missing_version <- nis_is_missing_expr(data, version_name) # nolint: object_usage_linter
    conditions <- c(
      conditions,
      list(rlang::expr(
        !!missing_version | !!field == !!version
      ))
    )
  }
  if ("YEAR" %in% columns) {
    missing_year <- nis_is_missing_expr(data, "YEAR") # nolint: object_usage_linter
    valid_year <- code_system_valid_year(data)
    year_range <- if (system == "icd9") {
      rlang::expr(YEAR >= 2012L & YEAR <= 2015L)
    } else {
      rlang::expr(YEAR >= 2015L)
    }
    conditions <- c(
      conditions,
      list(rlang::expr(
        !!missing_year | (!!valid_year & !!year_range)
      ))
    )
    if ("DQTR" %in% columns) {
      quarters <- if (system == "icd9") 1:3 else 4L
      quarter <- rlang::sym("DQTR")
      missing_quarter <- nis_is_missing_expr(data, "DQTR") # nolint: object_usage_linter
      conditions <- c(
        conditions,
        list(rlang::expr(
          !!missing_year | YEAR != 2015L | !!missing_quarter | !!quarter %in% !!quarters
        ))
      )
    }
  }
  if (length(conditions) == 0L) {
    return(NULL)
  }
  Reduce(nis_and_expr, conditions) # nolint: object_usage_linter
}

nis_in_code_system <- function(value, eligibility) {
  if (is.null(eligibility)) value else nis_and_expr(eligibility, value)
}
