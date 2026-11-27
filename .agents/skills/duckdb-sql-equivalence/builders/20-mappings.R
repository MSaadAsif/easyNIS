ccsr_cases <- function(con) {
  configs <- subset(
    grid(
      type = c("dx", "pr"),
      position = c("any", "principal", "default"),
      pinned = c(FALSE, TRUE),
      filter = c("none", "single", "multiple")
    ),
    type == "dx" | position != "default"
  )
  raw <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT * FROM read_parquet(",
      DBI::dbQuoteString(con, "inst/ccsr/map.parquet"),
      ")"
    )
  )
  cases <- lapply(seq_len(nrow(configs)), function(i) {
    args <- as.list(configs[i, ])
    codes <- if (args$type == "dx") c("E119", "E1165", "I509", "Z370") else c("02703ZZ", "02L73DK")
    args$map <- raw[raw$type == args$type & raw$code %in% codes, ]
    available <- sort(unique(args$map$category))
    args$categories <- switch(args$filter, single = available[1L], multiple = available)
    slots <- c(codes, NA, "", "ZZZZZZZ", tolower(codes[1L]))
    rows <- fixture(
      one = slots,
      two = slots,
      YEAR = c(2014, 2015, 2016, 2024, 2025, 2026, NA, 2015.5),
      DQTR = c(1L, 2L, 3L, 4L, NA, 5L),
      version = c(9L, 10L, NA)
    )
    type <- toupper(args$type)
    names(rows)[1:2] <- slot_names(type, "icd10")
    names(rows)[names(rows) == "version"] <- paste0(type, "VER")
    rows[[paste0(type, "1")]] <- codes[1L]
    case(rows, args)
  })
  wide <- which(configs$position == "any" & !configs$pinned & configs$filter == "multiple")
  c(
    cases,
    lapply(cases[wide], function(x) {
      rows <- utils::tail(x$rows, 128L)
      width <- if (x$args$type == "dx") 40L else 25L
      codes <- c(unique(x$args$map$code), NA, "", "ZZZZZZZ")
      for (slot in 3:width) {
        name <- paste0("I10_", toupper(x$args$type), slot)
        rows[[name]] <- sample(codes, nrow(rows), replace = TRUE)
      }
      case(rows, x$args)
    })
  )
}

ccsr_sql <- function(con, rows, args) {
  query <- easyNIS::nis_add_ccsr(
    duck_table(con, rows),
    type = args$type,
    position = args$position,
    version = if (args$pinned) "2025.1",
    categories = args$categories,
    name = "result"
  )
  pull_columns(query, c("id", "result"))
}

ccsr_reference <- function(rows, args) {
  type <- toupper(args$type)
  y <- rows$YEAR
  q <- rows$DQTR
  v <- rows[[paste0(type, "VER")]]
  covered <- !is.na(y) &
    y == floor(y) &
    y >= 2015 &
    (y != 2015 | is.na(q) | q == 4L) &
    (is.na(v) | v == 10L) &
    (y < 2025 | (args$pinned & y == 2025 & q %in% 1:3))
  map <- args$map
  if (!is.null(args$categories)) {
    map <- map[map$category %in% args$categories, ]
  }
  default <- args$position == "default"
  if (default) {
    map <- map[map$inpatient %in% "Y", ]
  }
  mapping <- split(map$category, map$code)
  prefix <- paste0("I10_", type)
  slots <- if (args$position == "any") {
    rows[grepl(paste0("^", prefix, "[1-9][0-9]*$"), names(rows))]
  } else {
    rows[paste0(prefix, "1")]
  }
  lookup <- function(i) {
    if (!covered[i]) {
      return(if (default) NA_character_ else NULL)
    }
    codes <- as.character(slots[i, ])
    hits <- sort(unique(as.character(unlist(mapping[codes], use.names = FALSE))))
    if (default) hits[1L] else hits
  }
  indices <- order(rows$id)
  out <- data.frame(id = rows$id[indices])
  out$result <- if (default) vapply(indices, lookup, character(1)) else lapply(indices, lookup)
  out
}

mapping_slot_relation <- function(case) {
  swapped <- case
  swapped$rows <- slot_swap(case$rows, paste0("I10_", toupper(case$args$type)))
  list(left = list(swapped), right = list(case))
}

ccsr_relation_case <- function(cases) {
  x <- Filter(
    function(x) {
      x$args$type == "dx" && x$args$position == "any" && x$args$filter == "multiple"
    },
    cases
  )[[1L]]
  x$rows <- x$rows[c(1L, 2L, 3L), ]
  x$rows$YEAR <- c(2020, 2020, 2026)
  x$rows$I10_DX1 <- c("E119", "I509", NA)
  x$rows$I10_DX2 <- c(NA, "E119", NA)
  x$rows$DXVER <- 10L
  x
}

register(
  "ccsr",
  ccsr_cases,
  ccsr_sql,
  ccsr_reference,
  mutation("ccsr-query.R", "ccsr_presence_sql", "list_has_any(", "list_has_all("),
  relations = list(slots = mapping_slot_relation, years = split_years, rows = shuffle_rows),
  relation_case = ccsr_relation_case,
  relation_mutations = list(
    slots = mutation(
      "ccsr-query.R",
      "ccsr_presence_sql",
      "dbQuoteIdentifier(con, slots)",
      "dbQuoteIdentifier(con, slots[1L])"
    ),
    years = mutation(
      "ccsr-query.R",
      "ccsr_query_sql",
      "dbplyr::sql_render(data)",
      "paste0('SELECT * REPLACE (max(YEAR) OVER () AS YEAR) FROM (', dbplyr::sql_render(data), ')')"
    ),
    rows = mutation(
      "ccsr-query.R",
      "ccsr_query_sql",
      "dbplyr::sql_render(data)",
      "paste0('SELECT * REPLACE (first_value(I10_DX1) OVER () AS I10_DX1) FROM (', dbplyr::sql_render(data), ')')"
    )
  )
)

comorbidity_cases <- function(con) {
  codes <- utils::read.csv("inst/extdata/elixhauser-2027-codes.csv")
  weights <- utils::read.csv("inst/extdata/elixhauser-2027-weights.csv")
  groups <- c("DIAB_UNCX", "DIAB_CX", "CBVD_POA", "CBVD_SQLA", "ANEMDEF")
  chosen <- unique(c(
    vapply(groups, function(x) codes$code[codes$condition == x][1L], character(1)),
    codes$code[codes$exempt_versions > 0L][1L]
  ))
  raw <- c(chosen, " e11.9 ", "ZZZZZZZ", NA, "")
  rows <- fixture(
    I10_DX1 = c("E119", "!", NA),
    I10_DX2 = raw,
    I10_DX3 = raw,
    DXPOA2 = c("Y", "W", "N", "U", NA),
    DXPOA3 = c("Y", "W", "N", "U", NA),
    YEAR = c(2015L, 2016L, 2026L, 2027L),
    DQTR = c(3L, 4L, NA),
    DXVER = c(9L, 10L, NA)
  )
  rows$KEY_NIS <- rows$id
  list(case(rows, list(codes = codes[codes$code %in% c(chosen, "E119"), ], weights = weights)))
}

comorbidity_sql <- function(con, rows, args) {
  query <- easyNIS::nis_comorbidity(duck_table(con, rows), method = "elixhauser_ahrq2027")
  names <- c("id", grep("^cmrb_", colnames(query), value = TRUE))
  result <- pull_columns(query, names)
  numeric <- c("cmrb_n", "cmrb_mortality_index", "cmrb_readmission_index")
  result[numeric] <- lapply(result[numeric], as.integer)
  result
}

comorbidity_reference <- function(rows, args) {
  code <- lapply(rows[paste0("I10_DX", 1:3)], function(x) toupper(gsub("[.[:space:]]", "", x)))
  era <- eligible(rows, "icd10", "DX")
  fiscal <- pmax(2016L, pmin(2027L, rows$YEAR + (rows$DQTR %in% 4L)))
  usable <- era & Reduce(`|`, lapply(code, function(x) !is.na(x) & nzchar(x)))
  conditions <- c(as.character(args$weights$condition), "CBVD_POA", "CBVD_SQLA", "CBVD_NPOA")
  flags <- as.data.frame(setNames(rep(list(rep(FALSE, nrow(rows))), length(conditions)), conditions))
  for (j in 2:3) {
    idx <- match(code[[j]], args$codes$code)
    poa <- rows[[paste0("DXPOA", j)]]
    code_condition <- args$codes$condition[idx]
    exemption <- (args$codes$exempt_versions[idx] %/% 2^(fiscal - 2016L)) %% 2 == 1
    present <- poa %in% c("Y", "W") | (!is.na(exemption) & exemption)
    absent <- poa %in% c("N", "U") & !present
    for (condition in conditions) {
      unrestricted <- condition %in% args$weights$condition[args$weights$requires_poa == 0L]
      matched <- !is.na(code_condition) & code_condition == condition
      hit <- if (condition == "CBVD_NPOA") {
        !is.na(code_condition) & code_condition == "CBVD_POA" & absent
      } else {
        matched & (unrestricted | present)
      }
      flags[[condition]] <- flags[[condition]] | (era & hit)
    }
  }
  flags$CBVD <- with(flags, CBVD_POA | (CBVD_SQLA & !CBVD_NPOA))
  flags$DIAB_UNCX <- with(flags, DIAB_UNCX & !DIAB_CX)
  flags$HTN_UNCX <- with(flags, HTN_UNCX & !HTN_CX)
  flags$CANCER_SOLID <- with(flags, CANCER_SOLID & !CANCER_METS)
  flags$CANCER_NSITU <- with(flags, CANCER_NSITU & !(CANCER_METS | CANCER_SOLID))
  flags$LIVER_MLD <- with(flags, LIVER_MLD & !LIVER_SEV)
  flags$RENLFL_MOD <- with(flags, RENLFL_MOD & !RENLFL_SEV)
  flags <- flags[args$weights$condition]
  flags[!usable, ] <- NA
  n <- as.integer(rowSums(flags))
  scores <- as.matrix(flags) %*% as.matrix(args$weights[c("mortality_index", "readmission_index")])
  names(flags) <- paste0("cmrb_", tolower(names(flags)))
  out <- cbind(
    data.frame(id = rows$id),
    flags,
    cmrb_n = n,
    cmrb_any = n > 0L,
    cmrb_mortality_index = as.integer(scores[, 1L]),
    cmrb_readmission_index = as.integer(scores[, 2L])
  )
  out[order(rows$id), ]
}

comorbidity_slot_relation <- function(case) {
  swapped <- case
  swapped$rows <- slot_swap(case$rows, c("I10_DX", "DXPOA"), 2:3)
  list(left = list(swapped), right = list(case))
}

register(
  "comorbidity",
  comorbidity_cases,
  comorbidity_sql,
  comorbidity_reference,
  mutation("comorbidity-sql.R", "nis_cmrb_aggregate_sql", "poa IN ('Y', 'W')", "poa = 'Y'"),
  relations = list(slots = comorbidity_slot_relation, years = split_years, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[1L]]
    x$rows <- x$rows[sample.int(nrow(x$rows), 300L), ]
    x
  }
)
