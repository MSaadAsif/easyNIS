# Run from the repository root with the 13 public SAS Core load programs in
# a local directory. See docs/nis-core-layouts.md for the download command.

parse_informat <- function(program, format) {
  if (startsWith(format, "$CHAR")) {
    return(list(
      width = as.integer(sub("^[$]CHAR", "", format)),
      decimals = NA_integer_,
      missing = ""
    ))
  }
  start <- grep(paste0("^\\s*INVALUE ", format, "\\b"), program)
  stopifnot(length(start) == 1L)
  body <- program[seq.int(start + 1L, length(program))]
  body <- body[seq_len(match(TRUE, grepl("^\\s*;", body)) - 1L)]
  missing <- grep("^\\s*'", body, value = TRUE)
  missing <- sub("^\\s*'([^']+)'.*$", "\\1", missing)
  other <- grep("OTHER", body, value = TRUE)
  match <- regmatches(other, regexec("[(][|]([0-9]+)[.]([0-9]*)[|][)]", other))[[1L]]
  stopifnot(length(other) == 1L, length(match) == 3L)
  list(
    width = as.integer(match[[2L]]),
    decimals = if (nzchar(match[[3L]])) as.integer(match[[3L]]) else 0L,
    missing = paste(missing, collapse = ";")
  )
}

parse_program <- function(file, year) {
  program <- readLines(file, warn = FALSE)
  url <- sub("^URL Source: ", "", grep("^URL Source: ", program, value = TRUE))
  if (!length(url)) {
    url <- paste0("https://hcup-us.ahrq.gov/db/nation/nis/tools/pgms/", sub("[.]txt$", "", basename(file)))
  }
  infile <- grep("^INFILE ", program, value = TRUE)
  width <- as.integer(sub("^.*LRECL *= *([0-9]+);.*$", "\\1", infile))
  fields <- grep("^\\s*@", program, value = TRUE)
  pattern <- "^\\s*@([0-9]+)\\s+([A-Za-z_][A-Za-z_0-9]*)\\s+([^ .]+)[.]\\s*$"
  groups <- regmatches(fields, regexec(pattern, fields))
  stopifnot(length(width) == 1L, length(fields) > 0L, all(lengths(groups) == 4L))
  fields <- do.call(rbind, groups)[, -1L, drop = FALSE]
  formats <- unique(fields[, 3L])
  parsed <- stats::setNames(lapply(formats, function(format) parse_informat(program, format)), formats)
  data <- do.call(
    rbind,
    lapply(seq_len(nrow(fields)), function(i) {
      format <- parsed[[fields[i, 3L]]]
      data.frame(year = year, column = fields[i, 2L], start = as.integer(fields[i, 1L]), format)
    })
  )
  stopifnot(
    identical(data$start, c(1L, head(cumsum(data$width) + 1L, -1L))),
    sum(data$width) == width,
    !anyDuplicated(toupper(data$column)),
    "YEAR" %in% data$column,
    length(url) == 1L
  )
  message(year, "  ", width, " bytes  ", nrow(data), " fields  ", url, "  MD5 ", tools::md5sum(file))
  data$source <- url
  data
}

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
years <- 2012:2024
layouts <- lapply(years, function(year) {
  revision <- if (year %in% 2019:2020) "_V2" else ""
  file <- paste0("SASLoad_NIS_", year, "_Core", revision, ".SAS.txt")
  parse_program(file.path(args[[1L]], file), year)
})
utils::write.csv(do.call(rbind, layouts), "inst/extdata/nis-core-layouts.csv", row.names = FALSE, na = "")
