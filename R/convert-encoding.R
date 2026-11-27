# Haven's readers do not return the inbound code page. Inspect the format
# metadata only after a decoding error, for diagnostic column attribution.
# The code page identifiers follow haven's bundled ReadStat format definitions.
nis_convert_declared_encoding <- function(path) {
  input <- file(path, "rb")
  on.exit(close(input), add = TRUE)
  format <- tolower(tools::file_ext(path))
  switch(
    format,
    sav = nis_convert_sav_encoding(input),
    sas7bdat = nis_convert_sas_encoding(input),
    dta = {
      # Stata 118 and later use UTF-8. Older files do not declare an encoding
      # and ReadStat defaults to Windows-1252.
      header <- readBin(input, "raw", n = 31L)
      prefix <- charToRaw("<stata_dta><header><release>")
      if (identical(utils::head(header, length(prefix)), prefix)) {
        release <- as.integer(rawToChar(utils::tail(header, 3L)))
        if (release >= 118L) return("UTF-8")
      }
      "WINDOWS-1252"
    }
  )
}

nis_convert_sas_encoding <- function(input) {
  # SAS7BDAT header byte 71 stores the encoding identifier.
  seek(input, 70L)
  code <- readBin(input, "integer", size = 1L, signed = FALSE, n = 1L)
  if (!length(code)) {
    return(NULL)
  }
  if (code %in% 29:37) {
    return(paste0("ISO-8859-", code - 28L))
  }
  if (code %in% 60:68) {
    return(paste0("WINDOWS-", code + 1190L))
  }
  encodings <- c(
    "0" = "WINDOWS-1252",
    "20" = "UTF-8",
    "28" = "US-ASCII",
    "39" = "ISO-8859-11",
    "40" = "ISO-8859-15",
    stats::setNames(
      paste0("CP", c(437, 850, 852, 857, 858, 862, 864, 865, 866, 869, 874, 921, 922, 1129, 720, 737, 775, 860, 863)),
      41:59
    ),
    "69" = "MACROMAN",
    "70" = "MACARABIC",
    "71" = "MACHEBREW",
    "72" = "MACGREEK",
    "73" = "MACTHAI",
    "75" = "MACTURKISH",
    "76" = "MACUKRAINE",
    "118" = "CP950",
    "119" = "EUC-TW",
    "123" = "BIG-5",
    "125" = "GB18030",
    "126" = "WINDOWS-936",
    "128" = "CP1381",
    "134" = "EUC-JP",
    "136" = "CP949",
    "137" = "CP942",
    "138" = "CP932",
    "140" = "EUC-KR",
    "141" = "CP949",
    "142" = "CP949",
    "163" = "MACICELAND",
    "167" = "ISO-2022-JP",
    "168" = "ISO-2022-KR",
    "169" = "ISO-2022-CN",
    "172" = "ISO-2022-CN-EXT",
    "204" = "WINDOWS-1252",
    "205" = "GB18030",
    "227" = "ISO-8859-14",
    "242" = "ISO-8859-13",
    "245" = "MACCROATIAN",
    "246" = "MACCYRILLIC",
    "247" = "MACROMANIA",
    "248" = "SHIFT_JISX0213"
  )
  unname(as.list(encodings)[[as.character(code)]])
}

nis_convert_sav_encoding <- function(input) {
  # The four-byte layout code at offset 64 determines dictionary byte order.
  seek(input, 64L)
  layout <- readBin(input, "integer", size = 4L, n = 1L, endian = "little")
  endian <- if (layout %in% c(2L, 3L)) "little" else "big"
  ints <- function(n = 1L) readBin(input, "integer", n = n, size = 4L, endian = endian)
  skip <- function(n) {
    stopifnot(length(n) == 1L, n >= 0)
    seek(input, n, origin = "current")
  }
  seek(input, 176L)
  repeat {
    record <- ints()
    encoding <- switch(
      as.character(record),
      "2" = nis_convert_sav_skip_variable(ints, skip),
      "3" = nis_convert_sav_skip_labels(input, ints, skip),
      "6" = {
        skip(80 * ints())
        NULL
      },
      "7" = nis_convert_sav_extension(ints, skip),
      return(NULL)
    )
    if (!is.null(encoding)) return(encoding)
  }
}

nis_convert_sav_skip_variable <- function(ints, skip) {
  fields <- ints(5L)
  skip(8L)
  if (fields[[2L]] != 0L) {
    skip(4 * ceiling(ints() / 4))
  }
  skip(8 * abs(fields[[3L]]))
  NULL
}

nis_convert_sav_skip_labels <- function(input, ints, skip) {
  for (i in seq_len(ints())) {
    skip(8L)
    bytes <- readBin(input, "integer", size = 1L, signed = FALSE, n = 1L)
    skip(8 * ceiling((bytes + 1L) / 8) - 1)
  }
  # A type-4 variable index follows the label entries.
  ints()
  skip(4 * ints())
  NULL
}

nis_convert_sav_extension <- function(ints, skip) {
  extension <- ints(3L)
  # Subtype 3 is the machine-integer record used by ReadStat. Its eighth
  # integer is the original file's character code page.
  if (identical(extension, c(3L, 4L, 8L))) {
    return(nis_convert_sav_code_page(ints(8L)[[8L]]))
  }
  skip(as.double(extension[[2L]]) * extension[[3L]])
  NULL
}

nis_convert_sav_code_page <- function(code) {
  if (code %in% 2:3) {
    return("WINDOWS-1252")
  }
  if (code %in% 28591:28599) {
    return(paste0("ISO-8859-", code - 28590L))
  }
  encodings <- c(
    "1" = "EBCDIC-US",
    "4" = "DEC-KANJI",
    "708" = "ASMO-708",
    "950" = "BIG-5",
    "1200" = "UTF-16LE",
    "1201" = "UTF-16BE",
    "10000" = "MACROMAN",
    "10004" = "MACARABIC",
    "10005" = "MACHEBREW",
    "10006" = "MACGREEK",
    "10007" = "MACCYRILLIC",
    "10010" = "MACROMANIA",
    "10017" = "MACUKRAINE",
    "10021" = "MACTHAI",
    "10029" = "MACCENTRALEUROPE",
    "10079" = "MACICELAND",
    "10081" = "MACTURKISH",
    "10082" = "MACCROATIAN",
    "12000" = "UTF-32LE",
    "12001" = "UTF-32BE",
    "20127" = "US-ASCII",
    "20866" = "KOI8-R",
    "20932" = "EUC-JP",
    "21866" = "KOI8-U",
    "28603" = "ISO-8859-13",
    "28605" = "ISO-8859-15",
    "50220" = "ISO-2022-JP",
    "50221" = "ISO-2022-JP",
    "50222" = "ISO-2022-JP",
    "50225" = "ISO-2022-KR",
    "50229" = "ISO-2022-CN",
    "51932" = "EUC-JP",
    "51936" = "GBK",
    "51949" = "EUC-KR",
    "52936" = "HZ-GB-2312",
    "54936" = "GB18030",
    "65000" = "UTF-7",
    "65001" = "UTF-8"
  )
  encoding <- unname(as.list(encodings)[[as.character(code)]])
  if (is.null(encoding)) paste0("CP", code) else encoding
}
