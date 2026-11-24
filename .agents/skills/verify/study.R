study_verification_packages <- function(journey) {
  if (!journey %in% c("study", "study-ci", "study-small")) return(character())
  packages <- c("broom.helpers", "cardx", "ggplot2", "gt", "gtsummary", "knitr",
    "purrr", "rmarkdown", "survey", "xml2")
  if (journey == "study-ci") c(packages, "flextable") else packages
}

drive_study <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html")
}

drive_study_small <- function(scratch, evidence) {
  verify_study(scratch, evidence, "html", small_cohort = TRUE)
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

verify_study <- function(scratch, evidence, formats, input = NULL, small_cohort = FALSE) {
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
  if (!is.null(input)) {
    expected <- study_fixture_expectations(input, evidence)
    cohort_code <- "dplyr::if_else(AGE >= 50, TRUE, NA)"
  } else if (small_cohort) {
    cohort_code <- "YEAR == 2017L & HOSP_NIS == 1L & AGE == 28"
  }
  if (!is.null(cohort_code)) {
    analysis <- file.path(path, "analysis.qmd")
    definition <- readLines(analysis, encoding = "UTF-8")
    cohort_line <- grepl("^cohort <- ", definition)
    stopifnot(sum(cohort_line) == 1L)
    definition[cohort_line] <- paste0("cohort <- rlang::expr(", cohort_code, ")")
    writeLines(enc2utf8(definition), analysis, useBytes = TRUE)
  }
  stopifnot(all(file.copy(file.path(path, scaffold_files), evidence)))

  original <- getwd()
  on.exit(setwd(original))
  setwd(path)
  Sys.setenv(QUARTO_R = R.home("bin"), R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (format in formats) {
    report <- render_study(quarto, format, input, evidence)
    validate_study_report(report, format, input, expected, evidence, small_cohort)
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
      stopifnot(grepl("contains \u226410 discharges", methods, fixed = TRUE),
        grepl("includes \u226410 hospitals", methods, fixed = TRUE))
    }
    validate_study_flow(document, expected, evidence, small_cohort)
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
