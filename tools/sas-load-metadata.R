# Development-only audit of the saved HCUP SAS load-program grammar.
# Programs are read as text, never executed; missing tokens remain literal facts.
parse_sas_load <- function(lines, layout) {
  fail <- function(message) stop("Invalid SAS load program: ", message, call. = FALSE)
  capture <- function(pattern, text) {
    result <- regmatches(text, regexec(pattern, text, perl = TRUE))
    if (length(result) != 1L || !length(result[[1L]])) fail("unsupported syntax.")
    result[[1L]][-1L]
  }
  # SAS comments and statement separators have no effect inside quoted text.
  chars <- strsplit(paste(lines, collapse = "\n"), "", fixed = TRUE)[[1L]]
  cleaned <- chars
  quote <- ""
  block <- comment <- FALSE
  start <- TRUE
  ends <- integer()
  i <- 1L
  while (i <= length(chars)) {
    char <- chars[i]
    next_char <- if (i < length(chars)) chars[i + 1L] else ""
    if (block) {
      if (char != "\n") cleaned[i] <- " "
      if (char == "*" && next_char == "/") {
        cleaned[i + 1L] <- " "
        block <- FALSE
        i <- i + 1L
      }
    } else if (comment) {
      if (char != "\n") cleaned[i] <- " "
      if (char == ";") comment <- FALSE
    } else if (nzchar(quote)) {
      if (char == quote) {
        if (next_char == quote) i <- i + 1L else quote <- ""
      }
    } else if (char == "/" && next_char == "*") {
      cleaned[i:(i + 1L)] <- " "
      block <- TRUE
      i <- i + 1L
    } else if (char == "*" && start) {
      cleaned[i] <- " "
      comment <- TRUE
    } else if (char == ";") {
      ends <- c(ends, i)
      start <- TRUE
    } else if (char %in% c("'", '"')) {
      quote <- char
      start <- FALSE
    } else if (!grepl("[[:space:]]", char)) start <- FALSE
    i <- i + 1L
  }
  if (block) fail("unclosed block comment.")
  if (nzchar(quote)) fail("unclosed quoted text.")
  if (comment) fail("unclosed statement comment.")
  text <- paste(cleaned, collapse = "")
  starts <- c(1L, ends + 1L)
  stops <- c(ends - 1L, length(chars))
  statements <- trimws(substring(text, starts, pmax(starts, stops)))
  statements <- statements[nzchar(statements)]
  one <- function(prefix) {
    found <- statements[grepl(paste0("^", prefix, "\\b"), statements,
                              perl = TRUE, ignore.case = TRUE)]
    if (length(found) != 1L) fail(paste("missing or repeated", prefix))
    found
  }
  dataset <- capture("^DATA\\s+([A-Za-z][A-Za-z0-9_]*)$", one("DATA"))
  infile <- capture("^INFILE\\s+'([^']+)'\\s+LRECL\\s*=\\s*([0-9]+)$", one("INFILE"))
  if (toupper(dataset) != layout$dataset ||
      toupper(infile[1L]) != paste0(layout$dataset, ".ASC") ||
      as.numeric(infile[2L]) != layout$record_length) fail("dataset or record length mismatch.")
  input <- sub("^INPUT\\s+", "", one("INPUT"), perl = TRUE)
  rows <- trimws(strsplit(input, "\n", fixed = TRUE)[[1L]])
  rows <- rows[nzchar(rows)]
  assigned <- lapply(rows, function(row) capture(
    "^@([0-9]+)\\s+([A-Za-z][A-Za-z0-9_]*)\\s+(\\$?[A-Za-z0-9]+\\.)$", row))
  assigned <- do.call(rbind, assigned)
  fields <- data.frame(name = assigned[, 2L], start = as.numeric(assigned[, 1L]),
                       informat = assigned[, 3L], stringsAsFactors = FALSE)
  if (!identical(fields$name, layout$fields$name) ||
      !identical(fields$start, as.double(layout$fields$start))) fail("INPUT fields or positions mismatch.")
  definitions <- statements[grepl("^INVALUE\\b", statements, perl = TRUE, ignore.case = TRUE)]
  definitions <- lapply(definitions, function(definition) {
    parts <- strsplit(definition, "\n", fixed = TRUE)[[1L]]
    parts <- trimws(parts[nzchar(trimws(parts))])
    name <- capture("^INVALUE\\s+([A-Z][A-Z0-9_]*)$", parts[1L])
    if (length(parts) < 3L) fail("incomplete INVALUE.")
    fallback <- capture("^OTHER\\s*=\\s*\\(\\|([A-Za-z0-9.]+)\\|\\)$", tail(parts, 1L))
    mappings <- lapply(parts[2L:(length(parts) - 1L)], function(row) capture(
      "^'(-?[0-9]+(?:\\.[0-9]+)?)'\\s*=\\s*(\\.[A-Z]?)$", row))
    mappings <- do.call(rbind, mappings)
    if (anyDuplicated(mappings[, 1L])) fail("duplicate raw token in INVALUE.")
    list(name = paste0(name, "."), fallback = fallback, mappings = data.frame(
      informat = paste0(name, "."), raw_token = mappings[, 1L],
      sas_missing_token = mappings[, 2L], stringsAsFactors = FALSE))
  })
  names(definitions) <- vapply(definitions, `[[`, character(1), "name")
  if (anyDuplicated(names(definitions))) fail("duplicate INVALUE definition.")
  widths <- decimals <- numeric(nrow(fields))
  types <- character(nrow(fields))
  for (i in seq_len(nrow(fields))) {
    format <- fields$informat[i]
    if (grepl("^\\$CHAR[0-9]+\\.$", format)) {
      widths[i] <- as.numeric(sub("^\\$CHAR([0-9]+)\\.$", "\\1", format))
      types[i] <- "Char"
    } else {
      types[i] <- "Num"
      fallback <- if (format == "1.") format else {
        if (!format %in% names(definitions)) fail("undefined INPUT informat.")
        definitions[[format]]$fallback
      }
      size <- capture("^([0-9]+)\\.([0-9]*)$", fallback)
      widths[i] <- as.numeric(size[1L])
      decimals[i] <- if (size[2L] == "") 0 else as.numeric(size[2L])
    }
  }
  if (any(widths != layout$fields$end - layout$fields$start + 1L) ||
      any(decimals != layout$fields$decimals) || any(types != layout$fields$type)) {
    fail("informat width, precision or type mismatch.")
  }
  fields$width <- widths
  fields$decimals <- decimals
  fields$type <- types
  used <- definitions[intersect(unique(fields$informat), names(definitions))]
  mappings <- if (length(used)) do.call(rbind, lapply(used, `[[`, "mappings")) else
    data.frame(informat = character(), raw_token = character(), sas_missing_token = character())
  rownames(mappings) <- NULL
  list(fields = fields, mappings = mappings)
}

audit_sas_loads <- function(cache = "docs/references/local/annual-documents",
                           output = ".audit/sas-load-audit") {
  if (file.exists(output) || dir.exists(output)) {
    stop("Choose a new audit output directory.", call. = FALSE)
  }
  rows <- maps <- refs <- list()
  for (year in 2017:2022) for (component in c("Core", "Hospital", "Severity", "DX_PR_GRPS")) {
    if (year == 2017L && component == "DX_PR_GRPS") next
    suffix <- if (year %in% c(2019L, 2020L)) "_V2" else ""
    stem <- paste0("NIS_", year, "_", component, suffix)
    layout_file <- paste0("FileSpecifications_", stem, ".TXT")
    sas_file <- paste0("SASLoad_", stem, ".SAS")
    paths <- file.path(cache, c(layout_file, sas_file))
    if (!all(file.exists(paths))) stop("Missing cached layout or SAS program: ", stem, call. = FALSE)
    lines <- readLines(paths[1L], warn = FALSE)
    layout <- if (component == "Core") parse_core_layout(lines, year) else
      parse_nis_layout(lines, year, component)
    parsed <- parse_sas_load(readLines(paths[2L], warn = FALSE), layout)
    key <- length(refs) + 1L
    rows[[key]] <- cbind(year = year, component = component, parsed$fields)
    maps[[key]] <- cbind(year = rep(year, nrow(parsed$mappings)),
                         component = rep(component, nrow(parsed$mappings)), parsed$mappings)
    refs[[key]] <- data.frame(year = year, component = component,
      layout_source = paste0("https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/", layout_file),
      sas_source = paste0("https://hcup-us.ahrq.gov/db/nation/nis/tools/pgms/", sas_file),
      layout_md5 = unname(tools::md5sum(paths[1L])), sas_md5 = unname(tools::md5sum(paths[2L])),
      field_count = nrow(parsed$fields), mapping_count = nrow(parsed$mappings),
      review_status = "provisional", stringsAsFactors = FALSE)
  }
  # Validate every pair before creating output; publish the three files together.
  parent <- dirname(output)
  if (!dir.exists(parent)) stop("Audit output parent must exist.", call. = FALSE)
  staged <- tempfile("sas-load-", tmpdir = parent)
  dir.create(staged)
  on.exit(unlink(staged, recursive = TRUE), add = TRUE)
  tables <- list(fields = do.call(rbind, rows), mappings = do.call(rbind, maps),
                 references = do.call(rbind, refs))
  for (name in names(tables)) {
    utils::write.csv(tables[[name]], file.path(staged, paste0(name, ".csv")), row.names = FALSE)
  }
  if (file.exists(output) || dir.exists(output) || !file.rename(staged, output)) {
    stop("Could not publish audit directory.", call. = FALSE)
  }
  invisible(tables)
}
