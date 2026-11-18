test_that("disclosure check finds tokens and small CSV counts", {
  dir <- tempfile(); dir.create(dir)
  write.csv(data.frame(n = c(0, 3, 11), note = c("ok", "KEY_NIS", "ok")),
    file.path(dir, "table.csv"), row.names = FALSE)
  out <- nis_disclosure_check(dir, error = FALSE)
  expect_equal(sum(out$kind == "small_count"), 1)
  expect_true(any(out$value == "KEY_NIS"))
})

test_that("disclosure check scans rendered and prose files", {
  dir <- tempfile(); dir.create(dir)
  writeLines("<p>safe HOSP_NIS</p>", file.path(dir, "report.html"))
  writeLines("safe", file.path(dir, "notes.qmd"))
  out <- nis_disclosure_check(dir, error = FALSE)
  expect_equal(nrow(out), 1)
  expect_equal(out$kind, "restricted_token")
  expect_error(nis_disclosure_check(dir), "Disclosure violations")
})

test_that("disclosure check scans CSV headers and DOCX text", {
  dir <- tempfile(); dir.create(dir)
  write.csv(data.frame(HOSP_NIS = 1, n_count = 2),
    file.path(dir, "table.csv"), row.names = FALSE)
  file.copy(test_path("fixtures", "disclosure.docx"), file.path(dir, "report.docx"))
  out <- nis_disclosure_check(dir, error = FALSE)
  expect_true(any(out$file == file.path(dir, "table.csv") & out$value == "HOSP_NIS"))
  expect_true(any(out$file == file.path(dir, "report.docx") & out$value == "KEY_NIS"))
})
