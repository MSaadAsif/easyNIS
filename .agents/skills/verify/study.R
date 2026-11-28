study_verification_packages <- function(journey) {
  if (!journey %in% c("study", "study-ci", "study-small", "study-reporting", "study-support")) {
    return(character())
  }
  packages <- c("broom.helpers", "cardx", "ggplot2", "gt", "gtsummary", "knitr", "purrr", "rmarkdown", "survey", "xml2")
  if (journey %in% c("study-ci", "study-support")) c(packages, "flextable") else packages
}

drive_study <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html")
}

drive_study_small <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html", small_cohort = TRUE)
  cases <- list(
    flow_one_hospital = list(sizes = rep(144L, 2L), flow_one_hospital = TRUE, setup = 'cohort <- rlang::expr(FALSE)'),
    missing_exposure = list(sizes = rep(144L, 2L), missing_exposure = TRUE, setup = 'exposure <- "not_kept"'),
    missing_arm = list(sizes = rep(144L, 2L), setup = 'study_design$variables$exposed[seq_len(5L)] <- NA'),
    unused_arm = list(
      sizes = rep(144L, 2L),
      setup = paste0(
        'study_design$variables$exposed <- factor(study_design$variables$exposed, ',
        'levels = c("FALSE", "TRUE", "Unused"))'
      )
    ),
    masked_p = list(
      sizes = rep(144L, 2L),
      masked_p = TRUE,
      setup = c(
        'study_design$variables$exposed[seq_len(24L)] <- NA',
        'arm <- which(study_design$variables$exposed)',
        'female <- seq_len(nrow(study_design$variables)) %% 2L == 0L',
        'female[arm] <- seq_along(arm) <= 5L',
        'study_design$variables$FEMALE <- factor(ifelse(female, "A", "B"))'
      )
    ),
    one_year = list(sizes = c(10L, 11L, 144L), masks = "\u226410"),
    two_years = list(sizes = c(1L, 3L, 144L), masks = rep("\u226410", 2L)),
    one_hospital = list(sizes = c(12L, 144L), masks = "<2 hospitals"),
    small_arm = list(sizes = rep(144L, 2L), small_arm = TRUE),
    supported = list(sizes = rep(144L, 2L), supported = TRUE)
  )
  for (name in names(cases)) {
    directory <- file.path(scratch, name)
    results <- file.path(evidence, name)
    stopifnot(dir.create(directory), dir.create(results))
    case <- cases[[name]]
    fixture <- study_disclosure_fixture(directory, case, one_hospital = name == "one_hospital")
    verify_study(directory, results, "html", fixture$input, disclosure_case = c(case, fixture[c("years", "weights")]))
  }
}

drive_study_support <- function(scratch, evidence) {
  cases <- list(
    missing_died = "DIED",
    missing_los = "LOS",
    mixed_invalid = "DISCWT",
    observed_los = "observed_los",
    rare_annual_arm = "exposure",
    absent_annual_arm = "absent_exposure"
  )
  for (name in names(cases)) {
    run <- file.path(scratch, name)
    proof <- file.path(evidence, name)
    stopifnot(dir.create(run), dir.create(proof))
    case <- list(sizes = rep(144L, 2L), support_case = cases[[name]])
    fixture <- study_disclosure_fixture(run, case, one_hospital = FALSE)
    verify_study(run, proof, c("html", "docx"), fixture$input, disclosure_case = c(case, fixture["years"]))
  }
}

drive_study_reporting <- function(scratch, evidence) {
  verify_study_inputs(scratch, evidence)
  for (variant in c(
    "domain",
    "prefiltered",
    "small-exclusion",
    "uppercase",
    "dichotomous",
    "shared-denominator",
    "one-year-denominator",
    "unweighted"
  )) {
    run <- file.path(scratch, variant)
    proof <- file.path(evidence, variant)
    stopifnot(dir.create(run), dir.create(proof))
    verify_study(run, proof, "html", reporting_variant = variant)
  }
}

verify_study_inputs <- function(scratch, evidence) {
  years <- 2015:2016
  opened <- easyNIS::nis_open(easyNIS::nis_example(years), years = years)
  check <- function(data, cohort, source = opened) {
    design <- easyNIS::nis_design(data, {{ cohort }}, keep = c(DQTR, AGE), annualize = TRUE)
    easyNIS:::nis_study_reporting(source, design, years)
  }
  missing <- dplyr::mutate(opened, DQTR = dplyr::if_else(YEAR == 2015L, NA_integer_, DQTR))
  reports <- list(
    q4 = check(opened, YEAR == 2016L | DQTR == 4L),
    zero_cohort_year = check(opened, YEAR == 2016L),
    invalid_year = check(dplyr::mutate(opened, DISCWT = dplyr::if_else(YEAR == 2015L, 0, DISCWT)), TRUE),
    missing_quarter = check(missing, TRUE, source = missing)
  )

  more_inputs <- file.path(scratch, "annual-release")
  stopifnot(dir.create(more_inputs))
  con <- easyNIS:::nis_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  fixture <- dplyr::collect(opened |> dplyr::select(YEAR, DQTR, HOSP_NIS, NIS_STRATUM, DISCWT, AGE))
  easyNIS:::nis_duckdb_write_parquet(fixture[FALSE, ], file.path(more_inputs, "NIS_2015.parquet"), con)
  easyNIS:::nis_duckdb_write_parquet(fixture[fixture$YEAR == 2016L, ], file.path(more_inputs, "NIS_2016.parquet"), con)
  writeLines(
    unname(tools::md5sum(list.files(more_inputs, full.names = TRUE))),
    file.path(evidence, "annual-release-hashes.txt")
  )
  empty <- suppressWarnings(easyNIS::nis_open(more_inputs, years = years))
  reports$empty_year <- check(empty, TRUE, source = empty)
  stopifnot(
    all(!vapply(reports[1:3], function(report) report$full_years, logical(1))),
    !reports$empty_year$full_years,
    identical(reports$empty_year$years, 2016L),
    identical(reports$invalid_year$years, 2016L),
    isTRUE(reports$missing_quarter$coding$unknown),
    identical(easyNIS:::nis_open_source_info(opened)$release, "non-release"),
    identical(easyNIS:::nis_open_source_info(empty)$release, "mismatch")
  )

  extract_path <- file.path(scratch, "extract")
  stopifnot(dir.create(extract_path))
  DBI::dbExecute(
    con,
    paste0(
      "COPY (SELECT * FROM read_parquet(",
      DBI::dbQuoteString(con, file.path(more_inputs, "NIS_2016.parquet")),
      ") WHERE AGE >= 30) TO ",
      DBI::dbQuoteString(con, file.path(extract_path, "NIS_2016.parquet"))
    )
  )
  extract <- suppressWarnings(easyNIS::nis_open(extract_path, years = 2016L))
  stopifnot(identical(easyNIS:::nis_open_source_info(extract)$release, "mismatch"))
  reports$extract <- check(extract, TRUE, source = extract)
  stopifnot(identical(easyNIS:::nis_study_release_status(reports$extract$release)[[1L]], "Needs attention"))

  design <- easyNIS::nis_design(opened, YEAR == 2016L, keep = DQTR, annualize = TRUE)
  reweighted <- easyNIS::nis_reweight(design, rep(2, nrow(design$variables)))
  reports$reweighted <- easyNIS:::nis_study_reporting(opened, reweighted, years)
  stopifnot(
    identical(reports$reweighted$years, years),
    identical(reports$reweighted$cohort, "YEAR == 2016L"),
    isTRUE(reports$reweighted$reweighted),
    !reports$reweighted$design$weighted
  )
  dput(reports, file = file.path(evidence, "study-input-receipts.R"))
}

drive_study_ci <- function(scratch, evidence) {
  input <- normalizePath(easyNIS::nis_example(), winslash = "/", mustWork = TRUE)
  session_tmp <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(input), session_tmp))
  on.exit({
    if (dir.exists(input) && identical(normalizePath(input, winslash = "/", mustWork = TRUE), input)) {
      unlink(input, recursive = TRUE)
    }
    stopifnot(!dir.exists(input))
  })
  verify_study(scratch, evidence, c("html", "docx"), input)
}

study_fixture_expectations <- function(input, evidence) {
  files <- list.files(input, pattern = "[.]parquet$", full.names = TRUE, recursive = TRUE)
  stopifnot(length(files) > 0L)
  hashes <- tools::md5sum(files)
  relative <- substring(files, nchar(input) + 2L)
  writeLines(paste(unname(hashes), relative), file.path(evidence, "study-input-hashes.txt"))

  query <- easyNIS::nis_open(input)
  records <- dplyr::collect(dplyr::select(query, AGE, DISCWT, I10_DX1))
  rm(query)
  gc()
  principal <- startsWith(records$I10_DX1, "I50")
  cohort <- records$AGE >= 50
  stopifnot(any(cohort & !principal), any(!cohort))
  groups <- list(rep(TRUE, nrow(records)), principal, cohort, cohort)
  data.frame(
    step = c(
      "All discharges",
      "Principal diagnosis prefix",
      "Cohort definition",
      "Analysis cohort (valid survey design)"
    ),
    discharges = vapply(groups, sum, integer(1)),
    weighted_discharges = vapply(groups, function(included) sum(records$DISCWT[included]), numeric(1))
  )
}

study_disclosure_fixture <- function(scratch, case, one_hospital) {
  input <- file.path(scratch, "fixture")
  stopifnot(dir.create(input))
  years <- seq.int(2017L, length.out = length(case$sizes))
  weights <- numeric(length(years))
  con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = "1")))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (i in seq_along(years)) {
    position <- seq_len(case$sizes[[i]])
    hospital <- if (one_hospital && i == 1L) rep(1L, length(position)) else (position - 1L) %% 12L + 1L
    exposed <- if (isTRUE(case$small_arm)) i == 1L & position <= 3L else position %% 5L < 2L
    principal <- rep("I5022", length(position))
    if (isTRUE(case$flow_one_hospital)) {
      matching <- i == 1L & position <= 15L
      hospital[matching] <- 1L
      principal[!matching] <- "E119"
    }
    records <- data.frame(
      YEAR = years[[i]],
      HOSP_NIS = hospital,
      NIS_STRATUM = (hospital - 1L) %/% 4L + 1L,
      DISCWT = 101.25 + 13 * i,
      CCR_NIS = 0.3,
      TOTCHG = 2000 + 17 * position + position %% 7L,
      LOS = 1L + (position * 7L + i) %% 19L,
      DIED = as.integer(position %% 7L < 3L),
      AGE = 41L + position %% 37L,
      FEMALE = position %% 3L == 0L,
      I10_DX1 = principal,
      I10_DX2 = ifelse(exposed, "Z515", "E119")
    )
    if (isTRUE(case$support_case %in% c("exposure", "absent_exposure"))) {
      records$DISCWT <- 5 * i
      sizes <- if (case$support_case == "exposure") c(3L, 50L) else c(0L, 50L)
      records$I10_DX2 <- ifelse(position <= sizes[[i]], "Z515", "E119")
    } else if (length(case$support_case)) {
      records$DISCWT <- 5
      if (i == 2L) {
        if (case$support_case == "DISCWT") {
          records$DISCWT[1:15] <- NA_real_
          records$NIS_STRATUM[16:18] <- 0L
        } else if (case$support_case == "observed_los") {
          records$LOS[1:72] <- NA_real_
        } else {
          records[[case$support_case]][1:3] <- NA
        }
      }
    }
    weights[[i]] <- sum(records$DISCWT)
    destination <- file.path(input, sprintf("NIS_%d.parquet", years[[i]]))
    easyNIS:::nis_duckdb_write_parquet(records, destination, con)
  }
  list(input = input, years = years, weights = weights)
}

verify_study <- function(
  scratch,
  evidence,
  formats,
  input = NULL,
  small_cohort = FALSE,
  disclosure_case = NULL,
  reporting_variant = NULL
) {
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) {
    stop("Quarto must be on PATH to drive the study feature.")
  }
  version <- system2(quarto, "--version", stdout = TRUE)
  if (!length(version) || !is.null(attr(version, "status"))) {
    stop("Quarto version check failed.")
  }
  cat("QUARTO ", version, "\n", sep = "")
  path <- easyNIS::nis_new_study(file.path(scratch, "study"))
  scaffold_files <- c("_quarto.yml", "analysis.qmd", ".gitignore")
  stopifnot(all(file.exists(file.path(path, scaffold_files))))
  writeLines(list.files(path, all.files = TRUE, no.. = TRUE), file.path(evidence, "scaffold.txt"))

  expected <- NULL
  cohort_code <- NULL
  if (!is.null(input) && is.null(disclosure_case)) {
    expected <- study_fixture_expectations(input, evidence)
    cohort_code <- "dplyr::if_else(AGE >= 50, TRUE, NA)"
  } else if (small_cohort) {
    cohort_code <- "YEAR == 2017L & HOSP_NIS == 1L & AGE == 28"
  }
  if (!is.null(cohort_code) || !is.null(disclosure_case)) {
    analysis <- file.path(path, "analysis.qmd")
    definition <- readLines(analysis, encoding = "UTF-8")
    if (!is.null(cohort_code)) {
      cohort_line <- grepl("^cohort <- ", definition)
      stopifnot(sum(cohort_line) == 1L)
      definition[cohort_line] <- paste0("cohort <- rlang::expr(", cohort_code, ")")
    }
    if (!is.null(disclosure_case)) {
      definition[grepl("^  years:", definition)] <-
        paste0("  years: [", paste(disclosure_case$years, collapse = ", "), "]")
      if (isTRUE(disclosure_case$supported)) {
        summary <- which(definition == "#| label: design-summary")
        stopifnot(length(summary) == 1L)
        definition <- append(
          definition,
          c(
            'outcomes <- dplyr::add_row(outcomes, outcome = "TOTCHG", family = "gaussian", exponentiate = FALSE)',
            'outcomes <- dplyr::add_row(outcomes, outcome = "not_kept_outcome", family = "gaussian", exponentiate = FALSE)',
            ""
          ),
          after = summary
        )
      }
      setup <- disclosure_case$setup
      if (isTRUE(disclosure_case$flow_one_hospital) || isTRUE(disclosure_case$missing_exposure)) {
        field <- if (isTRUE(disclosure_case$flow_one_hospital)) "cohort" else "exposure"
        line <- grep(paste0("^", field, " <- "), definition)
        stopifnot(length(line) == 1L)
        definition[line] <- setup
      } else if (length(setup)) {
        line <- which(definition == "#| label: design-summary")
        stopifnot(length(line) == 1L)
        definition <- append(definition, setup, after = line)
      }
      if (!isTRUE(disclosure_case$flow_one_hospital)) {
        definition <- c(
          definition,
          "",
          "```{r}",
          "#| include: false",
          'dput(trend_long, file = "trend-plot-data.R")',
          "```"
        )
      }
    }
    writeLines(enc2utf8(definition), analysis, useBytes = TRUE)
  }
  stopifnot(all(file.copy(file.path(path, scaffold_files), evidence)))
  if (!is.null(reporting_variant)) {
    analysis <- file.path(path, "analysis.qmd")
    definition <- readLines(analysis, encoding = "UTF-8")
    definition[grepl("^  years:", definition)] <- "  years: [2019, 2020]"
    definition[definition == "annualize <- FALSE"] <- "annualize <- TRUE"
    if (reporting_variant == "uppercase") {
      definition[grepl("^  years:", definition)] <- "  years: [2022]"
    }
    if (reporting_variant == "shared-denominator") {
      definition[grepl("^  years:", definition)] <- "  years: [2017, 2018, 2019, 2020, 2021, 2022]"
    }
    if (reporting_variant == "one-year-denominator") {
      definition[grepl("^  years:", definition)] <- "  years: [2022]"
      definition[grepl("^cohort <- ", definition)] <- "cohort <- rlang::expr(AGE >= 18)"
    }
    denominator_case <- reporting_variant %in% c("shared-denominator", "one-year-denominator")
    if (denominator_case || reporting_variant %in% c("dichotomous", "unweighted")) {
      line <- which(definition == "#| label: design-summary")
      stopifnot(length(line) == 1L)
      setup <- switch(
        reporting_variant,
        dichotomous = c(
          'records <- study_design$variables',
          'records$exposed <- seq_len(nrow(records)) %% 5L < 2L',
          'arm <- which(records$exposed)',
          'records$FEMALE <- seq_len(nrow(records)) %% 2L == 1L',
          'records$FEMALE[arm] <- TRUE',
          'records$FEMALE[arm[[1L]]] <- FALSE',
          'study_design$variables <- records'
        ),
        `shared-denominator` = c(
          'records <- study_design$variables',
          'records$exposed[seq_len(24L)] <- NA',
          'records$DIED <- seq_len(nrow(records)) %% 2L == 1L',
          'records$DIED[seq_len(24L)] <- FALSE',
          'records$DIED[1L] <- TRUE',
          'study_design$variables <- records'
        ),
        `one-year-denominator` = c(
          'records <- study_design$variables',
          'i <- seq_len(nrow(records))',
          'records$exposed <- i %% 2L == 1L',
          'records$exposed[seq_len(24L)] <- NA',
          'records$DIED <- i %% 5L < 2L',
          'records$DIED[seq_len(24L)] <- FALSE',
          'records$DIED[seq_len(3L)] <- TRUE',
          'records$LOS[seq_len(24L)] <- NA_real_',
          'records$LOS[1:2] <- 200',
          'study_design$variables <- records'
        ),
        unweighted = character()
      )
      definition <- append(definition, setup, after = line)
      if (reporting_variant == "unweighted") {
        line <- which(definition == "valid_models <- which(vapply(model_results, function(result) {")
        stopifnot(length(line) == 1L)
        definition <- append(
          definition,
          c(
            'model_results[[2L]] <- list(model = stats::glm(LOS ~ AGE, data = records))'
          ),
          after = line - 1L
        )
      }
      if (denominator_case) {
        definition <- c(
          definition,
          "",
          "```{r}",
          "#| include: false",
          'fixture <- study_design$variables',
          'dput(list(fixture = fixture[, c("YEAR", "HOSP_NIS", "DISCWT", "exposed", "DIED", "LOS")],',
          '  models = lapply(model_results[valid_models], function(result) stats::nobs(result$model)),',
          '  chart = trend_long), file = "denominator-evidence.R")',
          "```"
        )
      }
    }
    if (reporting_variant == "prefiltered") {
      line <- grep("^# Quarto can put chunk options", definition)
      stopifnot(length(line) == 1L)
      definition <- append(definition, "nis_data <- dplyr::filter(nis_data, AGE >= 30)", after = line - 1L)
    }
    if (reporting_variant == "small-exclusion") {
      line <- grep("^cohort <- ", definition)
      stopifnot(length(line) == 1L)
      definition[line] <- paste0(
        "cohort <- rlang::expr(",
        "principal_dx & !(YEAR == 2019L & HOSP_NIS == 1L & AGE == 28))"
      )
    }
    writeLines(enc2utf8(definition), analysis, useBytes = TRUE)
    stopifnot(file.copy(analysis, evidence, overwrite = TRUE))
  }

  if (any(formats %in% c("html", "docx"))) {
    analysis <- file.path(path, "analysis.qmd")
    definition <- readLines(analysis, encoding = "UTF-8")
    definition <- c(
      definition,
      "",
      "```{r}",
      "#| include: false",
      'source_rows <- nis_data |> dplyr::transmute(YEAR, HOSP_NIS, NIS_STRATUM, DISCWT,',
      '  principal = principal_dx, cohort = !!cohort) |> dplyr::collect()',
      'dput(list(rows = analysis_design$variables, source = source_rows, exposure = exposure,',
      '  restricted = exposure_restricted, summary = lapply(list(table_one, outcome_table), function(x) x$table_body$variable),',
      '  models = lapply(model_results[valid_models], function(x) list(formula = stats::formula(x$model),',
      '    family = stats::family(x$model)$family)),',
      '  chart = if (exists("trend_long")) as.data.frame(trend_long[c("YEAR", "measure", "n")])),',
      '  file = "support-input.R")',
      "```"
    )
    writeLines(enc2utf8(definition), analysis, useBytes = TRUE)
    stopifnot(file.copy(analysis, evidence, overwrite = TRUE))
  }

  original <- getwd()
  on.exit(setwd(original))
  setwd(path)
  Sys.setenv(QUARTO_R = R.home("bin"), R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (format in formats) {
    report <- render_study(quarto, format, input, evidence)
    validate_study_report(report, format, input, expected, evidence, small_cohort)
    verify_study_cell_support(report, format, evidence, disclosure_case)
    if (format == "html" && !is.null(disclosure_case) && is.null(disclosure_case$support_case)) {
      verify_study_disclosure(report, disclosure_case)
    }
    if (!is.null(reporting_variant)) verify_study_reporting(report, reporting_variant, evidence)
  }
}

render_study <- function(quarto, format, input, evidence) {
  render_log <- file.path(evidence, paste0("render-", format, ".txt"))
  args <- c("render", "analysis.qmd", "--to", format)
  if (!is.null(input)) {
    args <- c(args, "-P", shQuote(paste0("data_path:", input)))
  }
  cat("RENDER ", paste(c(shQuote(quarto), args), collapse = " "), "\n", sep = "")
  status <- system2(quarto, args, stdout = render_log, stderr = render_log)
  if (status != 0L) {
    stop("Quarto render failed. Read ", basename(render_log), ".")
  }
  report <- file.path("docs", paste0("analysis.", format))
  stopifnot(file.exists(report), file.info(report)$size > 0L, file.copy(report, evidence))
  report
}

validate_study_report <- function(report, format, input, expected, evidence, small_cohort = FALSE) {
  sections <- c(
    "Study definitions",
    "Methods",
    "Cohort flow",
    "Table 1",
    "Outcomes",
    "Trends by year",
    "Multivariable models"
  )
  if (format == "html") {
    document <- xml2::read_html(report)
    headings <- xml2::xml_text(xml2::xml_find_all(document, "//main//h1 | //main//h2"), trim = TRUE)
    stopifnot(all(c("National Inpatient Sample Study", sections) %in% headings))
    outline <- xml2::xml_text(xml2::xml_find_all(document, "//nav[@id='TOC']//a"), trim = TRUE)
    stopifnot(all(sections %in% outline))
    body <- xml2::xml_text(xml2::xml_find_first(document, "//main"))
    stopifnot(!grepl("library(easyNIS)", body, fixed = TRUE))
    if (small_cohort) {
      methods <- xml2::xml_text(xml2::xml_find_first(document, "//section[@id='methods']"))
      methods <- gsub("[[:space:]]+", " ", methods)
      stopifnot(!grepl("contains.*discharges|includes.*hospitals", methods))
    }
    validate_study_flow(document, expected, evidence, small_cohort)
    if (small_cohort) {
      for (id in c("table-1", "outcomes", "multivariable-models")) {
        section <- study_report_section(document, id)
        stopifnot(
          !length(xml2::xml_find_all(section, ".//table")),
          grepl("under the study disclosure policy", xml2::xml_text(section), fixed = TRUE)
        )
      }
    }
    assets <- xml2::xml_text(xml2::xml_find_all(
      document,
      "//script/@src | //img/@src | //link[@rel='stylesheet']/@href"
    ))
    stopifnot(all(grepl("^(data:|https?://|#)", assets)))
    cache_values <- xml2::xml_text(xml2::xml_find_all(document, "//@data-cache.extra"))
    stopifnot(all(grepl("^[0-9a-f]{32}$", cache_values)))
    if (!is.null(input)) {
      html <- readLines(report, warn = FALSE, encoding = "UTF-8")
      stopifnot(!any(grepl(basename(input), html, fixed = TRUE)))
    }
  } else {
    xml <- utils::unzip(report, files = "word/document.xml", exdir = "word-proof")
    document <- xml2::read_xml(xml)
    body <- paste(xml2::xml_text(xml2::xml_find_all(document, "//*[local-name()='t']")), collapse = " ")
    stopifnot(all(vapply(
      c("National Inpatient Sample Study", sections),
      function(section) grepl(section, body, fixed = TRUE),
      logical(1)
    )))
  }
  stopifnot(
    grepl("unweighted discharges are masked", body, fixed = TRUE),
    grepl("HCUP Data Use Agreement", body, fixed = TRUE),
    grepl("experimental pending", body, fixed = TRUE)
  )
  cat("RENDER PASS ", format, " ", file.info(report)$size, " bytes\n", sep = "")
}

verify_study_reporting <- function(report, variant, evidence) {
  document <- xml2::read_html(report)
  methods <- xml2::xml_text(study_report_section(document, "methods"))
  methods <- gsub("[[:space:]]+", " ", methods)
  criterion <- if (variant == "small-exclusion") {
    "principal_dx & !(YEAR == 2019L & HOSP_NIS == 1L & AGE == 28)"
  } else if (variant == "one-year-denominator") {
    "AGE >= 18"
  } else {
    "principal_dx & AGE >= 18"
  }
  period <- switch(
    variant,
    uppercase = c("2022", "divided by 1"),
    `shared-denominator` = c("2017, 2018, 2019, 2020, 2021, 2022", "divided by 6"),
    `one-year-denominator` = c("2022", "divided by 1"),
    c("2019, 2020", "divided by 2")
  )
  expected <- c(
    period,
    criterion,
    "DISCWT",
    "with-replacement",
    "unweighted N",
    "HOSP_NIS",
    "NIS_STRATUM",
    "Taylor linearization",
    "ICD-10-CM/PCS",
    "DuckDB",
    "survey"
  )
  stopifnot(all(vapply(expected, grepl, logical(1), x = methods, fixed = TRUE)))
  domain <- xml2::xml_text(xml2::xml_find_first(
    document,
    "//section[@id='checklist-receipt']//tr[td[normalize-space(.)='Survey domain']]"
  ))
  prefilter <- variant == "prefiltered"
  stopifnot(grepl(if (prefilter) "Needs attention" else "Pass", domain, fixed = TRUE))
  stopifnot(
    grepl("could not verify that the design input retained the opened sample", methods, fixed = TRUE) == prefilter
  )
  receipt_status <- function(practice) {
    row <- sprintf("//section[@id='checklist-receipt']//tr[td[normalize-space(.)='%s']]/td[2]", practice)
    xml2::xml_text(xml2::xml_find_first(document, row))
  }
  if (variant %in% c("domain", "uppercase")) {
    stopifnot(
      identical(receipt_status("Annualization of partial years"), "Pass"),
      identical(receipt_status("National weights"), "Pass"),
      identical(receipt_status("Inpatient stays as the unit of analysis"), "Analyst review")
    )
  }
  if (variant == "dichotomous") {
    table <- study_report_section(document, "table-1")
    cells <- xml2::xml_text(xml2::xml_find_all(
      table,
      ".//tr[td[@headers='label' and starts-with(normalize-space(.),'Female')]]/td[starts-with(@headers,'stat_')]"
    ))
    stopifnot(length(cells) == 3L, all(cells %in% c("Masked", "\u226410", "<2 hospitals")))
  }
  if (variant %in% c("shared-denominator", "one-year-denominator")) {
    verify_study_denominator(document, variant, evidence)
  }
  if (variant == "unweighted") {
    for (practice in c("National weights", "Sampling design", "Standard errors and hospital nesting")) {
      stopifnot(identical(receipt_status(practice), "Needs attention"))
    }
  }
  if (variant == "small-exclusion") {
    flow <- study_report_section(document, "cohort-flow")
    counts <- xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr/td[position() > 1]"), trim = TRUE)
    stopifnot(length(counts) == 8L, all(counts == "Masked"))
  }
}

verify_study_denominator <- function(document, variant, evidence) {
  stopifnot(file.copy("denominator-evidence.R", evidence))
  proof <- dget("denominator-evidence.R")
  missing <- is.na(proof$fixture$exposed)
  stopifnot(sum(missing) == 24L, sum(proof$fixture$DIED[missing]) == if (variant == "one-year-denominator") 3L else 1L)
  selected <- proof$fixture[!missing, ]
  n <- nrow(selected)
  headings <- function(id) xml2::xml_text(xml2::xml_find_all(study_report_section(document, id), ".//thead//th"))
  arms_ok <- all(vapply(split(selected, selected$YEAR), study_audit_levels, logical(1), variable = "exposed"))
  table_one_headings <- headings("table-1")
  stopifnot(
    if (arms_ok) any(grepl(paste0("N = ", n), table_one_headings, fixed = TRUE)) else !length(table_one_headings),
    any(grepl(paste0("N = ", n), headings("outcomes"), fixed = TRUE)),
    grepl("DIED", xml2::xml_text(study_report_section(document, "outcomes")), fixed = TRUE)
  )
  cells <- function(id) {
    rows <- xml2::xml_find_all(study_report_section(document, id), ".//tbody/tr")
    do.call(
      rbind,
      lapply(rows, function(row) {
        xml2::xml_text(xml2::xml_find_all(row, "./td"), trim = TRUE)
      })
    )
  }
  flow <- cells("cohort-flow")
  stopifnot(
    nrow(flow) == 1L,
    as.integer(flow[1L, 2L]) == n,
    flow[1L, 3L] == formatC(sum(selected$DISCWT), format = "f", digits = 1, big.mark = ",")
  )
  trends <- cells("trends-by-year")
  annual <- split(selected, selected$YEAR)
  stopifnot(setequal(trends[, 1L], names(annual)), sum(as.integer(trends[, 2L])) == n)
  for (rows in annual) {
    year <- rows$YEAR[[1L]]
    observed <- trends[trends[, 1L] == year, ]
    mortality <- stats::weighted.mean(rows$DIED, rows$DISCWT)
    los <- stats::weighted.mean(rows$LOS, rows$DISCWT, na.rm = TRUE)
    stopifnot(
      as.integer(observed[[2L]]) == nrow(rows),
      observed[[3L]] == formatC(sum(rows$DISCWT) / length(annual), format = "f", digits = 1, big.mark = ","),
      observed[[4L]] == paste0(formatC(100 * mortality, format = "f", digits = 1), "%"),
      observed[[5L]] == formatC(los, format = "f", digits = 2),
      isTRUE(all.equal(proof$chart$estimate[proof$chart$YEAR == year], c(mortality, los), check.attributes = FALSE))
    )
  }
  model_tables <- xml2::xml_find_all(study_report_section(document, "multivariable-models"), ".//table")
  if (variant == "one-year-denominator") {
    stopifnot(length(model_tables) > 0L, length(proof$models) > 0L)
  }
  stopifnot(all(unlist(proof$models) == n))
}

validate_study_flow <- function(document, expected, evidence, small_cohort) {
  rows <- xml2::xml_find_all(document, "//section[@id='cohort-flow']//tbody/tr")
  cells <- lapply(rows, function(row) xml2::xml_text(xml2::xml_find_all(row, "./td"), trim = TRUE))
  result <- do.call(rbind, cells)
  if (identical(dim(result), c(1L, 3L))) {
    stopifnot(is.null(expected), !small_cohort, result[1L, 1L] == "Analysis cohort (observed exposure)")
    return(invisible(NULL))
  }
  stopifnot(identical(dim(result), c(4L, 3L)))
  if (small_cohort) {
    stopifnot(all(result[3:4, 2:3] == "\u226410"))
  }
  if (is.null(expected)) {
    return(invisible(NULL))
  }

  parse_number <- function(value) as.numeric(gsub(",", "", value, fixed = TRUE))
  observed <- data.frame(
    step = result[, 1L],
    discharges = parse_number(result[, 2L]),
    weighted_discharges = parse_number(result[, 3L])
  )
  dput(list(expected = expected, observed = observed), file = file.path(evidence, "study-flow.R"))
  stopifnot(
    identical(observed$step, expected$step),
    all(observed$discharges == expected$discharges),
    isTRUE(all.equal(observed$weighted_discharges, expected$weighted_discharges))
  )
}

study_report_section <- function(document, id) {
  section <- xml2::xml_find_first(document, sprintf("//section[@id='%s']", id))
  stopifnot(!inherits(section, "xml_missing"))
  section
}

study_audit_groups <- function(values) {
  split(seq_along(values), match(values, unique(values)))
}

study_audit_supported <- function(data) {
  valid <- is.finite(data$HOSP_NIS) & data$HOSP_NIS > 0 & is.finite(data$YEAR) & data$YEAR > 0
  nrow(data) >= 11L && nrow(unique(data[valid, c("YEAR", "HOSP_NIS")])) >= 2L
}

study_audit_levels <- function(data, variable) {
  value <- data[[variable]]
  if (is.numeric(value) && !is.factor(value)) {
    observed <- is.finite(value)
    value <- as.character(value)
    value[observed] <- "observed"
  }
  levels <- unique(value)
  if (is.logical(data[[variable]])) {
    levels <- union(c(FALSE, TRUE), levels)
  }
  all(vapply(
    levels,
    function(level) {
      selected <- if (is.na(level)) is.na(value) else which(value == level)
      study_audit_supported(data[selected, ])
    },
    logical(1)
  ))
}

study_audit_sections <- c(
  "cohort-flow" = "Cohort flow",
  "table-1" = "Table 1",
  outcomes = "Outcomes",
  "trends-by-year" = "Trends by year",
  "multivariable-models" = "Multivariable models"
)

study_audit_tables <- function(report, format) {
  if (format == "html") {
    doc <- xml2::read_html(report)
    xml2::xml_remove(xml2::xml_find_all(doc, "//table//sup"))
    cells <- function(row) xml2::xml_text(xml2::xml_find_all(row, "./th | ./td"), trim = TRUE)
    return(
      lapply(names(study_audit_sections), function(id) {
        tables <- xml2::xml_find_all(study_report_section(doc, id), ".//table")
        lapply(tables, function(table) {
          list(
            header = cells(xml2::xml_find_first(table, "./thead/tr[last()]")),
            rows = lapply(xml2::xml_find_all(table, "./tbody/tr"), cells)
          )
        })
      }) |>
        stats::setNames(names(study_audit_sections))
    )
  }

  file <- utils::unzip(report, files = "word/document.xml", exdir = "word-proof")
  doc <- xml2::read_xml(file)
  ns <- xml2::xml_ns(doc)
  node_text <- function(node) {
    parts <- xml2::xml_find_all(node, ".//w:r[not(w:rPr/w:vertAlign[@w:val='superscript'])]/w:t", ns)
    trimws(paste(xml2::xml_text(parts), collapse = " "))
  }
  tables <- xml2::xml_find_all(doc, "//w:body/w:tbl", ns)
  sections <- vapply(
    tables,
    function(table) {
      node_text(xml2::xml_find_first(table, "preceding-sibling::w:p[w:pPr/w:pStyle[@w:val='Heading2']][1]", ns))
    },
    character(1)
  )
  lapply(study_audit_sections, function(section) {
    lapply(tables[sections == section], function(table) {
      cells <- function(row) vapply(xml2::xml_find_all(row, "./w:tc", ns), node_text, character(1))
      header <- cells(tail(xml2::xml_find_all(table, "./w:tr[w:trPr/w:tblHeader]", ns), 1L))
      rows <- xml2::xml_find_all(table, "./w:tr[not(w:trPr/w:tblHeader) and count(w:tc) > 1]", ns)
      list(header = header, rows = lapply(rows, cells))
    })
  })
}

verify_study_cell_support <- function(report, format, evidence, case) {
  stopifnot(file.copy("support-input.R", file.path(evidence, paste0("support-input-", format, ".R"))))
  proof <- dget("support-input.R")
  tables <- study_audit_tables(report, format)
  rows <- proof$rows
  by_arm <- vapply(
    tables[["table-1"]],
    function(table) {
      any(grepl("^.+[[:space:]]+N =", table$header))
    },
    logical(1)
  )
  arms <- if (any(by_arm)) study_audit_groups(rows[[proof$exposure]]) else list()
  groups <- c(list(seq_len(nrow(rows))), study_audit_groups(rows$YEAR))
  valid <- function(variable) {
    scopes <- if (identical(variable, proof$exposure)) groups else c(groups, arms)
    all(vapply(scopes, function(i) study_audit_levels(rows[i, ], variable), logical(1)))
  }
  if (any(by_arm)) {
    stopifnot(valid(proof$exposure))
  }
  numeric_cell <- function(x) grepl("[0-9]", x) & !trimws(x) %in% c("\u226410", "<2 hospitals")
  parse_count <- function(x) {
    ifelse(numeric_cell(x), as.numeric(gsub(",", "", ifelse(numeric_cell(x), x, NA_character_))), NA_real_)
  }
  check_summary <- function(id, variables) {
    section <- tables[[id]]
    if (!length(section)) {
      stopifnot(!length(variables))
      return(numeric())
    }
    stopifnot(length(section) == 1L)
    table <- section[[1L]]
    headers <- table$header[grepl("N = ", table$header, fixed = TRUE)]
    for (header in headers) {
      group <- trimws(sub("N = .*", "", header))
      tab_rows <- if (!nzchar(group)) rows else rows[which(as.character(rows[[proof$exposure]]) == group), ]
      stopifnot(study_audit_supported(tab_rows), parse_count(sub(".*N = ", "", header)) == nrow(tab_rows))
    }
    stopifnot(length(variables) == length(table$rows))
    for (i in seq_along(variables)) {
      if (any(numeric_cell(table$rows[[i]][-1L]))) {
        stopifnot(valid(variables[[i]]))
      }
      if (id == "table-1") {
        for (j in which(grepl("N = ", table$header, fixed = TRUE))) {
          cell <- table$rows[[i]][[j]]
          if (!grepl("\\[", cell)) {
            next
          }
          group <- trimws(sub("N = .*", "", table$header[[j]]))
          values <- rows[[variables[[i]]]]
          if (nzchar(group)) {
            values <- values[which(as.character(rows[[proof$exposure]]) == group)]
          }
          n <- sub(".*\\[(.*/)?([0-9,]+)\\]$", "\\2", cell)
          stopifnot(parse_count(n) == sum(!is.na(values)))
        }
      }
    }
    parse_count(sub("^N = ", "", headers[startsWith(headers, "N = ")]))
  }
  table_counts <- check_summary("table-1", proof$summary[[1L]])
  outcome_counts <- check_summary("outcomes", proof$summary[[2L]])
  trends <- tables[["trends-by-year"]]
  totals <- if (length(trends)) trends[[1L]]$rows else list()
  pooled <- all(vapply(study_audit_groups(rows$YEAR), function(i) study_audit_supported(rows[i, ]), logical(1)))
  trend_valid <- function(year, variable) {
    if (pooled) valid(variable) else study_audit_levels(rows[rows$YEAR == year, ], variable)
  }
  for (cell in totals) {
    annual <- rows[rows$YEAR == cell[[1L]], ]
    if (any(numeric_cell(cell[2:3]))) {
      stopifnot(study_audit_supported(annual))
    }
    if (numeric_cell(cell[[2L]])) {
      stopifnot(parse_count(cell[[2L]]) == nrow(annual))
    }
    for (j in 1:2) {
      variable <- c("DIED", "LOS")[[j]]
      displayed <- numeric_cell(cell[[3L + j]])
      stopifnot(displayed == numeric_cell(cell[[5L + j]]))
      if (displayed) {
        stopifnot(trend_valid(cell[[1L]], variable), parse_count(cell[[5L + j]]) == sum(!is.na(annual[[variable]])))
      } else {
        stopifnot(identical(cell[[3L + j]], cell[[5L + j]]))
      }
    }
  }
  chart <- proof$chart
  for (i in seq_len(NROW(chart))) {
    variable <- if (chart$measure[[i]] == "In-hospital mortality") "DIED" else "LOS"
    stopifnot(
      trend_valid(chart$YEAR[[i]], variable),
      chart$n[[i]] == sum(rows$YEAR == chart$YEAR[[i]] & !is.na(rows[[variable]]))
    )
  }
  model_tables <- tables[["multivariable-models"]]
  if (length(model_tables)) {
    stopifnot(length(proof$models) > 0L)
    for (model in proof$models) {
      stopifnot(all(vapply(all.vars(model$formula), valid, logical(1))))
      study_audit_model(rows, model)
    }
    if (format == "html") {
      text <- xml2::xml_text(study_report_section(xml2::read_html(report), "multivariable-models"))
      stopifnot(grepl(paste0("(n = ", format(nrow(rows), big.mark = ","), ")"), text, fixed = TRUE))
    }
  }
  if (any(case$support_case %in% c("DIED", "LOS"))) {
    variable <- case$support_case
    unaffected <- if (variable == "DIED") "Mean length of stay" else "In-hospital mortality"
    stopifnot(
      sum(is.na(rows[[variable]]) & rows$YEAR == max(rows$YEAR)) == 3L,
      !valid(variable),
      unaffected %in% chart$measure
    )
  }
  if (identical(case$support_case, "observed_los")) {
    point <- chart[chart$YEAR == max(rows$YEAR) & chart$measure == "Mean length of stay", ]
    stopifnot(identical(point$n, 72L), valid("LOS"))
  }
  flow <- tables[["cohort-flow"]][[1L]]$rows
  flow_final <- verify_study_flow_support(flow, proof, case, numeric_cell)
  yearly_counts <- vapply(totals, function(cell) parse_count(cell[[2L]]), numeric(1))
  if (anyNA(yearly_counts)) {
    stopifnot(
      !any(numeric_cell(unlist(lapply(flow, function(row) row[2:3])))),
      !length(table_counts),
      !length(outcome_counts)
    )
  }
  published_counts <- c(flow_final, table_counts, outcome_counts)
  if (length(yearly_counts) && !anyNA(yearly_counts)) {
    published_counts <- c(published_counts, sum(yearly_counts))
  }
  stopifnot(all(published_counts[!is.na(published_counts)] == nrow(rows)))
  if (isTRUE(case$support_case %in% c("exposure", "absent_exposure"))) {
    sizes <- if (case$support_case == "exposure") c(3L, 50L) else c(0L, 50L)
    stopifnot(
      identical(unname(as.integer(tapply(rows[[proof$exposure]], rows$YEAR, sum))), sizes),
      identical(unname(vapply(split(rows$DISCWT, rows$YEAR), unique, numeric(1))), c(5, 10)),
      all(!by_arm),
      !valid(proof$exposure),
      length(yearly_counts) == 2L,
      !anyNA(yearly_counts)
    )
    stopifnot(!length(model_tables))
    # The disclosure pathway withholds all arm-specific totals and estimates;
    # the two displayed annual margins alone leave the arm cells unknown.
    stopifnot(!length(tables[["table-1"]]))
  }
}

study_audit_model <- function(rows, model) {
  frame <- stats::model.frame(model$formula, rows, na.action = stats::na.omit)
  stopifnot(nrow(frame) == nrow(rows))
  response <- stats::model.response(frame)
  if (model$family %in% c("binomial", "quasibinomial")) {
    response <- factor(response)
  }
  rows$.response <- response
  categorical <- names(frame)[vapply(frame, function(x) is.factor(x) || is.logical(x) || is.character(x), logical(1))]
  categorical <- setdiff(categorical, names(frame)[attr(attr(frame, "terms"), "response")])
  term_factors <- attr(attr(frame, "terms"), "factors")
  interactions <- lapply(seq_len(ncol(term_factors)), function(i) {
    intersect(categorical, rownames(term_factors)[term_factors[, i] > 0L])
  })
  groups <- unique(c(as.list(categorical), Filter(length, interactions)))
  for (fields in groups) {
    keys <- interaction(frame[fields], drop = TRUE)
    for (i in study_audit_groups(keys)) {
      stopifnot(study_audit_levels(rows[i, ], ".response"))
    }
  }
}

verify_study_flow_support <- function(flow, proof, case, numeric_cell) {
  source <- proof$source
  valid <- Reduce(`&`, lapply(source[c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")], function(x) is.finite(x) & x > 0))
  cells <- do.call(rbind, flow)
  parse_discharge <- function(x) as.numeric(gsub(",", "", x, fixed = TRUE))
  final <- cells[nrow(cells), 2L]
  final <- if (numeric_cell(final)) parse_discharge(final) else NA_real_
  if (proof$restricted) {
    stopifnot(nrow(cells) == 1L)
    if (any(numeric_cell(cells[, 2:3]))) {
      stopifnot(study_audit_supported(proof$rows))
    }
    if (numeric_cell(cells[1L, 3L])) {
      stopifnot(cells[1L, 3L] == formatC(sum(proof$rows$DISCWT), format = "f", digits = 1, big.mark = ","))
    }
    return(final)
  }
  stopifnot(nrow(cells) == 4L)
  principal <- source$principal %in% TRUE
  cohort <- source$cohort %in% TRUE
  atoms <- interaction(principal, cohort, valid, drop = TRUE)
  if (any(numeric_cell(cells[, 2:3]))) {
    # Primary masks may leave safe labels, but a protected atom closes every numeric flow total.
    stopifnot(all(vapply(split(source, atoms), study_audit_supported, logical(1))))
  }
  counts <- c(nrow(source), sum(principal), sum(cohort), sum(cohort & valid))
  unweighted <- numeric_cell(cells[, 2L])
  stopifnot(all(parse_discharge(cells[unweighted, 2L]) == counts[unweighted]))
  weights <- ifelse(valid, source$DISCWT, 0)
  expected <- c(sum(weights), sum(weights[principal]), sum(weights[cohort]), sum(weights[cohort & valid]))
  visible <- numeric_cell(cells[, 3L])
  stopifnot(all(cells[visible, 3L] == formatC(expected[visible], format = "f", digits = 1, big.mark = ",")))
  if (identical(case$support_case, "DISCWT")) {
    stopifnot(sum(!valid & is.finite(source$DISCWT) & source$DISCWT > 0) == 3L, all(visible))
  }
  final
}

verify_study_disclosure <- function(report, case) {
  document <- xml2::read_html(report)
  table_one <- study_report_section(document, "table-1")
  models <- study_report_section(document, "multivariable-models")
  if (isTRUE(case$flow_one_hospital)) {
    flow <- study_report_section(document, "cohort-flow")
    cells <- xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr[2]/td[position() > 1]"), trim = TRUE)
    stopifnot(
      identical(cells, rep("<2 hospitals", 2L)),
      grepl("The cohort has no rows", xml2::xml_text(models), fixed = TRUE)
    )
    return(invisible(NULL))
  }
  if (isTRUE(case$missing_exposure)) {
    stopifnot(
      length(xml2::xml_find_all(table_one, ".//table")) == 1L,
      grepl("The model data are missing not_kept", xml2::xml_text(models), fixed = TRUE)
    )
    return(invisible(NULL))
  }
  if (isTRUE(case$masked_p)) {
    headers <- xml2::xml_text(xml2::xml_find_all(table_one, ".//thead//th"))
    label <- xml2::xml_find_first(
      table_one,
      ".//tbody/tr[td[@headers='label' and starts-with(normalize-space(.), 'Female')]]"
    )
    p <- xml2::xml_text(xml2::xml_find_all(label, "./td[@headers='p.value']"), trim = TRUE)
    levels <- xml2::xml_find_all(label, "following-sibling::tr[position() <= 2]/td")
    stopifnot(
      any(grepl("N = 264", headers, fixed = TRUE)),
      "\u226410" %in% xml2::xml_text(levels, trim = TRUE),
      length(p) == 1L,
      !grepl("[0-9]", p)
    )
    return(invisible(NULL))
  }
  trends <- study_report_section(document, "trends-by-year")
  plot_data <- dget("trend-plot-data.R")
  stopifnot(
    all(plot_data$visible),
    any(plot_data$YEAR == tail(case$years, 1L)),
    length(xml2::xml_find_all(trends, ".//img[starts-with(@src, 'data:image/')]")) == 1L
  )
  published_models <- xml2::xml_find_all(models, ".//table")
  if (isTRUE(case$supported)) {
    outcomes <- study_report_section(document, "outcomes")
    headers <- xml2::xml_text(xml2::xml_find_all(outcomes, ".//thead//th"))
    stopifnot(
      any(grepl(paste0("N = ", sum(case$sizes)), headers, fixed = TRUE)),
      length(xml2::xml_find_all(table_one, ".//table")) == 1L,
      any(grepl("TOTCHG", xml2::xml_text(published_models), fixed = TRUE))
    )
    stopifnot(
      length(published_models) > 0L,
      grepl(as.character(tail(case$years, 1L)), xml2::xml_text(published_models), fixed = TRUE),
      grepl("The model data are missing not_kept_outcome", xml2::xml_text(models), fixed = TRUE)
    )
    return(invisible(NULL))
  }
  stopifnot(
    !length(published_models),
    grepl("Withheld under the study disclosure policy.", xml2::xml_text(models), fixed = TRUE)
  )
  stopifnot(!length(xml2::xml_find_all(table_one, ".//table")))
  if (is.null(case$masks)) {
    return(invisible(NULL))
  }

  rows <- xml2::xml_find_all(trends, ".//tbody/tr")
  cells <- do.call(
    rbind,
    lapply(rows, function(row) {
      xml2::xml_text(xml2::xml_find_all(row, "./td"), trim = TRUE)
    })
  )
  n_masked <- length(case$masks)
  stopifnot(
    !any(plot_data$YEAR %in% head(case$years, n_masked)),
    identical(cells[seq_len(n_masked), 2L], case$masks),
    identical(cells[seq_len(n_masked), 3L], case$masks),
    cells[nrow(cells), 2L] == as.character(tail(case$sizes, 1L))
  )
  outcomes <- study_report_section(document, "outcomes")
  flow <- study_report_section(document, "cohort-flow")
  stopifnot(
    !length(xml2::xml_find_all(outcomes, ".//table")),
    all(xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr[last()]/td[position() > 1]")) == "Masked")
  )
  protected <- formatC(c(case$weights[seq_len(n_masked)], sum(case$weights)), format = "f", digits = 1L, big.mark = ",")
  main <- xml2::xml_text(xml2::xml_find_first(document, "//main"))
  stopifnot(!any(vapply(protected, grepl, logical(1), x = main, fixed = TRUE)))
}
