years <- 2017:2022
output <- "inst/metadata/modern-layouts.csv"
cache <- "docs/references/local/official-layouts"
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
rows <- lapply(years, function(year) {
  revision <- if (year %in% c(2019L, 2020L)) "V2" else "unspecified"
  suffix <- if (revision == "V2") "_V2" else ""
  filename <- paste0("FileSpecifications_NIS_", year, "_Core", suffix, ".TXT")
  url <- paste0("https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/", filename)
  path <- file.path(cache, filename)
  if (!file.exists(path) || file.info(path)$size == 0) {
    staged <- tempfile(tmpdir = cache)
    on.exit(unlink(staged), add = TRUE)
    tryCatch(utils::download.file(url, staged, mode = "wb", quiet = TRUE),
      error = function(error) stop(
        "Official layout download failed. Keep the previous registry unchanged; ",
        "retry when the source is reachable or supply the official file in the ignored cache. ",
        conditionMessage(error), call. = FALSE
      ))
    if (!file.copy(staged, path, overwrite = TRUE)) stop("Could not cache official layout.")
  }
  lines <- readLines(path, warn = FALSE)
  fields <- lines[grepl("^NIS ", lines)]
  names <- trimws(substr(fields, 42L, 70L))
  types <- trimws(substr(fields, 84L, 87L))
  if (anyDuplicated(names)) stop("Duplicated fields in official layout for ", year)
  required <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
  if (!all(required %in% names)) stop("Missing required fields for ", year)
  dx <- names[grepl("^I10_DX[0-9]+$", names)]
  pr <- names[grepl("^I10_PR[0-9]+$", names)]
  if (!identical(dx, paste0("I10_DX", seq_along(dx))) ||
      !identical(pr, paste0("I10_PR", seq_along(pr))) ||
      any(types[names %in% c(dx, pr)] != "Char")) {
    stop("Non-contiguous or non-character coding slots for ", year)
  }
  count_line <- lines[grepl("^Number of Observations:", lines)]
  field_line <- lines[grepl("^Total Number of Data Elements:", lines)]
  count <- as.integer(sub("^Number of Observations: *", "", count_line))
  field_count <- as.integer(sub("^Total Number of Data Elements: *", "", field_line))
  if (length(count) != 1L || is.na(count) || length(field_count) != 1L ||
      is.na(field_count) || field_count != length(names)) stop("Invalid layout header.")
  data.frame(
    year = year, documented_revision = revision, core_records = count,
    core_columns = field_count, diagnosis_slots = length(dx),
    procedure_slots = length(pr), discharge_key = "KEY_NIS",
    hospital_key = "HOSP_NIS", stratum = "NIS_STRATUM", weight = "DISCWT",
    diagnosis_system = "ICD10CM", procedure_system = "ICD10PCS",
    source = url, retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    source_md5 = unname(tools::md5sum(path)), review_status = "provisional",
    stringsAsFactors = FALSE
  )
})
utils::write.csv(do.call(rbind, rows), output, row.names = FALSE)
cat("Updated provisional layout facts for", length(rows), "years.\n")
