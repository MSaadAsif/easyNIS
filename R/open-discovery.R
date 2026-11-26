nis_open_discover <- function(path, years, call) {
  entries <- nis_open_entries(path, call)
  if (!nrow(entries)) {
    cli::cli_abort("No `NIS_<year>.parquet` entries were found in `path`.", call = call)
  }
  explicit <- !is.null(years)
  years <- nis_open_select_years(entries$year, years, call)
  nis_open_validate_layout(entries, years, call)
  parts <- nis_open_parts(entries, years)
  empty <- setdiff(years, parts$year)
  if (!nrow(parts) || (explicit && length(empty))) {
    cli::cli_abort("The selected NIS entries contain no Parquet part files for year{?s} {.val {empty}}.", call = call)
  }
  distinct <- !duplicated(parts[c("path", "partition_year")])
  list(years = intersect(years, parts$year), parts = parts[distinct, ])
}

nis_open_available_years <- function(path) {
  entries <- nis_open_entries(path, rlang::current_call())
  sort(unique(nis_open_parts(entries, entries$year)$year))
}

nis_open_entries <- function(path, call) {
  if (!dir.exists(path)) {
    cli::cli_abort("`path` must name an existing directory.", call = call)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  annual <- list.files(path, pattern = "^NIS_[0-9]{4}[.]parquet$", full.names = TRUE)
  hive <- list.dirs(path, recursive = TRUE, full.names = TRUE)
  hive <- hive[grepl("^YEAR=[0-9]{4}$", basename(hive))]
  entries <- c(annual, hive)
  data.frame(
    path = entries,
    year = as.integer(sub("^(NIS_|YEAR=)([0-9]{4})([.]parquet)?$", "\\2", basename(entries))),
    annual = seq_along(entries) <= length(annual),
    directory = c(dir.exists(annual), rep(TRUE, length(hive)))
  )
}

nis_open_select_years <- function(found, years, call) {
  if (is.null(years)) {
    years <- sort(found)
  }
  if (!nis_open_whole_years(years)) {
    cli::cli_abort("`years` must be a non-empty vector of whole years.", call = call)
  }
  years <- unique(as.integer(years))
  if (any(years < 2012L)) {
    cli::cli_abort("NIS years before 2012 are not supported.", call = call)
  }
  missing <- setdiff(years, found)
  if (length(missing)) {
    cli::cli_abort("No NIS Parquet entry was found for year{?s} {.val {missing}}.", call = call)
  }
  years
}

nis_open_whole_years <- function(years) {
  is.numeric(years) &&
    length(years) > 0L &&
    all(is.finite(years)) &&
    all(abs(years) <= .Machine$integer.max & years == floor(years))
}

nis_open_validate_layout <- function(entries, years, call) {
  mixed <- intersect(years, intersect(entries$year[entries$annual], entries$year[!entries$annual]))
  if (!length(mixed)) {
    return(invisible(NULL))
  }

  details <- lapply(mixed, function(year) {
    same_year <- entries[entries$year == year, , drop = FALSE]
    paths <- normalizePath(same_year$path, winslash = "/", mustWork = TRUE)
    roots <- same_year[nis_open_uncovered_entries(paths), , drop = FALSE]
    if (all(roots$annual) || !any(roots$annual)) {
      return(NULL)
    }
    paste0(
      "Year ",
      year,
      ": annual ",
      paste(roots$path[roots$annual], collapse = ", "),
      " and Hive ",
      paste(roots$path[!roots$annual], collapse = ", ")
    )
  })
  details <- unlist(details, use.names = FALSE)
  if (!length(details)) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    paste0(
      "A year is present in both annual and Hive layouts.\n",
      paste0("x Year is duplicated: ", details, collapse = "\n"),
      "\ni Keep one layout per year."
    ),
    call = call
  )
}

nis_open_uncovered_entries <- function(paths, through_hidden = TRUE) {
  covered <- rep(FALSE, length(paths))
  child <- paths
  pending <- seq_along(paths)
  while (length(pending)) {
    if (!through_hidden) {
      pending <- pending[!startsWith(basename(child[pending]), ".")]
    }
    parent <- dirname(child[pending])
    higher <- parent != child[pending]
    pending <- pending[higher]
    parent <- parent[higher]
    covered[pending] <- parent %in% paths
    child[pending] <- parent
    pending <- pending[!covered[pending]]
  }
  !covered
}

nis_open_parts <- function(entries, years) {
  selected <- entries[entries$year %in% years, , drop = FALSE]
  # list.files() skips hidden directories unless used as traversal roots.
  roots <- selected[nis_open_uncovered_entries(selected$path, through_hidden = FALSE), , drop = FALSE]
  files <- Map(
    function(path, directory) {
      if (directory) {
        return(list.files(path, pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE))
      }
      path
    },
    roots$path,
    roots$directory
  )
  paths <- as.character(unlist(files, use.names = FALSE))
  years_by_part <- rep(roots$year, lengths(files))
  partition_year <- nis_open_partition_year(paths, entries$path[!entries$annual])
  hive <- !is.na(partition_year)
  years_by_part[hive] <- partition_year[hive]
  keep <- years_by_part %in% years
  data.frame(
    path = normalizePath(paths[keep], winslash = "/", mustWork = TRUE),
    partition_year = partition_year[keep],
    year = years_by_part[keep]
  )
}

nis_open_partition_year <- function(paths, hive_dirs) {
  # Ownership is lexical. A symlink's target does not change its partition.
  year <- rep(NA_integer_, length(paths))
  if (!length(paths) || !length(hive_dirs)) {
    return(year)
  }
  # Greedy matching finds the deepest partition component. Paths above the
  # supplied directory are absent from the discovered Hive directories.
  pattern <- "(?s)^(.*/YEAR=([0-9]{4}))(?:/.*)?$"
  dirs <- dirname(paths)
  owner <- sub(pattern, "\\1", dirs, perl = TRUE)
  found <- owner %in% hive_dirs
  year[found] <- as.integer(sub(pattern, "\\2", owner[found], perl = TRUE))
  year
}
