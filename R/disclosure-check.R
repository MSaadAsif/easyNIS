#' Check published files for disclosure risks
#'
#' Scans CSV, HTML, Markdown, Quarto Markdown, and DOCX files under `path` for
#' restricted identifiers and small values in count-like CSV columns.
#' @param path A file or directory to scan recursively.
#' @param tokens Restricted identifier strings to find.
#' @param count_cols Regular expression identifying count columns.
#' @param threshold Largest count value to flag (exclusive of zero).
#' @param error If `TRUE`, abort when violations are found.
#' @return A tibble of violations, invisibly.
#' @examples
#' dir <- tempfile(); dir.create(dir)
#' write.csv(data.frame(n = c(3, 20)), file.path(dir, "table.csv"), row.names = FALSE)
#' nis_disclosure_check(dir)
#' @export
nis_disclosure_check <- function(path,
                                 tokens = c("HOSP_NIS", "KEY_NIS", "NIS_STRATUM"),
                                 count_cols = "(^n$|count|unweighted)",
                                 threshold = 10,
                                 error = TRUE) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    cli::cli_abort("`path` must name an existing file or directory.")
  }
  if (!is.character(tokens) || anyNA(tokens) || !is.character(count_cols) ||
      length(count_cols) != 1L || is.na(count_cols) ||
      !is.numeric(threshold) || length(threshold) != 1L || is.na(threshold) ||
      !is.finite(threshold) || threshold < 0 || !is.logical(error) ||
      length(error) != 1L || is.na(error)) {
    cli::cli_abort("Invalid disclosure check options.")
  }
  files <- if (dir.exists(path)) list.files(path, recursive = TRUE, full.names = TRUE) else path
  rows <- list()
  add <- function(file, kind, column = NA_character_, row = NA_integer_, value = NA_character_) {
    rows[[length(rows) + 1L]] <<- data.frame(file = file, kind = kind, column = column,
      row = row, value = as.character(value), stringsAsFactors = FALSE)
  }
  scan_text <- function(file, content) {
    content <- gsub("<[^>]*>", " ", content)
    for (token in tokens) if (grepl(token, content, fixed = TRUE)) add(file, "restricted_token", value = token)
  }
  for (file in files) {
    ext <- tolower(tools::file_ext(file))
    if (ext == "csv") {
      data <- utils::read.csv(file, check.names = FALSE, stringsAsFactors = FALSE,
        na.strings = c("", "NA", "*", "-", "Suppressed"))
      for (token in tokens) {
        if (any(grepl(token, names(data), fixed = TRUE))) add(file, "restricted_token", value = token)
        for (column in names(data)) {
          hit <- which(!is.na(data[[column]]) & grepl(token, as.character(data[[column]]), fixed = TRUE))
          for (i in hit) add(file, "restricted_token", column, i + 1L, token)
        }
      }
      cols <- grep(count_cols, names(data), value = TRUE, ignore.case = TRUE)
      for (column in cols) {
        vals <- suppressWarnings(as.numeric(as.character(data[[column]])))
        hit <- which(!is.na(vals) & vals > 0 & vals <= threshold)
        for (i in hit) add(file, "small_count", column, i + 1L, vals[i])
      }
    } else if (ext %in% c("html", "htm", "md", "qmd")) {
      scan_text(file, paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
    } else if (ext == "docx") {
      dest <- tempfile(); dir.create(dest)
      utils::unzip(file, files = "word/document.xml", exdir = dest)
      xml <- file.path(dest, "word", "document.xml")
      if (file.exists(xml)) scan_text(file, paste(readLines(xml, warn = FALSE), collapse = "\n"))
    }
  }
  out <- if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble(
    file = character(), kind = character(), column = character(), row = integer(), value = character())
  if (nrow(out) && error) cli::cli_abort(c("Disclosure violations found:", "*" = "{nrow(out)} violation{?s} across {.val {unique(basename(out$file))}}."))
  if (!nrow(out)) cli::cli_alert_success("No disclosure violations found.")
  invisible(out)
}
