nis_cmrb_inputs <- function(records, slots, keys, fiscal_exemptions) {
  con <- dbplyr::remote_con(records)
  fields <- colnames(records)
  controls <- intersect(c("YEAR", "DQTR", "DXVER", "PRVER"), fields)
  input <- records |>
    dplyr::ungroup() |>
    dplyr::select(dplyr::all_of(unique(c(keys, slots$name, intersect(slots$poa, fields), controls))))
  source <- dbplyr::sql_render(input)
  quoted_keys <- DBI::dbQuoteIdentifier(con, keys)
  eligible <- nis_cmrb_slot_eligibility(con, input, fields, slots)
  dx <- DBI::dbQuoteIdentifier(con, slots$name)
  # Remove ASCII whitespace and decimal separators, as with compact ICD codes.
  code <- paste0(
    "NULLIF(UPPER(TRANSLATE(",
    dx,
    "::VARCHAR, '. ' || CHR(9) || CHR(10) || CHR(11) || CHR(12) || CHR(13), '')), '')"
  )
  code <- ifelse(eligible == "TRUE", code, paste0("CASE WHEN ", eligible, " THEN ", code, " END"))
  poa <- rep("'Y'", nrow(slots))
  has_poa <- which(slots$poa %in% fields)
  quoted_poa <- DBI::dbQuoteIdentifier(con, slots$poa[has_poa])
  poa[has_poa] <- paste0("COALESCE(UPPER(", quoted_poa, "::VARCHAR), '?')")
  i <- seq_len(nrow(slots))
  code_names <- paste0("dx", i)
  poa_names <- paste0("poa", i)
  fiscal <- if (isTRUE(fiscal_exemptions)) nis_cmrb_fiscal_year(fields)
  list(
    query = paste0(
      "SELECT ",
      paste(c(quoted_keys, fiscal, paste(code, "AS", code_names), paste(poa, "AS", poa_names)), collapse = ", "),
      " FROM (",
      source,
      ") AS input"
    ),
    code_names = code_names,
    pairs = paste0("(", code_names, ", ", poa_names, ") AS s", i),
    slot = transform(slots, sql = paste0("'s", i, "'"))
  )
}

nis_cmrb_slot_eligibility <- function(con, input, fields, slots) {
  groups <- unique(slots[c("version", "kind")])
  eligible <- vapply(
    seq_len(nrow(groups)),
    function(i) {
      system <- paste0("icd", groups$version[[i]])
      condition <- code_system_filter(input, fields, groups$kind[[i]], system)
      if (is.null(condition)) {
        return("TRUE")
      }
      as.character(dbplyr::translate_sql(!!condition, con = con))
    },
    character(1)
  )
  group <- match(paste(slots$version, slots$kind), paste(groups$version, groups$kind))
  eligible[group]
}

nis_cmrb_validate_keys <- function(con, input, quoted_keys, keys) {
  missing_key <- paste(quoted_keys, "IS NULL", collapse = " OR ")
  grouped <- paste(quoted_keys, collapse = ", ")
  usable <- paste(input$code_names, "IS NOT NULL", collapse = " OR ")
  stats <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT COALESCE(BOOL_OR(n <> 1 OR missing_key), FALSE) AS invalid, ",
      "COUNT(*) FILTER (WHERE NOT usable)::DOUBLE AS unusable ",
      "FROM (SELECT COUNT(*) AS n, (",
      missing_key,
      ") AS missing_key, ",
      "BOOL_OR(",
      usable,
      ") AS usable FROM (",
      input$query,
      ") AS inputs GROUP BY ",
      grouped,
      ") AS checks"
    )
  )
  if (stats$invalid) {
    cli::cli_abort("Lazy comorbidity scoring requires unique, non-missing discharge keys ({.field {keys}}).")
  }
  stats$unusable
}

nis_cmrb_score_sql <- function(con, input, keys, spec, added) {
  key_list <- paste(keys, collapse = ", ")
  select_keys <- paste0("long.", keys, collapse = ", ")
  aggregate <- nis_cmrb_join_sql(con, input, select_keys, spec)
  base <- nis_cmrb_decode_sql(con, spec)
  decoded <- paste0("SELECT ", paste(c(key_list, base), collapse = ", "), " FROM (", aggregate, ") AS combined")
  conditions <- spec$conditions
  flags <- vapply(
    conditions,
    function(condition) {
      expr <- spec$derived[[condition]]
      if (is.null(expr)) {
        expr <- DBI::dbQuoteIdentifier(con, condition)
      }
      exclude <- unname(spec$exclude[condition])
      if (!is.na(exclude)) {
        expr <- paste0("(", expr, ") AND NOT (", exclude, ")")
      }
      paste0(expr, " AS ", DBI::dbQuoteIdentifier(con, condition))
    },
    character(1)
  )
  hier <- paste0("SELECT ", paste(c(key_list, flags), collapse = ", "), " FROM (", decoded, ") AS decoded")
  output <- nis_cmrb_output_sql(con, spec, added)
  paste0("SELECT ", paste(c(key_list, output), collapse = ", "), " FROM (", hier, ") AS conditions")
}

nis_cmrb_join_sql <- function(con, input, select_keys, spec) {
  lookup <- nis_cmrb_lookup_sql(con, spec$map$values)
  slot <- input$slot
  slot_test <- function(rows) {
    if (!any(rows)) {
      return("FALSE")
    }
    if (all(rows)) {
      return("TRUE")
    }
    paste0("slot IN (", paste(slot$sql[rows], collapse = ", "), ")")
  }
  # Keep principal-only discharges in the left join, but give their
  # principal codes a NULL join key so DuckDB can hash the equality.
  join <- c(
    paste0("(CASE WHEN NOT (", slot_test(slot$principal), ") THEN long.code END) = lookup.code"),
    paste0("lookup.icdv = CASE WHEN ", slot_test(slot$version == 9L), " THEN 9 ELSE 10 END"),
    paste0("lookup.dx = CASE WHEN ", slot_test(slot$kind == "DX"), " THEN 1 ELSE 0 END")
  )
  unpivot <- paste0(
    "SELECT * FROM (",
    input$query,
    ") AS inputs ",
    "UNPIVOT ((code, poa) FOR slot IN (",
    paste(input$pairs, collapse = ", "),
    "))"
  )
  paste0(
    "SELECT ",
    select_keys,
    ", ",
    nis_cmrb_aggregate_sql(spec),
    " FROM (",
    unpivot,
    ") AS long LEFT JOIN (",
    lookup,
    ") AS lookup ON ",
    paste(join, collapse = " AND "),
    " GROUP BY ",
    select_keys
  )
}

nis_cmrb_aggregate_sql <- function(spec) {
  present <- "poa IN ('Y', 'W')"
  absent <- "poa IN ('N', 'U')"
  if (is.null(spec$evidence)) {
    if (isTRUE(spec$fiscal_exemptions)) {
      present <- paste(present, "OR (lookup.fiscal_exempt & (1 << (fiscal_year - 2016))) <> 0")
    }
    return(paste0(
      "COALESCE(BIT_OR(CASE WHEN ",
      present,
      " THEN yes WHEN ",
      absent,
      " THEN no ELSE unknown END), 0) AS flags"
    ))
  }

  # The medicalcoder data.frame path retains the last POA per condition
  # and exemption state after sorting 0, 1, then NA. Keep unknown distinct
  # from N/U so a repeated diagnosis resolves just as it did in R.
  bit_or <- function(column, filter, alias) {
    paste0("COALESCE(BIT_OR(", column, ") ", filter, ", 0) AS ", alias)
  }
  paste(
    c(
      bit_or("observed", "", "seen"),
      bit_or("exempt", "", "exempt"),
      bit_or("nonexempt", paste0("FILTER (WHERE ", present, ")"), "present"),
      bit_or("nonexempt", paste0("FILTER (WHERE ", absent, ")"), "absent"),
      bit_or("nonexempt", paste0("FILTER (WHERE NOT (", present, " OR ", absent, "))"), "unknown")
    ),
    collapse = ", "
  )
}

nis_cmrb_decode_sql <- function(con, spec) {
  bits <- spec$map$bits
  fields <- names(bits)
  term <- function(mask, conditions) {
    value <- sum(bits[conditions], na.rm = TRUE)
    paste0("((", mask, ") & ", sprintf("%.0f", value), "::BIGINT) <> 0")
  }
  methods <- spec$evidence
  if (is.null(methods)) {
    flags <- vapply(fields, function(field) term("flags", field), character(1))
  } else {
    flags <- vapply(
      fields,
      function(field) {
        raw <- c(field, names(methods$always)[methods$always == field])
        from <- unique(c(raw, names(methods$positive)[methods$positive == field]))
        yes <- term("(present & ~unknown) | exempt", from)
        if (field %in% methods$unrestricted) {
          return(paste0("(", yes, " OR ", term("seen", raw), ")"))
        }
        yes
      },
      character(1)
    )
    if ("CBVD_POA" %in% fields) {
      fields <- c(fields, "CBVD_NPOA")
      flags <- c(flags, term("absent & ~(present | unknown)", "CBVD_POA"))
    }
  }
  paste(flags, "AS", DBI::dbQuoteIdentifier(con, fields))
}

nis_cmrb_lookup_sql <- function(con, map) {
  # Codes with identical masks share a constant list in the query.
  version <- substr(map$id, 1L, regexpr(":", map$id) - 1L)
  kind <- substr(map$id, nchar(version) + 2L, nchar(version) + 2L)
  code <- substring(map$id, nchar(version) + 4L)
  columns <- setdiff(names(map), "id")
  masks <- lapply(map[columns], sprintf, fmt = "%.0f")
  group <- do.call(paste, c(list(version, kind), masks, sep = ", "))
  codes <- split(code, group)
  packed <- unname(vapply(codes, paste, character(1), collapse = ","))
  rows <- paste0("(", names(codes), ", ", DBI::dbQuoteString(con, packed), ")")
  paste0(
    "SELECT icdv, dx, ",
    paste(paste0(columns, "::BIGINT AS ", columns), collapse = ", "),
    ", UNNEST(STRING_SPLIT(codes, ',')) AS code FROM (VALUES ",
    paste(rows, collapse = ", "),
    ") AS dictionary(icdv, dx, ",
    paste(columns, collapse = ", "),
    ", codes)"
  )
}

nis_cmrb_output_sql <- function(con, spec, added) {
  weighted_sum <- function(weight) {
    weight <- weight[weight != 0L]
    if (!length(weight)) {
      return("0")
    }
    flag <- DBI::dbQuoteIdentifier(con, names(weight))
    paste(sprintf("%s::INTEGER * %d", flag, weight), collapse = " + ")
  }
  count <- weighted_sum(stats::setNames(rep(1L, length(spec$counted)), spec$counted))
  scores <- vapply(spec$weights, weighted_sum, character(1))
  expr <- c(DBI::dbQuoteIdentifier(con, spec$conditions), count, paste0("(", count, ") > 0"), scores)
  if (!is.null(spec$distinct)) {
    distinct <- vapply(
      spec$distinct,
      function(outputs) {
        flags <- DBI::dbQuoteIdentifier(con, outputs)
        paste0("(", paste(flags, collapse = " OR "), ")::INTEGER")
      },
      character(1)
    )
    expr <- c(expr, paste(c("0", distinct), collapse = " + "))
  }
  paste(expr, "AS", DBI::dbQuoteIdentifier(con, added))
}

nis_cmrb_fiscal_year <- function(fields) {
  year <- if ("YEAR" %in% fields) 'TRY_CAST("YEAR" AS INTEGER)' else "NULL"
  quarter <- if ("DQTR" %in% fields) 'CASE WHEN "DQTR" = 4 THEN 1 ELSE 0 END' else "0"
  paste0("LEAST(2027, GREATEST(2016, COALESCE(", year, " + ", quarter, ", 2027))) AS fiscal_year")
}
