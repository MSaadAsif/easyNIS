main <- function(args) {
  if (length(args) != 2L || !dir.exists(args[1L])) {
    stop("Usage: Rscript tools/inventory-parquet.R <input-directory> <private-output-directory>")
  }
  for (package in c("DBI", "duckdb")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("This developer tool requires the optional package ", package, ".")
    }
  }
  root <- normalizePath(args[1L], winslash = "/", mustWork = TRUE)
  files <- sort(list.files(root, pattern = "[.]parquet$", recursive = TRUE,
                          full.names = TRUE, ignore.case = TRUE))
  if (!length(files)) stop("No parquet files found under the input directory.")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  inventories <- schemas <- vector("list", length(files))
  for (index in seq_along(files)) {
    path <- normalizePath(files[index], winslash = "/", mustWork = TRUE)
    relative_path <- substring(path, nchar(root) + 2L)
    quoted <- as.character(DBI::dbQuoteString(con, path))
    schema <- DBI::dbGetQuery(con, paste0(
      "DESCRIBE SELECT * FROM read_parquet(", quoted, ")"
    ))
    footer <- DBI::dbGetQuery(con, paste0(
      "SELECT num_rows, num_row_groups, created_by FROM parquet_file_metadata(", quoted, ")"
    ))
    if (nrow(footer) != 1L) stop("Expected one footer for ", relative_path)
    year_match <- regexec("NIS_([0-9]{4})[.]parquet", relative_path)
    year_parts <- regmatches(relative_path, year_match)[[1L]]
    year_hint <- if (length(year_parts) == 2L) as.integer(year_parts[2L]) else NA_integer_
    info <- file.info(path)
    inventories[[index]] <- data.frame(
      path = path, year_hint = year_hint, bytes = info$size,
      modified_utc = format(info$mtime, tz = "UTC", usetz = TRUE),
      rows_from_footer = as.character(footer$num_rows),
      row_groups = as.character(footer$num_row_groups), columns = nrow(schema),
      writer_metadata = as.character(footer$created_by),
      conversion_provenance = "unknown", release_revision = "unknown",
      labels_preserved = "unverified", missing_reasons_preserved = "unverified",
      prefiltered = "unknown", stringsAsFactors = FALSE
    )
    schemas[[index]] <- data.frame(
      path = path, year_hint = year_hint, position = seq_len(nrow(schema)),
      column_name = schema$column_name, column_type = schema$column_type,
      stringsAsFactors = FALSE
    )
  }
  inventory <- do.call(rbind, inventories)
  schema <- do.call(rbind, schemas)
  dir.create(args[2L], recursive = TRUE, showWarnings = FALSE)
  output <- normalizePath(args[2L], winslash = "/", mustWork = TRUE)
  utils::write.csv(inventory, file.path(output, "file-inventory.csv"), row.names = FALSE)
  utils::write.csv(schema, file.path(output, "schemas.csv"), row.names = FALSE)
  writeLines(c(
    "# Private parquet metadata inventory", "",
    paste("Input directory:", root),
    paste("Created at:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste("R version:", getRversion()),
    paste("DuckDB R package:", utils::packageVersion("duckdb")), "",
    "Only file footers and schemas were queried. No discharge values were read or exported.",
    "Year hints come from directory names, not inspected YEAR values.",
    "Footer counts are not independent source-count validation.",
    "writer_metadata is the unverified created_by footer string, not proof of the converter, source release or transformations.",
    "Conversion history, prefiltering, labels, missing reasons, and revisions remain unverified.",
    "Keep these receipts ignored and outside any distributed package."
  ), file.path(output, "README.md"))
  cat("Inventoried", length(files), "parquet files. Receipts saved privately.\n")
}

if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
