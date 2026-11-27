domain_rows <- function() {
  masks <- fixture(
    a = c(FALSE, TRUE, NA),
    b = c(FALSE, TRUE, NA),
    c = c(FALSE, TRUE, NA),
    d = c(FALSE, TRUE, NA),
    draws = 16L
  )
  rows <- data.frame(
    id = seq_len(nrow(masks) * 4L),
    YEAR = rep(2020L + masks$id, each = 4L),
    DQTR = rep(1:4, nrow(masks)),
    HOSP_NIS = rep(c(1L, 1L, 2L, 2L), nrow(masks)),
    NIS_STRATUM = 1L,
    DISCWT = rep(c(1, 4, 8, 2), nrow(masks)),
    keep = as.vector(t(as.matrix(masks[1:4])))
  )
  random <- rows$YEAR > 2020L + 3L^4
  rows$DISCWT[random] <- runif(sum(random), 0.25, 100)
  rows$outcome <- rep(c(NA, 1, -2, 4), nrow(masks))
  rows
}

variance <- function(scores, strata) {
  sum(vapply(
    split(scores, strata),
    function(x) {
      n <- length(x)
      n / (n - 1) * sum((x - mean(x))^2)
    },
    double(1)
  ))
}

outside_domain <- function(case) {
  expanded <- case
  extra <- case$rows[rep(1L, 2L), ]
  extra$id <- max(case$rows$id) + 1:2
  extra$keep <- c(FALSE, NA)
  extra$outcome <- c(-500, 1000)
  extra$DISCWT <- 25
  expanded$rows <- rbind(case$rows, extra)
  list(left = list(expanded), right = list(case))
}

annual_cases <- function(con) list(case(domain_rows()))

annual_sql <- function(con, rows, args) {
  as.data.frame(easyNIS::nis_annual_totals(duck_table(con, rows), keep))
}

annual_reference <- function(rows, args) {
  outputs <- lapply(split(rows, rows$YEAR), function(x) {
    active <- x$keep %in% TRUE
    totals <- tapply(ifelse(active, x$DISCWT, 0), x$HOSP_NIS, sum)
    data.frame(
      YEAR = x$YEAR[1L],
      discharges = if (any(active)) sum(totals) else NA_real_,
      discharges_se = if (any(active)) sqrt(variance(totals, rep(1L, length(totals)))) else NA_real_,
      n = sum(active),
      hospitals = length(unique(x$HOSP_NIS[active]))
    )
  })
  do.call(rbind, outputs)
}

register(
  "annual-totals",
  annual_cases,
  annual_sql,
  annual_reference,
  mutation("trends.R", "nis_annual_cells_sql", "ELSE 0.0", "ELSE 1.0"),
  relations = list(years = split_years, domain = outside_domain, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[1L]]
    x$rows <- x$rows[x$rows$YEAR %in% c(2021L, 2022L, 2023L), ]
    x
  },
  approximate = c("discharges", "discharges_se")
)

survey_cases <- function(con) {
  all <- domain_rows()
  # Make each enumerated mask a grouping level while keeping two sampled PSUs.
  all$group <- all$YEAR
  all$YEAR <- 2020L
  all$HOSP_NIS <- as.integer(all$HOSP_NIS + 2L * (all$group - 2021L))
  all$NIS_STRATUM <- all$group
  configs <- grid(statistic = c("mean", "total"), na_rm = c(TRUE, FALSE), grouped = c(TRUE, FALSE))
  batches <- lapply(seq_len(nrow(configs)), function(i) case(all, as.list(configs[i, ])))
  lonely <- data.frame(
    id = 1:5,
    YEAR = 2020L,
    HOSP_NIS = 1:5,
    NIS_STRATUM = c(1L, 2L, 2L, 3L, 3L),
    DISCWT = c(1, 3, 5, 2, 4),
    keep = c(TRUE, TRUE, FALSE, NA, FALSE),
    outcome = runif(5L, -2, 5)
  )
  c(
    batches,
    lapply(c(FALSE, TRUE), function(domain_adjust) {
      case(
        lonely,
        list(statistic = "total", na_rm = TRUE, grouped = FALSE, adjust = TRUE, domain_adjust = domain_adjust)
      )
    })
  )
}

survey_result <- function(value, se, group = NA_integer_) {
  data.frame(group = as.integer(group), estimate = as.double(value), se = as.double(se))
}

with_survey_design <- function(con, rows, run) {
  opts <- options(easyNIS.duckdb_config = list(threads = 1L))
  on.exit(options(opts))
  path <- tempfile("invented-nis-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  # Use the normal lazy-design entry point on invented annual Parquet.
  names(rows) <- toupper(names(rows))
  DBI::dbWriteTable(con, "survey_fixture", rows, overwrite = TRUE, temporary = TRUE)
  file <- file.path(path, "NIS_2020.parquet")
  DBI::dbExecute(con, paste("COPY survey_fixture TO", DBI::dbQuoteString(con, file), "(FORMAT PARQUET)"))
  query <- easyNIS::nis_open(path, check_release = FALSE)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(query), shutdown = TRUE), add = TRUE, after = FALSE)
  run(dplyr::filter(easyNIS::nis_survey(query), KEEP))
}

survey_sql <- function(con, rows, args) {
  if (isTRUE(args$adjust)) {
    opts <- options(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = args$domain_adjust)
    on.exit(options(opts))
  }
  with_survey_design(con, rows, function(design) {
    fn <- if (args$statistic == "mean") survey::svymean else survey::svytotal
    if (args$grouped) {
      result <- survey::svyby(~OUTCOME, ~GROUP, design, fn, na.rm = args$na_rm, keep.names = FALSE)
      return(survey_result(result$OUTCOME, survey::SE(result), result$GROUP))
    }
    result <- fn(~OUTCOME, design, na.rm = args$na_rm)
    survey_result(stats::coef(result), survey::SE(result))
  })
}

survey_reference <- function(rows, args) {
  active <- rows$keep %in% TRUE
  groups <- if (args$grouped) sort(unique(rows$group[active])) else NA_integer_
  if (!args$na_rm && anyNA(rows$outcome[active])) {
    design <- survey::svydesign(~HOSP_NIS, strata = ~NIS_STRATUM, weights = ~DISCWT, data = rows, nest = TRUE)
  }
  outputs <- lapply(groups, function(g) {
    domain <- active
    if (args$grouped) {
      domain <- domain & rows$group == g
    }
    usable <- domain & !is.na(rows$outcome)
    if (!any(usable) && args$na_rm) {
      return(survey_result(0, 0, g))
    }
    if (!args$na_rm && any(domain & !usable)) {
      fn <- if (args$statistic == "mean") survey::svymean else survey::svytotal
      reference <- fn(~outcome, subset(design, domain), na.rm = FALSE)
      return(survey_result(stats::coef(reference), survey::SE(reference), g))
    }
    estimate <- sum(rows$outcome[usable] * rows$DISCWT[usable])
    score <- numeric(nrow(rows))
    score[usable] <- rows$outcome[usable] * rows$DISCWT[usable]
    if (args$statistic == "mean") {
      weight <- sum(rows$DISCWT[usable])
      estimate <- estimate / weight
      score[usable] <- (rows$outcome[usable] - estimate) * rows$DISCWT[usable] / weight
    }
    psu <- tapply(score, list(rows$HOSP_NIS), sum)
    strata <- rows$NIS_STRATUM[match(as.integer(names(psu)), rows$HOSP_NIS)]
    var <- if (isTRUE(args$adjust)) {
      active_psus <- unique(rows$HOSP_NIS[usable])
      sampled_strata <- unique(rows$NIS_STRATUM[usable])
      grand <- sum(psu) / sum(strata %in% sampled_strata)
      sum(vapply(
        sampled_strata,
        function(h) {
          scores <- psu[strata == h]
          n <- length(scores)
          m <- sum(as.integer(names(scores)) %in% active_psus)
          center <- if (m == 1L && (n == 1L || args$domain_adjust)) grand else mean(scores)
          sum((scores - center)^2) * if (n == 1L) 1 else n / (n - 1L)
        },
        double(1)
      ))
    } else {
      variance(psu, strata)
    }
    survey_result(estimate, sqrt(var), g)
  })
  do.call(rbind, outputs)
}

survey_relation_case <- function(cases) {
  x <- cases[[1L]]
  x$rows <- x$rows[x$rows$group %in% 2023:2025, ]
  x$args$grouped <- FALSE
  x
}

survey_mutation <- mutation("lazy-survey-stat.R", "nis_survey_aggregate", 'c("inside",', 'c("TRUE",')
register(
  "survey-aggregate",
  survey_cases,
  survey_sql,
  survey_reference,
  survey_mutation,
  relations = list(domain = outside_domain, rows = shuffle_rows),
  relation_case = survey_relation_case,
  relation_mutations = list(domain = survey_mutation),
  approximate = c("estimate", "se")
)

glm_cases <- function(con) {
  lapply(c("quasibinomial", "poisson"), function(family) {
    outcome <- if (family == "poisson") 0:2 else 0:1
    rows <- fixture(
      YEAR = 2020L,
      NIS_STRATUM = 1:2,
      HOSP_NIS = 1:3,
      x = -1:1,
      outcome = outcome,
      DISCWT = c(1, 2, 4),
      copy = 1:4,
      draws = 160L
    )
    rows$HOSP_NIS <- as.integer(rows$HOSP_NIS + 3L * (rows$NIS_STRATUM - 1L))
    rows$keep <- TRUE
    rows$keep[seq(3L, nrow(rows), by = 11L)] <- FALSE
    rows$outcome[seq(5L, nrow(rows), by = 31L)] <- NA_integer_
    case(rows, list(family = family))
  })
}

glm_result <- function(fit) {
  data.frame(
    term = names(stats::coef(fit)),
    estimate = as.double(stats::coef(fit)),
    se = as.double(survey::SE(fit)),
    deviance = as.double(fit$deviance)
  )
}

glm_sql <- function(con, rows, args) {
  with_survey_design(con, rows, function(design) {
    family <- get(args$family, asNamespace("stats"))()
    form <- OUTCOME ~ X
    input <- internal("nis_survey_model_input")(form, design, family, TRUE)
    if (!input$group_rows) {
      stop("Fixture did not enter grouped-row IRLS")
    }
    glm_result(survey::svyglm(
      form,
      design,
      family = family,
      rescale = TRUE,
      control = stats::glm.control(epsilon = 1e-13)
    ))
  })
}

glm_reference <- function(rows, args) {
  names(rows) <- toupper(names(rows))
  design <- survey::svydesign(
    ~HOSP_NIS,
    strata = ~NIS_STRATUM,
    weights = ~DISCWT,
    data = rows,
    nest = TRUE
  )
  design <- subset(design, KEEP)
  family <- get(args$family, asNamespace("stats"))()
  glm_result(survey::svyglm(
    OUTCOME ~ X,
    design,
    family = family,
    rescale = TRUE,
    control = stats::glm.control(epsilon = 1e-13)
  ))
}

register(
  "survey-irls",
  glm_cases,
  glm_sql,
  glm_reference,
  mutation("lazy-survey-glm.R", "nis_survey_irls", "fsum(w) AS w", "avg(w) AS w"),
  relations = list(domain = outside_domain, rows = shuffle_rows),
  approximate = c("estimate", "se", "deviance")
)
