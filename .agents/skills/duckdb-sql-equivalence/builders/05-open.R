# A projection can change column order, lose case restoration, misquote an
# identifier, or attach the wrong values or promoted types to a retained name.
open_cases <- function(con) {
  rows <- fixture(YEAR = 2019:2020, measure = c(NA_integer_, 0L, 3L), flag = c(NA, FALSE, TRUE))
  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  spellings <- grid(first = c("measure", "Measure"), second = c("measure", "MEASURE"))
  unlist(
    lapply(readers, function(reader) {
      lapply(seq_len(nrow(spellings)), function(i) {
        case(
          rows,
          list(
            reader = reader,
            spellings = unname(unlist(spellings[i, ])),
            promote = i != 1L
          )
        )
      })
    }),
    recursive = FALSE
  )
}

open_projection_sql <- function(con, rows, args) {
  path <- tempfile("open-projection-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  for (year in sort(unique(rows$YEAR))) {
    annual <- rows[rows$YEAR == year, ]
    if (year == 2020L && args$promote) {
      annual$measure <- annual$measure / 2
    }
    names(annual)[2:3] <- c(args$spellings[[year - 2018L]], 'tag "note"')
    duck_table(con, annual)
    part <- DBI::dbQuoteString(con, file.path(path, sprintf("NIS_%d.parquet", year)))
    DBI::dbExecute(con, paste("COPY fixture TO", part, "(FORMAT PARQUET)"))
  }
  input <- easyNIS::nis_open(path, reader = args$reader, check_release = FALSE)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(input), shutdown = TRUE), add = TRUE, after = FALSE)
  actual <- as.data.frame(dplyr::collect(input))
  actual[order(actual$id), ]
}

open_projection_reference <- function(rows, args) {
  if (args$promote) {
    rows$measure <- as.double(rows$measure)
    latest <- rows$YEAR == 2020L
    rows$measure[latest] <- rows$measure[latest] / 2
  }
  # The first file supplies the pooled spelling and sort position. A later
  # uppercase spelling can restore the output name without moving it.
  sort_name <- if (args$spellings[[1L]] == "Measure") "MEASURE" else "measure"
  columns <- order(c("YEAR", sort_name, 'tag "note"', "id"))
  output <- if (all(args$spellings == "measure")) "measure" else "MEASURE"
  names(rows)[2:3] <- c(output, 'tag "note"')
  rows[order(rows$id), columns]
}

register(
  "open-projection",
  open_cases,
  open_projection_sql,
  open_projection_reference,
  mutation(
    "open.R",
    "nis_open_projection_sql",
    "dbQuoteIdentifier(con, fields)",
    "dbQuoteIdentifier(con, rev(fields))"
  ),
  relations = list(years = split_years, rows = shuffle_rows)
)
