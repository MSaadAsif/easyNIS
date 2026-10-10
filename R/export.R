#' Export a disclosure-reviewed table
#'
#' Writes the presentation of one [nis_disclosure_review()] to CSV, HTML or
#' Word.
#' Only reviewed presentations can be exported. The review is recomputed from
#' its retained results and recorded policy and must match exactly. The file is a candidate for human publication review and
#' does not certify a manuscript.
#'
#' @param review An experimental [nis_disclosure_review()] result.
#' @param path File path whose extension matches `format`. Its directory must
#'   exist.
#' @param format `"csv"`, `"html"` or `"docx"`. Word output requires the
#'   optional officer package, version 0.5.0 or later.
#' @param digits `NULL` for exact values, required for CSV. For HTML and Word,
#'   a whole number from 1 to 15 rounds the estimate, SE and interval to that
#'   many significant digits. Counts, df and confidence levels are never
#'   rounded.
#' @param formula_text For CSV, how to write text cells that begin with `=`,
#'   `+`, `-`, `@`, their full-width forms, a tab, a carriage return or a line
#'   feed, which spreadsheet programs can run as formulas: `"refuse"` stops without writing and names each cell,
#'   `"prefix"` writes them with a leading `'`, and `"keep"` writes them
#'   unchanged. Must be `NULL` for HTML and Word.
#' @param overwrite `TRUE` or `FALSE`. An existing file is replaced only when
#'   `TRUE`.
#' @return The normalized path, invisibly.
#' @details CSV contains the 13 presentation columns with exact numeric values
#'   that [utils::read.csv()] parses back to identical doubles; suppressed cells
#'   are empty. Text cells follow `formula_text`. HTML is a standalone escaped
#'   document whose notes record the experimental scope, count basis and
#'   disclosure policy. Word contains the same table cells and notes as HTML
#'   on a landscape page; labels and units with control characters other than
#'   tab, carriage return and line feed, or U+FFFE or U+FFFF, are refused.
#'   Suppressed values appear
#'   in no format, and audit counts are never written. Output is
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
#'   csv <- nis_export_table(review, tempfile(fileext = ".csv"), "csv", NULL,
#'     "refuse", FALSE)
#'   utils::read.csv(csv)
#'   html <- nis_export_table(review, tempfile(fileext = ".html"), "html", 3, NULL,
#'     FALSE)
#'   if (requireNamespace("officer", quietly = TRUE)) {
#'     docx <- nis_export_table(review, tempfile(fileext = ".docx"), "docx", 3,
#'       NULL, FALSE)
#'     unlink(docx)
#'   }
#'   nis_close(session)
#'   unlink(c(path, csv, html))
#' }
nis_export_table <- function(review, path, format, digits, formula_text,
                             overwrite) {
  if (base::missing(review) || base::missing(path) || base::missing(format) ||
      base::missing(digits) || base::missing(formula_text) ||
      base::missing(overwrite)) {
    stop("Supply `review`, `path`, `format`, `digits`, `formula_text` and ",
         "`overwrite` explicitly.", call. = FALSE)
  }
  if (inherits(review, c("nis_descriptive_table", "nis_regression_table"))) {
    stop("Only a nis_disclosure_review can be exported; review the table first. ",
         "Regression tables have no disclosure review yet.", call. = FALSE)
  }
  check_review(review)
  if (!is.character(format) || length(format) != 1L || is.na(format) ||
      !format %in% c("csv", "html", "docx")) {
    stop("`format` must be \"csv\", \"html\" or \"docx\".", call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) ||
      !grepl(paste0("\\.", format, "$"), path, ignore.case = TRUE)) {
    stop("`path` must be one file path ending in .", format, ".", call. = FALSE)
  }
  if (!is.null(digits) && (format == "csv" || !is_whole(digits, 1L) ||
      digits < 1 || digits > 15)) {
    stop("`digits` must be NULL for CSV, or NULL or a whole number from 1 to 15 for ",
         "HTML and Word.", call. = FALSE)
  }
  if (format != "csv" && !is.null(formula_text)) {
    stop("`formula_text` must be NULL for HTML and Word.", call. = FALSE)
  }
  if (format == "csv" && (!is.character(formula_text) || length(formula_text) != 1L ||
      is.na(formula_text) || !formula_text %in% c("refuse", "prefix", "keep"))) {
    stop("`formula_text` must be \"refuse\", \"prefix\" or \"keep\" for CSV.",
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

  if (format == "docx") {
    if (!officer_available()) {
      stop("Word export needs the optional officer package, version 0.5.0 or later. Install it with ",
           "install.packages(\"officer\"), or export CSV or HTML.", call. = FALSE)
    }
    check_docx_text(review$presentation)
  }

  staged <- tempfile("easyNIS-export-", tmpdir = directory, fileext = paste0(".", format))
  on.exit(if (file.exists(staged)) unlink(staged), add = TRUE)
  if (format == "docx") {
    write_docx(review, digits, staged)
  } else {
    lines <- if (format == "csv") csv_lines(review$presentation, formula_text) else
      html_lines(review, digits)
    connection <- file(staged, open = "wb")
    tryCatch(writeLines(enc2utf8(lines), connection, sep = "\n", useBytes = TRUE),
      finally = close(connection))
  }
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

csv_lines <- function(presentation, formula_text) {
  quote <- function(x) {
    x <- enc2utf8(as.character(x))
    ifelse(is.na(x), "", paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\""))
  }
  numeric <- vapply(presentation, is.numeric, logical(1))
  # Leading characters that spreadsheet programs can treat as a formula (OWASP),
  # including full-width = + - @.
  formula <- lapply(presentation[!numeric], function(x) {
    x <- as.character(x)
    !is.na(x) & grepl("^[-=+@\t\r\n\uff1d\uff0b\uff0d\uff20]", x)
  })
  if (formula_text == "refuse" && any(unlist(formula))) {
    cells <- unlist(lapply(names(formula), function(column) {
      rows <- presentation$id[formula[[column]]]
      if (length(rows)) paste0(column, " in row '", rows, "'")
    }))
    stop("CSV text cells begin with a character that spreadsheets can run as a formula ",
      "(=, +, -, @, their full-width forms, tab, carriage return or line feed): ",
      paste(cells, collapse = ", "),
      ". Change the text or set `formula_text` to \"prefix\" or \"keep\".", call. = FALSE)
  }
  cells <- lapply(names(presentation), function(column) {
    if (numeric[[column]]) return(exact_number(presentation[[column]]))
    text <- as.character(presentation[[column]])
    if (formula_text == "prefix") text <- ifelse(formula[[column]], paste0("'", text), text)
    quote(text)
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

presentation_display <- function(review, digits) {
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
  cells <- cbind(enc2utf8(presentation$label), presentation$statistic,
    enc2utf8(presentation$unit), presentation$estimand,
    hidden(rounded(presentation$estimate)), hidden(rounded(presentation$se)),
    hidden(interval), rounded_exact(presentation$df),
    hidden(rounded_exact(presentation$unweighted_n)), unname(status),
    rounded_exact(presentation$confidence))
  header <- c("Label", "Statistic", "Unit", "Estimand", "Estimate", "SE", "Interval",
    "df", "Unweighted discharges", "Disclosure status", "Confidence level (0 to 1)")
  policy <- review$provenance$policy
  notes <- c(
    "Experimental table; not analysis ready. Annual support and scientific approval are pending.",
    "Unweighted discharges are included discharges with an observed outcome, not patients. Estimates and intervals are survey weighted.",
    paste0("Disclosure review suppressed checked unweighted counts from ",
      exact_number(policy$suppress[[1L]]), " to ", exact_number(policy$suppress[[2L]]),
      " inclusive; zero counts: ", policy$zero,
      "; minimum contributing hospitals: ", exact_number(policy$min_hospitals),
      "; declared margins: ", length(policy$margins), "."),
    "Complementary suppression is a bounded greedy procedure. Larger combinations of declared margins remain unchecked. Undeclared relations, other tables and external publications require human review.",
    if (is.null(digits)) "Values are exact." else
      paste0("Estimates, SEs and intervals are rounded to ", digits,
        " significant digits; counts, df and confidence levels are exact."))
  list(title = "easyNIS experimental descriptive table", header = header,
    cells = unname(cells), notes = notes)
}

html_lines <- function(review, digits) {
  display <- presentation_display(review, digits)
  row <- function(x, tag) paste0("<tr>", paste0("<", tag, ">", escape_html(x), "</", tag,
    ">", collapse = ""), "</tr>")
  c("<!DOCTYPE html>", "<html lang=\"en\">", "<head>", "<meta charset=\"utf-8\">",
    paste0("<title>", display$title, "</title>"),
    "<style>table{border-collapse:collapse}th,td{border:1px solid #888;padding:4px 8px;text-align:left}</style>",
    "</head>", "<body>", "<table>",
    paste0("<caption>", display$title, "</caption>"),
    paste0("<thead>", row(display$header, "th"), "</thead>"), "<tbody>",
    apply(display$cells, 1L, row, tag = "td"), "</tbody>", "</table>", "<ul>",
    paste0("<li>", escape_html(display$notes), "</li>"), "</ul>", "</body>", "</html>")
}

officer_available <- function() {
  requireNamespace("officer", quietly = TRUE) &&
    utils::packageVersion("officer") >= "0.5.0"
}

# Characters that XML 1.0, and therefore a Word document, cannot contain:
# control characters other than tab, carriage return and line feed, and the
# noncharacters U+FFFE and U+FFFF.
check_docx_text <- function(presentation) {
  disallowed <- c(1:8, 11:12, 14:31, 0xFFFE, 0xFFFF)
  invalid <- lapply(presentation[c("label", "unit")], function(x) {
    vapply(enc2utf8(x), function(text) any(utf8ToInt(text) %in% disallowed), logical(1),
      USE.NAMES = FALSE)
  })
  if (any(unlist(invalid))) {
    cells <- unlist(lapply(names(invalid), function(column) {
      rows <- presentation$id[invalid[[column]]]
      if (length(rows)) paste0(column, " in row '", rows, "'")
    }))
    stop("Word documents cannot contain control characters other than tab, ",
      "carriage return and line feed, or U+FFFE and U+FFFF: ",
      paste(cells, collapse = ", "), ".", call. = FALSE)
  }
  invisible(TRUE)
}

write_docx <- function(review, digits, target) {
  display <- presentation_display(review, digits)
  cells <- as.data.frame(display$cells, stringsAsFactors = FALSE)
  names(cells) <- display$header
  document <- officer::read_docx()
  document <- officer::body_set_default_section(document, officer::prop_section(
    page_size = officer::page_size(width = 8.5, height = 11, orient = "landscape"),
    page_margins = officer::page_mar(bottom = 0.5, top = 0.5, right = 0.5, left = 0.5,
      header = 0.3, footer = 0.3)))
  document <- officer::docx_set_paragraph_style(document, "easyNISTable", "easyNIS table",
    base_on = "Normal", fp_t = officer::fp_text_lite(font.size = 8))
  document <- officer::body_add_par(document, display$title, style = "Table Caption")
  document <- officer::body_add_blocks(document, officer::block_list(officer::block_table(cells,
    properties = officer::prop_table(style = "table_template",
      layout = officer::table_layout("fixed"),
      colwidths = officer::table_colwidths(docx_widths(display)),
      stylenames = officer::table_stylenames(list("easyNIS table" = names(cells)))),
    alignment = c("l", "l", "l", "l", "r", "r", "r", "r", "r", "l", "r"))))
  body <- officer::docx_body_xml(document)
  # Narrow left and right cell margins to 0.04 inch, before tblLook as the
  # schema orders table properties.
  look <- xml2::xml_find_first(body, "//w:tbl/w:tblPr/w:tblLook")
  xml2::xml_add_sibling(look, "w:tblCellMar", .where = "before")
  margins <- xml2::xml_find_first(body, "//w:tbl/w:tblPr/w:tblCellMar")
  for (side in c("w:left", "w:right")) {
    xml2::xml_add_child(margins, side, "w:w" = "58", "w:type" = "dxa")
  }
  # Keep each row on one page so interval bounds stay with their row.
  for (row in xml2::xml_find_all(body, "//w:tbl/w:tr")) {
    properties <- xml2::xml_find_first(row, "w:trPr")
    if (inherits(properties, "xml_missing")) {
      xml2::xml_add_child(row, "w:trPr", .where = 0L)
      properties <- xml2::xml_find_first(row, "w:trPr")
    }
    xml2::xml_add_child(properties, "w:cantSplit")
  }
  for (note in display$notes) document <- officer::body_add_par(document, note)
  print(document, target = target)
  invisible(target)
}

# Column widths in inches sharing the 10 inch landscape Letter text width. Each
# column needs its 0.08 inch cell margins plus about 0.07 inch per character of
# its longest word at 8 points. When everything fits, spare width is shared in
# proportion. Otherwise header words and package text (statistic, estimand,
# df, status, confidence level and `Suppressed`) keep their full width, and
# caller labels, units and long estimates share the rest, wrapping within their
# cells. Words count at most 24 characters, so one long unbroken label cannot
# take most of the page.
docx_widths <- function(display) {
  longest <- function(x) min(24L, max(c(0L, nchar(unlist(strsplit(x, "\\s+"))))))
  fixed_text <- display$cells
  fixed_text[, c(1L, 3L)] <- ""
  fixed_text[, c(5:7, 9L)][fixed_text[, c(5:7, 9L)] != "Suppressed"] <- ""
  inches <- function(characters) 0.08 + 0.07 * pmax(4L, characters)
  need <- inches(apply(rbind(display$header, display$cells), 2L, longest))
  floor <- inches(apply(rbind(display$header, fixed_text), 2L, longest))
  if (sum(need) <= 10) return(need + (10 - sum(need)) * need / sum(need))
  if (sum(floor) >= 10) return(10 * floor / sum(floor))
  floor + (10 - sum(floor)) * (need - floor) / sum(need - floor)
}
