source(file.path("tools", "probe", "helpers.R"))

test_paths <- c(
  "C:\\sandbox\\invented person\\nis.parquet",
  "D:/work/nis/input.parquet",
  "\\\\server\\share\\private data\\file.parquet",
  "/srv/invented nis/data.parquet"
)
redacted <- redact_paths(test_paths)
stopifnot(all(redacted == "[local path]"),
  redact_public_text("n=7 cases") == "n=[number] cases",
  redact_public_text("count=1e8, n=5L") == "count=[number], n=[number]")

local({
  receipt_path <- tempfile(fileext = ".json")
  on.exit(unlink(receipt_path))
  write_receipt <- function(studies) {
    jsonlite::write_json(list(studies = studies), receipt_path, auto_unbox = TRUE)
    study_verification_ready(receipt_path)
  }
  passed_studies <- lapply(c("synthetic-a", "synthetic-b", "synthetic-c"), function(id) {
    list(id = id, pass = TRUE, tolerance = 0.05)
  })
  stopifnot(write_receipt(passed_studies))
  stopifnot(!write_receipt(passed_studies[-1L]))
  failed_studies <- passed_studies
  failed_studies[[2L]]$pass <- FALSE
  stopifnot(!write_receipt(failed_studies))
  duplicate_studies <- passed_studies
  duplicate_studies[[3L]]$id <- duplicate_studies[[2L]]$id
  stopifnot(!write_receipt(duplicate_studies))
  vague_studies <- passed_studies
  vague_studies[[1L]]$tolerance <- "not specified"
  stopifnot(!write_receipt(vague_studies))
  stopifnot(!write_receipt("synthetic"),
    !write_receipt(list(1, 2, 3)))

  empty_issues <- parse_open_issue_query("[]")
  one_issue <- parse_open_issue_query('[{"number":42}]')
  failed_query <- parse_open_issue_query(character(), status = 1L)
  stopifnot(empty_issues$ok, identical(empty_issues$count, 0L),
    one_issue$ok, identical(one_issue$count, 1L), !failed_query$ok)

  clean_check <- check_result_counts(list(errors = character(), warnings = character(), notes = character()))
  noted_check <- check_result_counts(list(errors = character(), warnings = character(), notes = c("one", "two")))
  stopifnot(all(clean_check == 0L), identical(unname(noted_check), c(0L, 0L, 2L)))
})

cat("Probe-helper tests passed.\n")
