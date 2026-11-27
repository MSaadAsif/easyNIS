#' Scan a publication folder for disclosure risks
#'
#' Check CSV, TSV, XLSX, HTML, Markdown, text, and DOCX files in a folder
#' and its subfolders. The scan flags known HCUP identifier names and
#' potential unmasked counts of 1 through 10 in recognizable count columns
#' or explicit statements such as "n = 5" and "5 discharges".
#'
#' @param path Directory containing the files you intend to publish.
#' @param error If \code{TRUE}, stop with class \code{easyNIS_output_scan}
#'   when any finding is present. The condition carries a \code{findings}
#'   data frame.
#' @return A data frame with \code{file} (relative path), \code{location}
#'   (file, document part, sheet, table or column), \code{issue}
#'   (\code{restricted_identifier}, \code{small_count} or \code{scan_error}),
#'   and \code{field} (the recognized identifier name, or \code{NA}).
#'   A finding can represent several matches in one location. Cell contents
#'   and reader diagnostics are omitted.
#' @details
#' This check is heuristic. An identifier name can appear in a legitimate
#' methods description. Review unsupported files (including images and PDFs),
#' renamed identifiers, unfamiliar table layouts, and counts recoverable from
#' totals, percentages, or other releases by hand.
#'
#' XLSX uses \pkg{readxl}. HTML and DOCX use \pkg{xml2}, and Markdown also
#' uses \pkg{commonmark}. A supported file that cannot be read, including
#' when an optional reader is missing, produces a \code{scan_error}.
#' @family disclosure
#' @seealso [Check disclosure before sharing results](https://msaadasif.github.io/easyNIS/articles/disclosure.html)
#' @export
#' @examples
#' folder <- tempfile()
#' dir.create(folder)
#' writeLines(c("group,n", "A,3", "B,20"), file.path(folder, "table.csv"))
#' nis_scan_outputs(folder)
#' unlink(folder, recursive = TRUE)
nis_scan_outputs <- function(path, error = FALSE) {
  if (!rlang::is_string(path) || !dir.exists(path) || file.access(path, 4L) != 0L) {
    cli::cli_abort("{.arg path} must be a readable directory.")
  }
  if (!rlang::is_bool(error)) {
    cli::cli_abort("{.arg error} must be TRUE or FALSE.")
  }

  files <- list.files(path, all.files = TRUE, recursive = TRUE)
  findings <- dplyr::bind_rows(
    data.frame(file = character(), nis_scan_finding(character(), character())),
    lapply(files, function(file) nis_scan_file(file.path(path, file), file))
  )
  if (error && nrow(findings)) {
    cli::cli_abort(
      "Publication scan found {nrow(findings)} issue{?s} in {length(unique(findings$file))} file{?s}.",
      class = "easyNIS_output_scan",
      findings = findings
    )
  }
  findings
}

nis_scan_finding <- function(location, issue, field = rep(NA_character_, length(issue))) {
  data.frame(location = location, issue = issue, field = field)
}

nis_scan_file <- function(path, file) {
  extension <- tolower(tools::file_ext(file))
  reader <- switch(
    extension,
    csv = ,
    tsv = nis_scan_delimited,
    xlsx = nis_scan_workbook,
    html = ,
    htm = ,
    md = ,
    markdown = ,
    qmd = ,
    rmd = nis_scan_markup,
    txt = nis_scan_plain,
    docx = nis_scan_word
  )
  if (is.null(reader)) {
    return(NULL)
  }
  result <- tryCatch(
    reader(path, extension),
    error = function(e) nis_scan_finding("file", "scan_error"),
    warning = function(w) nis_scan_finding("file", "scan_error")
  )
  if (nrow(result)) {
    data.frame(file = file, result)
  }
}

.nis_scan_fields <- c(
  "KEY_NIS",
  "KEY_NRD",
  "KEY_ED",
  "RECNUM",
  "HOSP_NIS",
  "HOSP_KID",
  "HOSP_NRD",
  "HOSP_ED",
  "HOSPID",
  "DSHOSPID",
  "AHAID",
  "IDNUMBER",
  "NRD_VISITLINK",
  "VISITLINK"
)

.nis_scan_count_units <- "(?:discharges?|admissions?|hospitalizations?|patients?|cases?|deaths?|stays?|encounters?|records?|observations?|events?|people)"

nis_scan_text <- function(text, location, source = character(), key_header = FALSE) {
  fields <- .nis_scan_fields[vapply(
    .nis_scan_fields,
    function(field) {
      any(grepl(paste0("\\b", field, "\\b"), c(text, source), ignore.case = TRUE, perl = TRUE))
    },
    logical(1)
  )]
  # The pre-2012 name KEY is also common in ordinary prose.
  if (key_header || any(grepl("\\bKEY\\s*[:=]\\s*[0-9]", text, ignore.case = TRUE, perl = TRUE))) {
    fields <- c(fields, "KEY")
  }

  text <- nis_scan_trim(text)
  text <- gsub(
    "(?:[<>\u2264\u2265]=?|\\b(?:up to|at most|less than|no more than|fewer than))\\s*[0-9]+",
    "",
    text,
    ignore.case = TRUE,
    perl = TRUE
  )
  small <- "(?<![\\w.,+\\-\u2013])[0]*(?:10|[1-9])(?:\\.0+)?(?![\\w.,%])(?!\\s*%)"
  label <- paste0("\\b(?:n|counts?|sample size|number of ", .nis_scan_count_units, ")\\s*[:=]\\s*")
  unit <- paste0("\\s+", .nis_scan_count_units, "\\b")
  # A period or comma after an integer can end a sentence or clause.
  pattern <- paste0("(?:", label, small, "|", small, unit, ")")
  text <- gsub("(?<=[0-9])[.,](?![0-9])", " ", text, perl = TRUE)
  issues <- rep("restricted_identifier", length(fields))
  if (any(grepl(pattern, text, ignore.case = TRUE, perl = TRUE))) {
    issues <- c(issues, "small_count")
    fields <- c(fields, NA_character_)
  }
  nis_scan_finding(rep(location, length(issues)), issues, fields)
}

nis_scan_trim <- function(text) {
  trimws(gsub("[\u00a0\u202f]", " ", text))
}

nis_scan_count_heading <- function(text) {
  heading <- trimws(gsub("[^a-z]+", " ", tolower(text)))
  heading <- sub("^(?:no|number) of ", "", heading, perl = TRUE)
  modifier <- "(?:unweighted|weighted|sampled|raw|total|overall|event|case|discharge|patient|record|cell|group|sample|cohort)"
  name <- paste0("(?:n|counts?|frequenc(?:y|ies)|freq|sample size|", .nis_scan_count_units, ")")
  grepl(paste0("^(?:", modifier, " )*", name, "(?: ", modifier, ")*$"), heading, perl = TRUE)
}

nis_scan_small_cell <- function(text) {
  number <- suppressWarnings(as.numeric(sub(
    "\\s*\\(\\s*[0-9]+(?:\\.[0-9]+)?\\s*%?\\s*\\)$",
    "",
    nis_scan_trim(text),
    perl = TRUE
  )))
  any(number >= 1 & number <= 10 & number == floor(number), na.rm = TRUE)
}

nis_scan_table <- function(cells, location, headers = 1L) {
  if (!length(cells)) {
    return(nis_scan_finding(character(), character()))
  }
  heading <- cells[headers, , drop = FALSE]
  counts <- which(colSums(matrix(nis_scan_count_heading(heading), nrow(heading))) > 0)
  values <- cells[-headers, , drop = FALSE]
  small <- counts[vapply(counts, function(i) nis_scan_small_cell(values[, i]), logical(1))]
  rbind(
    nis_scan_text(cells, location, key_header = any(toupper(nis_scan_trim(heading)) == "KEY", na.rm = TRUE)),
    nis_scan_finding(paste(location, "column", small, recycle0 = TRUE), rep("small_count", length(small)))
  )
}

nis_scan_plain <- function(path, extension) {
  nis_scan_text(readLines(path, warn = FALSE, encoding = "UTF-8"), "file")
}

nis_scan_delimited <- function(path, extension) {
  if (file.size(path) == 0) {
    return(nis_scan_finding(character(), character()))
  }
  separator <- if (extension == "csv") "," else "\t"
  cells <- utils::read.table(
    path,
    sep = separator,
    quote = '"',
    comment.char = "",
    colClasses = "character",
    na.strings = NULL,
    fill = TRUE,
    row.names = NULL,
    fileEncoding = "UTF-8-BOM"
  )
  nis_scan_table(as.matrix(cells), "file")
}

nis_scan_workbook <- function(path, extension) {
  sheets <- readxl::excel_sheets(path)
  dplyr::bind_rows(lapply(seq_along(sheets), function(i) {
    cells <- as.matrix(readxl::read_xlsx(
      path,
      sheet = i,
      col_names = FALSE,
      col_types = "text",
      .name_repair = "minimal"
    ))
    count_headers <- matrix(nis_scan_count_heading(cells), nrow(cells), ncol(cells))
    header <- which(rowSums(count_headers) > 0)[1L]
    nis_scan_table(cells, paste("sheet", i), headers = if (is.na(header)) 1L else header)
  }))
}

nis_scan_markup <- function(path, extension) {
  source <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!any(nzchar(trimws(source)))) {
    return(nis_scan_finding(character(), character()))
  }
  html <- paste(source, collapse = "\n")
  if (!extension %in% c("html", "htm")) {
    html <- commonmark::markdown_html(html, extensions = "table")
  }
  doc <- xml2::read_html(html, encoding = "UTF-8", options = c("RECOVER", "NOERROR", "NOWARNING", "NONET"))
  xml2::xml_remove(xml2::xml_find_all(doc, ".//script | .//style"))
  parts <- xml2::xml_find_all(doc, ".//p | .//li | .//div | .//h1 | .//h2 | .//h3 | .//h4 | .//h5 | .//h6")
  tables <- xml2::xml_find_all(doc, ".//table")
  unique(dplyr::bind_rows(
    nis_scan_text(c(xml2::xml_text(doc), xml2::xml_text(parts)), "file", source),
    lapply(seq_along(tables), function(i) nis_scan_html_table(tables[[i]], paste("table", i)))
  ))
}

nis_scan_html_table <- function(table, location) {
  rows <- xml2::xml_find_all(table, "./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr")
  cells <- lapply(rows, xml2::xml_find_all, xpath = "./th | ./td")
  headers <- which(vapply(cells, function(row) all(xml2::xml_name(row) == "th"), logical(1)))
  widths <- lapply(cells, function(row) xml2::xml_attr(row, "colspan"))
  heights <- lapply(cells, function(row) xml2::xml_attr(row, "rowspan"))
  grid <- nis_scan_grid(lapply(cells, xml2::xml_text), widths, heights)
  nis_scan_table(grid, location, headers = union(1L, headers))
}

nis_scan_span <- function(text, maximum) {
  span <- suppressWarnings(as.integer(text))
  pmax(1L, pmin(maximum, ifelse(is.na(span), 1L, span)))
}

nis_scan_grid <- function(rows, widths, heights) {
  # Keep data columns aligned with their headings across merged cells.
  occupied <- integer()
  grid <- vector("list", length(rows))
  for (i in seq_along(rows)) {
    row <- character(length(occupied))
    column <- 1L
    width <- nis_scan_span(widths[[i]], 1000L)
    height <- nis_scan_span(heights[[i]], length(rows))
    for (j in seq_along(rows[[i]])) {
      while (isTRUE(occupied[column] >= i)) {
        column <- column + 1L
      }
      slots <- seq.int(column, length.out = width[j])
      row[slots] <- rows[[i]][j]
      occupied[slots] <- i + height[j] - 1L
      column <- max(slots) + 1L
    }
    grid[[i]] <- row
  }
  columns <- max(c(0L, lengths(grid)))
  matrix(
    as.character(unlist(lapply(grid, function(row) c(row, rep(NA_character_, columns - length(row)))))),
    ncol = columns,
    nrow = length(rows),
    byrow = TRUE
  )
}

nis_scan_word <- function(path, extension) {
  members <- utils::unzip(path, list = TRUE)$Name
  if (!"word/document.xml" %in% members) {
    stop("Missing Word document XML.")
  }
  parts <- grep("^word/(document|header[0-9]+|footer[0-9]+|footnotes|endnotes|comments)\\.xml$", members, value = TRUE)
  dplyr::bind_rows(lapply(parts, function(part) {
    connection <- unz(path, part, open = "rb")
    on.exit(close(connection))
    doc <- xml2::read_xml(connection, options = "NONET")
    ns <- c(w = xml2::xml_find_chr(doc, "namespace-uri(/*)"))
    paragraphs <- xml2::xml_find_all(doc, ".//w:p", ns)
    tables <- xml2::xml_find_all(doc, ".//w:tbl", ns)
    dplyr::bind_rows(
      nis_scan_text(vapply(paragraphs, nis_scan_word_text, character(1), ns = ns), part),
      lapply(seq_along(tables), function(i) nis_scan_word_table(tables[[i]], paste(part, "table", i), ns))
    )
  }))
}

nis_scan_word_text <- function(node, ns) {
  paste(xml2::xml_text(xml2::xml_find_all(node, ".//w:t | .//w:delText", ns)), collapse = "")
}

nis_scan_word_table <- function(table, location, ns) {
  rows <- xml2::xml_find_all(table, "./w:tr", ns)
  cells <- lapply(rows, xml2::xml_find_all, xpath = "./w:tc", ns = ns)
  headers <- which(vapply(
    rows,
    function(row) length(xml2::xml_find_all(row, "./w:trPr/w:tblHeader", ns)) > 0L,
    logical(1)
  ))
  widths <- lapply(cells, function(row) {
    vapply(row, xml2::xml_find_chr, character(1), xpath = "string(./w:tcPr/w:gridSpan/@w:val)", ns = ns)
  })
  heights <- lapply(cells, function(row) rep(1L, length(row)))
  text <- lapply(cells, function(row) vapply(row, nis_scan_word_text, character(1), ns = ns))
  grid <- nis_scan_grid(text, widths, heights)
  nis_scan_table(grid, location, headers = union(1L, headers))
}
