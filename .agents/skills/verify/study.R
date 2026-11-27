study_verification_packages <- function(journey) {
  if (!journey %in% c("study", "study-ci", "study-small", "study-reporting")) return(character())
  packages <- c("broom.helpers", "cardx", "ggplot2", "gt", "gtsummary", "knitr",
    "purrr", "rmarkdown", "survey", "xml2")
  if (journey == "study-ci") c(packages, "flextable") else packages
}

drive_study <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html")
}

drive_study_small <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html", small_cohort = TRUE)
  cases <- list(
    flow_one_hospital = list(sizes = rep(144L, 2L), flow_one_hospital = TRUE,
      setup = 'cohort <- rlang::expr(FALSE)'),
    missing_exposure = list(sizes = rep(144L, 2L), missing_exposure = TRUE,
      setup = 'exposure <- "not_kept"'),
    missing_arm = list(sizes = rep(144L, 2L),
      setup = 'study_design$variables$exposed[seq_len(5L)] <- NA'),
    unused_arm = list(sizes = rep(144L, 2L),
      setup = paste0('study_design$variables$exposed <- factor(study_design$variables$exposed, ',
        'levels = c("FALSE", "TRUE", "Unused"))')),
    masked_p = list(sizes = rep(144L, 2L), masked_p = TRUE, setup = c(
      'study_design$variables$exposed[seq_len(24L)] <- NA',
      'arm <- which(study_design$variables$exposed)',
      'female <- seq_len(nrow(study_design$variables)) %% 2L == 0L',
      'female[arm] <- seq_along(arm) <= 5L',
      'study_design$variables$FEMALE <- factor(ifelse(female, "A", "B"))'
    )),
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
    verify_study(directory, results, "html", fixture$input,
      disclosure_case = c(case, fixture[c("years", "weights")]))
  }
}

drive_study_reporting <- function(scratch, evidence) {
  for (variant in c("domain", "prefiltered", "small-exclusion")) {
    run <- file.path(scratch, variant)
    proof <- file.path(evidence, variant)
    stopifnot(dir.create(run), dir.create(proof))
    verify_study(run, proof, "html", reporting_variant = variant)
  }
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
    step = c("All discharges", "Principal diagnosis prefix", "Cohort definition",
      "Analysis cohort (valid survey design)"),
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
      YEAR = years[[i]], HOSP_NIS = hospital, NIS_STRATUM = (hospital - 1L) %/% 4L + 1L,
      DISCWT = 101.25 + 13 * i, CCR_NIS = 0.3, TOTCHG = 2000 + 17 * position + position %% 7L,
      LOS = 1L + (position * 7L + i) %% 19L, DIED = as.integer(position %% 7L < 3L),
      AGE = 41L + position %% 37L, FEMALE = position %% 3L == 0L,
      I10_DX1 = principal, I10_DX2 = ifelse(exposed, "Z515", "E119")
    )
    weights[[i]] <- sum(records$DISCWT)
    destination <- file.path(input, sprintf("NIS_%d.parquet", years[[i]]))
    easyNIS:::nis_duckdb_write_parquet(records, destination, con)
  }
  list(input = input, years = years, weights = weights)
}

verify_study <- function(scratch, evidence, formats, input = NULL, small_cohort = FALSE,
                         disclosure_case = NULL, reporting_variant = NULL) {
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) stop("Quarto must be on PATH to drive the study feature.")
  version <- system2(quarto, "--version", stdout = TRUE)
  if (!length(version) || !is.null(attr(version, "status"))) stop("Quarto version check failed.")
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
        flags_line <- grep("^nis_data <- nis_data", definition)
        stopifnot(length(flags_line) == 1L)
        definition <- append(definition, c(
          'outcomes <- dplyr::add_row(outcomes, outcome = "TOTCHG", family = "gaussian", exponentiate = FALSE)',
          'outcomes <- dplyr::add_row(outcomes, outcome = "not_kept_outcome", family = "gaussian", exponentiate = FALSE)',
          ""
        ), after = flags_line - 1L)
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
        definition <- c(definition, "", "```{r}", "#| include: false",
          'dput(trend_long, file = "trend-plot-data.R")', "```")
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
    if (reporting_variant == "prefiltered") {
      line <- grep("^# Quarto can put chunk options", definition)
      stopifnot(length(line) == 1L)
      definition <- append(definition, "nis_data <- dplyr::filter(nis_data, AGE >= 30)", after = line - 1L)
    }
    if (reporting_variant == "small-exclusion") {
      line <- grep("^cohort <- ", definition)
      stopifnot(length(line) == 1L)
      definition[line] <- paste0("cohort <- rlang::expr(",
        "principal_dx & !(YEAR == 2019L & HOSP_NIS == 1L & AGE == 28))")
    }
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
    if (!is.null(disclosure_case)) verify_study_disclosure(report, disclosure_case)
    if (!is.null(reporting_variant)) verify_study_reporting(report, reporting_variant)
  }
}

render_study <- function(quarto, format, input, evidence) {
  render_log <- file.path(evidence, paste0("render-", format, ".txt"))
  args <- c("render", "analysis.qmd", "--to", format)
  if (!is.null(input)) args <- c(args, "-P", shQuote(paste0("data_path:", input)))
  cat("RENDER ", paste(c(shQuote(quarto), args), collapse = " "), "\n", sep = "")
  status <- system2(quarto, args, stdout = render_log, stderr = render_log)
  if (status != 0L) stop("Quarto render failed. Read ", basename(render_log), ".")
  report <- file.path("docs", paste0("analysis.", format))
  stopifnot(file.exists(report), file.info(report)$size > 0L, file.copy(report, evidence))
  report
}

validate_study_report <- function(report, format, input, expected, evidence, small_cohort = FALSE) {
  sections <- c("Study definitions", "Methods", "Cohort flow", "Table 1", "Outcomes",
    "Trends by year", "Multivariable models")
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
        stopifnot(!length(xml2::xml_find_all(section, ".//table")),
          grepl("under the study disclosure policy", xml2::xml_text(section), fixed = TRUE))
      }
    }
    assets <- xml2::xml_text(xml2::xml_find_all(document,
      "//script/@src | //img/@src | //link[@rel='stylesheet']/@href"))
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
    body <- paste(xml2::xml_text(xml2::xml_find_all(document, "//*[local-name()='t']")),
      collapse = " ")
    stopifnot(all(vapply(c("National Inpatient Sample Study", sections),
      function(section) grepl(section, body, fixed = TRUE), logical(1))))
  }
  stopifnot(grepl("unweighted discharges are masked", body, fixed = TRUE),
    grepl("HCUP Data Use Agreement", body, fixed = TRUE),
    grepl("experimental pending", body, fixed = TRUE))
  cat("RENDER PASS ", format, " ", file.info(report)$size, " bytes\n", sep = "")
}

verify_study_reporting <- function(report, variant) {
  document <- xml2::read_html(report)
  methods <- xml2::xml_text(study_report_section(document, "methods"))
  methods <- gsub("[[:space:]]+", " ", methods)
  criterion <- if (variant == "small-exclusion") {
    "principal_dx & !(YEAR == 2019L & HOSP_NIS == 1L & AGE == 28)"
  } else "principal_dx & AGE >= 18"
  expected <- c("2019, 2020", criterion, "DISCWT", "divided by 2",
    "HOSP_NIS", "NIS_STRATUM", "Taylor linearization", "ICD-10-CM/PCS", "DuckDB", "survey")
  stopifnot(all(vapply(expected, grepl, logical(1), x = methods, fixed = TRUE)))
  domain <- xml2::xml_text(xml2::xml_find_first(document,
    "//section[@id='checklist-receipt']//tr[td[normalize-space(.)='Survey domain']]"))
  prefilter <- variant == "prefiltered"
  stopifnot(grepl(if (prefilter) "Needs attention" else "Pass", domain, fixed = TRUE))
  stopifnot(grepl("could not verify that the design input retained the opened sample",
    methods, fixed = TRUE) == prefilter)
  if (variant == "small-exclusion") {
    flow <- study_report_section(document, "cohort-flow")
    counts <- xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr/td[position() > 1]"), trim = TRUE)
    stopifnot(length(counts) == 8L, all(counts == "Masked"))
  }
}

validate_study_flow <- function(document, expected, evidence, small_cohort) {
  rows <- xml2::xml_find_all(document, "//section[@id='cohort-flow']//tbody/tr")
  cells <- lapply(rows, function(row) xml2::xml_text(xml2::xml_find_all(row, "./td"), trim = TRUE))
  result <- do.call(rbind, cells)
  stopifnot(identical(dim(result), c(4L, 3L)))
  if (small_cohort) stopifnot(all(result[3:4, 2:3] == "\u226410"))
  if (is.null(expected)) return(invisible(NULL))

  parse_number <- function(value) as.numeric(gsub(",", "", value, fixed = TRUE))
  observed <- data.frame(step = result[, 1L], discharges = parse_number(result[, 2L]),
    weighted_discharges = parse_number(result[, 3L]))
  dput(list(expected = expected, observed = observed), file = file.path(evidence, "study-flow.R"))
  stopifnot(identical(observed$step, expected$step),
    all(observed$discharges == expected$discharges),
    isTRUE(all.equal(observed$weighted_discharges, expected$weighted_discharges)))
}

study_report_section <- function(document, id) {
  section <- xml2::xml_find_first(document, sprintf("//section[@id='%s']", id))
  stopifnot(!inherits(section, "xml_missing"))
  section
}

verify_study_disclosure <- function(report, case) {
  document <- xml2::read_html(report)
  table_one <- study_report_section(document, "table-1")
  models <- study_report_section(document, "multivariable-models")
  if (isTRUE(case$flow_one_hospital)) {
    flow <- study_report_section(document, "cohort-flow")
    cells <- xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr[2]/td[position() > 1]"), trim = TRUE)
    stopifnot(identical(cells, rep("<2 hospitals", 2L)),
      grepl("The cohort has no rows", xml2::xml_text(models), fixed = TRUE))
    return(invisible(NULL))
  }
  if (isTRUE(case$missing_exposure)) {
    stopifnot(length(xml2::xml_find_all(table_one, ".//table")) == 1L,
      grepl("The model data are missing not_kept", xml2::xml_text(models), fixed = TRUE))
    return(invisible(NULL))
  }
  if (isTRUE(case$masked_p)) {
    headers <- xml2::xml_text(xml2::xml_find_all(table_one, ".//thead//th"))
    label <- xml2::xml_find_first(table_one,
      ".//tbody/tr[td[@headers='label' and starts-with(normalize-space(.), 'Female')]]")
    p <- xml2::xml_text(xml2::xml_find_all(label, "./td[@headers='p.value']"), trim = TRUE)
    levels <- xml2::xml_find_all(label, "following-sibling::tr[position() <= 2]/td")
    stopifnot(any(grepl("N = 264", headers, fixed = TRUE)),
      "\u226410" %in% xml2::xml_text(levels, trim = TRUE),
      length(p) == 1L, !grepl("[0-9]", p))
    return(invisible(NULL))
  }
  trends <- study_report_section(document, "trends-by-year")
  plot_data <- dget("trend-plot-data.R")
  stopifnot(all(plot_data$visible), any(plot_data$YEAR == tail(case$years, 1L)),
    length(xml2::xml_find_all(trends, ".//img[starts-with(@src, 'data:image/')]")) == 1L)
  published_models <- xml2::xml_find_all(models, ".//table")
  if (isTRUE(case$supported)) {
    outcomes <- study_report_section(document, "outcomes")
    headers <- xml2::xml_text(xml2::xml_find_all(outcomes, ".//thead//th"))
    stopifnot(any(grepl(paste0("N = ", sum(case$sizes)), headers, fixed = TRUE)),
      length(xml2::xml_find_all(table_one, ".//table")) == 1L,
      any(grepl("TOTCHG", xml2::xml_text(published_models), fixed = TRUE)))
    stopifnot(length(published_models) > 0L,
      grepl(as.character(tail(case$years, 1L)), xml2::xml_text(published_models), fixed = TRUE),
      grepl("The model data are missing not_kept_outcome", xml2::xml_text(models), fixed = TRUE))
    return(invisible(NULL))
  }
  stopifnot(!length(published_models), grepl("Withheld under the study disclosure policy.",
    xml2::xml_text(models), fixed = TRUE))
  stopifnot(!length(xml2::xml_find_all(table_one, ".//table")))
  if (is.null(case$masks)) return(invisible(NULL))

  rows <- xml2::xml_find_all(trends, ".//tbody/tr")
  cells <- do.call(rbind, lapply(rows, function(row) {
    xml2::xml_text(xml2::xml_find_all(row, "./td"), trim = TRUE)
  }))
  n_masked <- length(case$masks)
  stopifnot(!any(plot_data$YEAR %in% head(case$years, n_masked)),
    identical(cells[seq_len(n_masked), 2L], case$masks),
    identical(cells[seq_len(n_masked), 3L], case$masks),
    cells[nrow(cells), 2L] == as.character(tail(case$sizes, 1L)))
  outcomes <- study_report_section(document, "outcomes")
  flow <- study_report_section(document, "cohort-flow")
  stopifnot(!length(xml2::xml_find_all(outcomes, ".//table")),
    all(xml2::xml_text(xml2::xml_find_all(flow, ".//tbody/tr[last()]/td[position() > 1]")) == "Masked"))
  protected <- formatC(c(case$weights[seq_len(n_masked)], sum(case$weights)),
    format = "f", digits = 1L, big.mark = ",")
  main <- xml2::xml_text(xml2::xml_find_first(document, "//main"))
  stopifnot(!any(vapply(protected, grepl, logical(1), x = main, fixed = TRUE)))
}
