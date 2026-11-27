eligible <- function(rows, system, type) {
  y <- rows$YEAR
  q <- rows$DQTR
  version <- rows[[paste0(type, "VER")]]
  era <- if (system == "icd9") y >= 2012 & y <= 2015 else y >= 2015
  quarter <- if (system == "icd9") 1:3 else 4L
  (is.na(version) | version == if (system == "icd9") 9 else 10) &
    (is.na(y) | (is.finite(y) & y == floor(y) & era)) &
    (is.na(y) | y != 2015 | is.na(q) | q %in% quarter)
}

slot_names <- function(type, system, width = 2L) {
  paste0(if (system == "icd10") "I10_" else "", type, seq_len(width))
}

systems <- function(system) if (system == "both") c("icd9", "icd10") else system

mixed_rule <- function(rule, system) {
  if (system == "both") list(icd9 = rule, icd10 = rule) else rule
}

slot_swap <- function(rows, stems, positions = c(1L, 2L)) {
  for (stem in stems) {
    fields <- paste0(stem, positions)
    rows[fields] <- rows[rev(fields)]
  }
  rows
}

flag_cases <- function(con) {
  configs <- grid(system = c("icd9", "icd10", "both"), position = c("any", "principal", "secondary"))
  lapply(seq_len(nrow(configs)), function(i) {
    rows <- fixture(
      DX1 = c(NA, "A0", "B9", "RX", "Q"),
      DX2 = c(NA, "A0", "B9", "RX", "Q"),
      I10_DX1 = c(NA, "A0", "B9", "RX", "Q"),
      I10_DX2 = c(NA, "A0", "B9", "RX", "Q"),
      YEAR = c(2011, 2014, 2015, 2016, NA, NaN, Inf, 2015.5),
      DQTR = c(1L, 2L, 3L, 4L, NA, 5L),
      DXVER = c(9, 10, 0, NA, NaN)
    )
    case(rows, as.list(configs[i, ]))
  })
}

flag_sql <- function(con, rows, args) {
  rule <- mixed_rule(list(prefix = c("A", "B"), regex = "R.", exclude = "B9"), args$system)
  pull_columns(
    easyNIS::nis_flag_dx(
      duck_table(con, rows),
      result = rule,
      position = args$position,
      system = args$system
    ),
    c("id", "result")
  )
}

flag_reference <- function(rows, args) {
  result <- rep(FALSE, nrow(rows))
  for (system in systems(args$system)) {
    indices <- switch(args$position, any = 1:2, principal = 1L, secondary = 2L)
    matches <- lapply(rows[slot_names("DX", system)[indices]], function(code) {
      !is.na(code) & (startsWith(code, "A") | startsWith(code, "B") | grepl("^R.$", code)) & code != "B9"
    })
    result <- result | (eligible(rows, system, "DX") & Reduce(`|`, matches))
  }
  data.frame(id = rows$id, result = result)[order(rows$id), ]
}

flag_slot_relation <- function(case) {
  at_position <- function(position, swap) {
    x <- case
    if (swap) {
      x$rows <- slot_swap(x$rows, c("DX", "I10_DX"))
    }
    x$args$position <- position
    x
  }
  list(
    left = list(at_position("any", TRUE), at_position("principal", TRUE), at_position("secondary", TRUE)),
    right = list(at_position("any", FALSE), at_position("secondary", FALSE), at_position("principal", FALSE))
  )
}

register(
  "code-flags",
  flag_cases,
  flag_sql,
  flag_reference,
  mutation("code-flags.R", "nis_code_match", "reduce_or(per_slot)", "per_slot[[1L]]"),
  relations = list(slots = flag_slot_relation, years = split_years, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[1L]]
    x$rows <- x$rows[sample.int(nrow(x$rows), 500L), ]
    x
  },
  relation_mutations = list(
    slots = mutation(
      "code-flags.R",
      "nis_code_match",
      "reduce_or(per_slot)",
      "per_slot[[1L]]"
    )
  )
)

timing_cases <- function(con) {
  configs <- grid(
    missing_day = c("exclude", "assume_same_day", "indeterminate"),
    relation = c("on_or_after", "after", "before", "same_day", "within_days"),
    system = c("icd9", "icd10", "both")
  )
  rows <- fixture(
    PR1 = c(NA, "I", "O"),
    PR2 = c(NA, "I", "O"),
    I10_PR1 = c(NA, "I", "O"),
    I10_PR2 = c(NA, "I", "O"),
    PRDAY1 = c(NA, "n/a", "-9", "0", ".5", "1", "Inf", "NaN"),
    PRDAY2 = c(NA, "n/a", "-9", "0", ".5", "1", "Inf", "NaN")
  )
  # Cross every two-slot configuration with the transition and both sides.
  rows <- merge(rows, grid(YEAR = c(2014L, 2015L, 2016L), DQTR = c(3L, 4L, NA), PRVER = c(9L, 10L, NA)))
  rows$id <- seq_len(nrow(rows))
  draws <- lapply(seq_len(nrow(configs)), function(i) case(rows, c(as.list(configs[i, ]), list(width = 2L))))
  rows <- fixture(
    YEAR = 2020L,
    DQTR = 1L,
    PRVER = 10L,
    I10_PR1 = c("I", "O"),
    I10_PR2 = c(NA, "I", "O"),
    I10_PR3 = c(NA, "I", "O"),
    PRDAY1 = c(NA, 0, 1, 2),
    PRDAY2 = c(NA, 0, 1, 2)
  )
  args <- list(missing_day = "indeterminate", relation = "within_days", system = "icd10", width = 3L)
  wide <- data.frame(id = seq_len(512L), YEAR = 2020L, DQTR = 1L, PRVER = 10L)
  for (i in seq_len(25L)) {
    wide[[paste0("I10_PR", i)]] <- sample(c(NA, "I", "O", "X"), nrow(wide), replace = TRUE, prob = c(60, 4, 4, 32))
    wide[[paste0("PRDAY", i)]] <- sample(c(NA, -6, 0, 1, 2, 99, Inf), nrow(wide), replace = TRUE)
  }
  c(draws, list(case(rows, args), case(wide, modifyList(args, list(width = 25L)))))
}

timing_sql <- function(con, rows, args) {
  q <- easyNIS::nis_flag_pr_timing(
    duck_table(con, rows),
    mixed_rule("I", args$system),
    mixed_rule("O", args$system),
    name = "result",
    system = args$system,
    relation = args$relation,
    missing_day = args$missing_day,
    window = if (args$relation == "within_days") 1L
  )
  pull_columns(q, c("id", "result"))
}

timing_reference <- function(rows, args) {
  day <- lapply(seq_len(args$width), function(slot) {
    raw <- rows[[paste0("PRDAY", slot)]]
    x <- if (is.null(raw)) rep(NA_real_, nrow(rows)) else suppressWarnings(as.numeric(raw))
    x[!is.finite(x) | x < 0] <- if (args$missing_day == "assume_same_day") 0 else NA_real_
    x
  })
  days <- do.call(cbind, day)
  result <- rep(FALSE, nrow(rows))
  for (system in systems(args$system)) {
    code <- as.matrix(rows[slot_names("PR", system, args$width)])
    index <- !is.na(code) & code == "I"
    outcome <- !is.na(code) & code == "O"
    ref <- days
    ref[!index] <- NA_real_
    delta <- days - do.call(pmin, c(as.data.frame(ref), na.rm = TRUE))
    match <- switch(
      args$relation,
      on_or_after = delta >= 0,
      after = delta > 0,
      before = delta < 0,
      same_day = delta == 0,
      within_days = delta >= 0 & delta <= 1
    )
    hit <- rowSums(outcome & match, na.rm = TRUE) > 0L
    if (args$missing_day == "indeterminate") {
      uncertain <- rowSums(index) > 0 & rowSums(outcome) > 0 & rowSums((index | outcome) & is.na(days)) > 0
      hit[!hit & uncertain] <- NA
    }
    result <- result | (eligible(rows, system, "PR") & hit)
  }
  data.frame(id = rows$id, result = result)[order(rows$id), ]
}

timing_slot_relation <- function(case) {
  stems <- c(if ("PR1" %in% names(case$rows)) "PR", "I10_PR", "PRDAY")
  swapped <- case
  swapped$rows <- slot_swap(case$rows, stems)
  list(left = list(swapped), right = list(case))
}

register(
  "prday-timing",
  timing_cases,
  timing_sql,
  timing_reference,
  mutation("procedure-days.R", "nis_decode_procedure_day", " AS DOUBLE)", " AS BIGINT)"),
  relations = list(slots = timing_slot_relation, years = split_years, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[45L]]
    x$rows <- x$rows[sample.int(nrow(x$rows), 500L), ]
    x
  }
)

audit_cases <- function(con) {
  rows <- fixture(
    I10_DX1 = c(NA, "A0", "A1", "B0", "Q"),
    I10_DX2 = c(NA, "A0", "A1", "B0", "Q"),
    YEAR = 2019:2020,
    DISCWT = c(NA, 1, 4)
  )
  list(case(rows))
}

audit_order <- function(rows) rows[order(rows$id, rows$code), ]

audit_sql <- function(con, rows, args) {
  query <- internal(".nis_audit_lazy_codes")(
    duck_table(con, rows),
    c("I10_DX1", "I10_DX2"),
    c("A", "B"),
    list(code = "code", weight = "weight"),
    "DISCWT",
    c("id", "YEAR")
  )
  audit_order(as.data.frame(dplyr::collect(query)))
}

audit_reference <- function(rows, args) {
  codes <- lapply(seq_len(nrow(rows)), function(i) {
    observed <- unique(c(rows$I10_DX1[i], rows$I10_DX2[i]))
    observed[!is.na(observed) & grepl("^[AB]", observed)]
  })
  i <- rep(seq_len(nrow(rows)), lengths(codes))
  audit_order(data.frame(
    id = rows$id[i],
    YEAR = rows$YEAR[i],
    weight = rows$DISCWT[i],
    code = unlist(codes, use.names = FALSE)
  ))
}

audit_slots <- function(case) {
  swapped <- case
  swapped$rows <- slot_swap(case$rows, "I10_DX")
  list(left = list(swapped), right = list(case))
}

register(
  "code-inventory",
  audit_cases,
  audit_sql,
  audit_reference,
  mutation(
    "code-audit.R",
    ".nis_audit_lazy_codes",
    "UNNEST(list_filter(list_distinct([",
    "UNNEST(list_filter(list_sort(["
  ),
  relations = list(slots = audit_slots, years = split_years, rows = shuffle_rows)
)
