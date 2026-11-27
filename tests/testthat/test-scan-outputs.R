test_that("publication scan checks nested tables and plain prose", {
  folder <- withr::local_tempdir()
  dir.create(file.path(folder, ".appendix"))
  writeLines(
    c('"group","unweighted n","n","HOSP_NIS"', '"a,b","1","10 (20%)","98765432"'),
    file.path(folder, ".appendix", "cells.CSV")
  )
  writeLines(c("KEY\tCount", "12345678\t5"), file.path(folder, "legacy.tsv"))
  writeLines(
    c("Number of discharges: 4. The NRD_VisitLink was used.", "See the key findings."),
    file.path(folder, "notes.txt")
  )

  findings <- nis_scan_outputs(folder)

  expect_named(findings, c("file", "location", "issue", "field"))
  expect_setequal(findings$field[findings$issue == "restricted_identifier"], c("HOSP_NIS", "KEY", "NRD_VISITLINK"))
  expect_equal(sum(findings$issue == "small_count"), 4L)
  expect_true(".appendix/cells.CSV" %in% findings$file)
  expect_false(any(grepl("98765432|12345678", unlist(findings))))
  expect_error(nis_scan_outputs(folder, error = TRUE), class = "easyNIS_output_scan")
})

test_that("publication scan distinguishes masks and estimates from counts", {
  folder <- withr::local_tempdir()
  writeLines(
    c("n,hospitals,mean", "0,2,5", "11,4,10", "<=10,3,7", "Masked,2,1", "10%,3,1", "8.5,2,1", "NA,2,1"),
    file.path(folder, "safe.csv")
  )
  writeLines(
    c("n = <=10. This mask covers up to 10 discharges.", "Key findings include 11 cases."),
    file.path(folder, "safe.txt")
  )
  writeLines("KEY_NIS", file.path(folder, "manual-review.pdf"))

  expect_equal(nrow(nis_scan_outputs(folder, error = TRUE)), 0L)
  expect_error(nis_scan_outputs(file.path(folder, "safe.csv")), "directory")
})

test_that("publication scan checks rendered and Markdown tables and denominators", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("commonmark")
  folder <- withr::local_tempdir()
  writeLines(
    c(
      "<table><thead><tr><th rowspan='2'>Group</th><th colspan='2'>Results</th></tr>",
      "<tr><th>Estimate</th><th>n (%)</th></tr></thead>",
      "<tbody><tr><td>Overall</td><td>2</td><td><strong>10</strong> (12%)</td></tr></tbody></table>",
      "<p><b>N</b> = 1. <b>KEY</b>&#95;NIS.</p><!-- DSHOSPID -->"
    ),
    file.path(folder, "report.html")
  )
  writeLines(
    c("The file uses `hosp_kid`.", "", "| Group | Count |", "| --- | --- |", "| a | **5** |", "| b | &le;10 |"),
    file.path(folder, "report.md")
  )

  findings <- nis_scan_outputs(folder)
  expect_setequal(findings$field[findings$issue == "restricted_identifier"], c("KEY_NIS", "DSHOSPID", "HOSP_KID"))
  expect_equal(as.integer(table(findings$file[findings$issue == "small_count"])), c(2L, 1L))
  expect_true(any(findings$file == "report.html" & findings$location == "table 1 column 3"))
})

test_that("publication scan checks Word text parts and table cells", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("zip")
  folder <- withr::local_tempdir()
  source <- withr::local_tempdir()
  dir.create(file.path(source, "word"))
  writeLines(
    paste0(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>',
      "<w:p><w:r><w:t>KEY_</w:t></w:r><w:r><w:t>NIS</w:t></w:r></w:p>",
      "<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Group</w:t></w:r></w:p></w:tc>",
      "<w:tc><w:p><w:r><w:t>Count</w:t></w:r></w:p></w:tc></w:tr>",
      "<w:tr><w:tc><w:p><w:r><w:t>All</w:t></w:r></w:p></w:tc>",
      "<w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc></w:tr></w:tbl>",
      "</w:body></w:document>"
    ),
    file.path(source, "word", "document.xml")
  )
  writeLines(
    '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:r><w:t>HOSPID</w:t></w:r></w:p></w:hdr>',
    file.path(source, "word", "header1.xml")
  )
  zip::zipr(file.path(folder, "report.docx"), "word", root = source)

  findings <- nis_scan_outputs(folder)
  expect_setequal(findings$field[findings$issue == "restricted_identifier"], c("KEY_NIS", "HOSPID"))
  expect_equal(sum(findings$issue == "small_count"), 1L)
  expect_match(findings$location[findings$field %in% "HOSPID"], "header1.xml", fixed = TRUE)
})

test_that("publication scan checks hidden worksheets and flags unreadable files", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("zip")
  folder <- withr::local_tempdir()
  source <- withr::local_tempdir()
  dir.create(file.path(source, "xl", "worksheets"), recursive = TRUE)
  dir.create(file.path(source, "xl", "_rels"))
  dir.create(file.path(source, "_rels"))
  main_ns <- "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  rel_ns <- "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  writeLines(
    paste0(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      '<Relationship Id="rId1" Type="',
      rel_ns,
      '/officeDocument" Target="xl/workbook.xml"/>',
      "</Relationships>"
    ),
    file.path(source, "_rels", ".rels")
  )
  writeLines(
    paste0(
      '<workbook xmlns="',
      main_ns,
      '" xmlns:r="',
      rel_ns,
      '"><sheets>',
      '<sheet name="Summary" sheetId="1" r:id="rId1"/>',
      '<sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/>',
      "</sheets></workbook>"
    ),
    file.path(source, "xl", "workbook.xml")
  )
  writeLines(
    paste0(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      '<Relationship Id="rId1" Type="',
      rel_ns,
      '/worksheet" Target="worksheets/sheet1.xml"/>',
      '<Relationship Id="rId2" Type="',
      rel_ns,
      '/worksheet" Target="worksheets/sheet2.xml"/>',
      "</Relationships>"
    ),
    file.path(source, "xl", "_rels", "workbook.xml.rels")
  )
  for (i in 1:2) {
    writeLines(
      paste0(
        '<worksheet xmlns="',
        main_ns,
        '"><sheetData>',
        '<row r="1"><c r="A1" t="inlineStr"><is><t>n</t></is></c>',
        '<c r="B1" t="inlineStr"><is><t>',
        c("Group", "AHAID")[[i]],
        "</t></is></c></row>",
        '<row r="2"><c r="A2"><v>',
        c(11, 10)[[i]],
        "</v></c></row>",
        "</sheetData></worksheet>"
      ),
      file.path(source, "xl", "worksheets", paste0("sheet", i, ".xml"))
    )
  }
  zip::zipr(file.path(folder, "tables.xlsx"), c("xl", "_rels"), root = source)
  writeLines("not a workbook", file.path(folder, "broken.xlsx"))
  g <- file.path(folder, "broken.docx")
  expect_true(file.create(g))

  findings <- nis_scan_outputs(folder)
  workbook <- findings[findings$file == "tables.xlsx", ]
  expect_setequal(workbook$issue, c("restricted_identifier", "small_count"))
  expect_true(all(grepl("sheet 2", workbook$location, fixed = TRUE)))
  expect_setequal(findings$file[findings$issue == "scan_error"], c("broken.xlsx", "broken.docx"))
  expect_error(nis_scan_outputs(folder, error = TRUE), class = "easyNIS_output_scan")
})
