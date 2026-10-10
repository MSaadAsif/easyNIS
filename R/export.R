#' Export a disclosure-reviewed table
#'
#' Writes the presentation of one [nis_disclosure_review()] to CSV or HTML.
#' Only reviewed presentations can be exported. The review is recomputed from
#' its retained results and recorded policy and must match exactly. The file is a candidate for human publication review and
#' does not certify a manuscript.
#'
#' @param review An experimental [nis_disclosure_review()] result.
#' @param path File path whose extension matches `format`. Its directory must
#'   exist.
#' @param format `"csv"` or `"html"`.
#' @param digits `NULL` for exact values, required for CSV. For HTML, a whole
#'   number from 1 to 15 rounds the estimate, SE and interval to that many
#'   significant digits. Counts, df and confidence levels are never rounded.
#' @param overwrite `TRUE` or `FALSE`. An existing file is replaced only when
#'   `TRUE`.
#' @return The normalized path, invisibly.
#' @details CSV contains the 13 presentation columns with exact numeric values
#'   that [utils::read.csv()] parses back to identical doubles; suppressed cells
#'   are empty. HTML is a standalone escaped document whose notes record the
#'   experimental scope, count basis and disclosure policy. Suppressed values
#'   appear in neither format, and audit counts are never written. Output is
#'   written to a temporary file and renamed, so a failure leaves no partial
#'   file. Annual support and scientific approval remain pending.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), "LOS", TRUE,
#'     "hospital_wr", "fail")
#'   specification <- data.frame(id = "los", field = "LOS", statistic = "mean",
#'     label = "Length of stay", unit = "days")
#'   table <- nis_descriptive_table(design, specification, "fail", 2, 0.95,
#'     "wr_unadjusted")
#'   review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
#'   csv <- nis_export_table(review, tempfile(fileext = ".csv"), "csv", NULL, FALSE)
#'   utils::read.csv(csv)
#'   html <- nis_export_table(review, tempfile(fileext = ".html"), "html", 3, FALSE)
#'   nis_close(session)
#'   unlink(c(path, csv, html))
#' }
nis_export_table <- function(review, path, format, digits, overwrite) {
  if (base::missing(review) || base::missing(path) || base::missing(format) ||
      base::missing(digits) || base::missing(overwrite)) {
    stop("Supply `review`, `path`, `format`, `digits` and `overwrite` explicitly.",
         call. = FALSE)
  }
  if (inherits(review, c("nis_descriptive_table", "nis_regression_table"))) {
    stop("Only a nis_disclosure_review can be exported; review the table first. ",
         "Regression tables have no disclosure review yet.", call. = FALSE)
  }
  check_review(review)
  if (!is.character(format) || length(format) != 1L || is.na(format) ||
      !format %in% c("csv", "html")) {
    stop("`format` must be \"csv\" or \"html\".", call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) ||
      !grepl(paste0("\\.", format, "$"), path, ignore.case = TRUE)) {
    stop("`path` must be one file path ending in .", format, ".", call. = FALSE)
  }
  if (!is.null(digits) && (format == "csv" || !is_whole(digits, 1L) ||
      digits < 1 || digits > 15)) {
    stop("`digits` must be NULL for CSV, or NULL or a whole number from 1 to 15 for HTML.",
         call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  directory <- dirname(path)
  if (!dir.exists(directory)) stop("The output directory does not exist.", call. = FALSE)
  if (dir.exists(path)) stop("`path` is a directory.", call. = FALSE)
  if (file.exists(path) && !overwrite) {
    stop("`path` exists; set `overwrite = TRUE` to replace it.", call. = FALSE)
  }

  lines <- if (format == "csv") csv_lines(review$presentation) else
    html_lines(review, digits)
  staged <- tempfile("easyNIS-export-", tmpdir = directory, fileext = paste0(".", format))
  on.exit(if (file.exists(staged)) unlink(staged), add = TRUE)
  connection <- file(staged, open = "wb")
  tryCatch(writeLines(enc2utf8(lines), connection, sep = "\n", useBytes = TRUE),
    finally = close(connection))
  if (!file.rename(staged, path)) stop("Could not write `path`.", call. = FALSE)
  invisible(normalizePath(path))
}

check_review <- function(review) {
  refuse <- function() {
    stop("`review` must be an unmodified nis_disclosure_review result.", call. = FALSE)
  }
  table <- review$table
  policy <- review$provenance$policy
  if (!inherits(review, "nis_disclosure_review") || !is.list(review) ||
      !identical(names(review), c("presentation", "audit", "table", "provenance")) ||
      !is.data.frame(review$presentation) || !inherits(table, "nis_descriptive_table") ||
      !is.data.frame(table$data) || !is.list(table$results) ||
      !identical(names(table$results), table$data$id) || !is.list(policy)) refuse()
  for (column in c("estimate", "se", "lower", "upper", "df", "confidence")) {
    from_results <- vapply(table$results, function(x) {
      if (is.numeric(x[[column]]) && length(x[[column]]) == 1L) as.double(x[[column]]) else NaN
    }, numeric(1), USE.NAMES = FALSE)
    field <- if (column == "estimate") "weighted_estimate" else column
    if (!identical(as.double(table$data[[field]]), from_results)) refuse()
  }
  rerun <- tryCatch(nis_disclosure_review(table, policy$suppress, policy$zero,
    policy$min_hospitals, policy$margins), error = function(e) NULL)
  if (is.null(rerun) || !identical(rerun, review)) refuse()
  invisible(TRUE)
}

exact_number <- function(x) {
  vapply(x, function(value) {
    if (is.na(value)) return("")
    if (is.infinite(value)) return(if (value > 0) "Inf" else "-Inf")
    if (value == round(value) && abs(value) <= 2^53) return(sprintf("%.0f", value))
    sprintf("%.17g", value)
  }, character(1), USE.NAMES = FALSE)
}

csv_lines <- function(presentation) {
  quote <- function(x) {
    x <- enc2utf8(as.character(x))
    ifelse(is.na(x), "", paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\""))
  }
  numeric <- vapply(presentation, is.numeric, logical(1))
  cells <- lapply(names(presentation), function(column) {
    if (numeric[[column]]) exact_number(presentation[[column]]) else quote(presentation[[column]])
  })
  c(paste(quote(names(presentation)), collapse = ","),
    do.call(paste, c(cells, sep = ",")))
}

escape_html <- function(x) {
  x <- enc2utf8(as.character(x))
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"),
                    c("\"", "&quot;"), c("'", "&#39;"))) {
    x <- gsub(pair[[1L]], pair[[2L]], x, fixed = TRUE)
  }
  x
}

html_lines <- function(review, digits) {
  presentation <- review$presentation
  rounded <- function(x) {
    vapply(x, function(value) {
      if (is.na(value)) return("NA")
      if (is.null(digits) || !is.finite(value)) return(exact_number(value))
      sub("\\.$", "", formatC(signif(value, digits), digits = digits, format = "fg",
        flag = "#"))
    }, character(1), USE.NAMES = FALSE)
  }
  rounded_exact <- function(x) ifelse(is.na(x), "NA", exact_number(x))
  shown <- presentation$disclosure_status == "shown"
  hidden <- function(text) ifelse(shown, text, "Suppressed")
  interval <- paste0(rounded(presentation$lower), " to ", rounded(presentation$upper))
  status <- c(shown = "Shown", suppressed_primary = "Suppressed (primary)",
    suppressed_complementary = "Suppressed (complementary)")[presentation$disclosure_status]
  cells <- cbind(escape_html(presentation$label), escape_html(presentation$statistic),
    escape_html(presentation$unit), escape_html(presentation$estimand),
    hidden(rounded(presentation$estimate)), hidden(rounded(presentation$se)),
    hidden(interval), rounded_exact(presentation$df),
    hidden(rounded_exact(presentation$unweighted_n)), unname(status),
    rounded_exact(presentation$confidence))
  header <- c("Label", "Statistic", "Unit", "Estimand", "Estimate", "SE", "Interval",
    "df", "Unweighted discharges", "Disclosure status", "Confidence level (0 to 1)")
  row <- function(x, tag) paste0("<tr>", paste0("<", tag, ">", x, "</", tag, ">",
    collapse = ""), "</tr>")
  policy <- review$provenance$policy
  notes <- c(
    "Experimental table; not analysis ready. Annual support and scientific approval are pending.",
    "Unweighted discharges are included discharges with an observed outcome, not patients. Estimates and intervals are survey weighted.",
    paste0("Disclosure review suppressed checked unweighted counts from ",
      exact_number(policy$suppress[[1L]]), " to ", exact_number(policy$suppress[[2L]]),
      " inclusive; zero counts: ", escape_html(policy$zero),
      "; minimum contributing hospitals: ", exact_number(policy$min_hospitals),
      "; declared margins: ", length(policy$margins), "."),
    "Complementary suppression is a bounded greedy procedure. Larger combinations of declared margins remain unchecked. Undeclared relations, other tables and external publications require human review.",
    if (is.null(digits)) "Values are exact." else
      paste0("Estimates, SEs and intervals are rounded to ", digits,
        " significant digits; counts, df and confidence levels are exact."))
  c("<!DOCTYPE html>", "<html lang=\"en\">", "<head>", "<meta charset=\"utf-8\">",
    "<title>easyNIS experimental descriptive table</title>",
    "<style>table{border-collapse:collapse}th,td{border:1px solid #888;padding:4px 8px;text-align:left}</style>",
    "</head>", "<body>", "<table>",
    "<caption>easyNIS experimental descriptive table</caption>",
    paste0("<thead>", row(header, "th"), "</thead>"), "<tbody>",
    apply(cells, 1L, row, tag = "td"), "</tbody>", "</table>", "<ul>",
    paste0("<li>", notes, "</li>"), "</ul>", "</body>", "</html>")
}
