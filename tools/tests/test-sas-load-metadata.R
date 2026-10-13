source(file.path("..", "layout-metadata.R"), local = TRUE)
source(file.path("..", "sas-load-metadata.R"), local = TRUE)

invented_sas <- function(layout) {
  formats <- ifelse(layout$fields$type == "Char",
    paste0("$CHAR", layout$fields$end - layout$fields$start + 1L, "."),
    ifelse(layout$fields$name == "DISCWT", "N11P7F.",
      paste0("N", layout$fields$end - layout$fields$start + 1L, "PF.")))
  formats[formats == "N1PF."] <- "1."
  numeric <- setdiff(unique(formats[layout$fields$type == "Num"]), "1.")
  definitions <- unlist(lapply(numeric, function(format) {
    width <- if (format == "N11P7F.") 11L else as.integer(sub("N([0-9]+)PF\\.", "\\1", format))
    token <- if (format == "N11P7F.") "-99.9999999" else paste0("-", strrep("9", width - 1L))
    c(paste("INVALUE", sub("\\.$", "", format)), paste0("'", token, "' = ."),
      paste0("OTHER = (|", width, ".", if (format == "N11P7F.") "7" else "", "|)"), ";")
  }))
  c("/* Entirely invented load-program fixture. */", "PROC FORMAT;", definitions, "RUN;",
    paste0("DATA ", layout$dataset, ";"),
    paste0("INFILE '", layout$dataset, ".ASC' LRECL = ", layout$record_length, ";"),
    "INPUT", paste0("@", layout$fields$start, " ", layout$fields$name, " ", formats), ";", "RUN;")
}

test_that("SAS audit matches invented fields and retains literal missing tokens", {
  layout <- parse_core_layout(invented_layout(), 2022L)
  lines <- invented_sas(layout)
  parsed <- parse_sas_load(lines, layout)
  expect_identical(parsed$fields$name, layout$fields$name)
  expect_identical(parsed$fields$type, layout$fields$type)
  expect_equal(parsed$fields$width, layout$fields$end - layout$fields$start + 1L)
  expect_equal(parsed$fields$decimals, layout$fields$decimals)
  expect_identical(parsed$mappings$raw_token[parsed$mappings$informat == "N11P7F."], "-99.9999999")
  expect_true(all(parsed$mappings$sas_missing_token == "."))
  added <- sub("'-999' = .", "'-999' = .\n'-888' = .A\n'-666' = .C", lines, fixed = TRUE)
  expect_identical(parse_sas_load(added, layout)$mappings$sas_missing_token[1:3], c(".", ".A", ".C"))
})

test_that("malformed or mismatched SAS input cannot supply audit facts", {
  layout <- parse_core_layout(invented_layout(), 2022L)
  lines <- invented_sas(layout)
  expect_error(parse_sas_load(sub("DATA NIS_2022_CORE", "DATA NIS_2021_CORE", lines), layout), "dataset")
  expect_error(parse_sas_load(sub("LRECL = 48", "LRECL = 49", lines), layout), "record length")
  expect_error(parse_sas_load(c(lines, "INPUT @1 YEAR N4PF.;"), layout), "repeated INPUT")
  expect_error(parse_sas_load(sub("@5 KEY_NIS", "@6 KEY_NIS", lines), layout), "positions")
  expect_error(parse_sas_load(sub("@5 KEY_NIS", "@5 OTHER", lines), layout), "fields")
  expect_error(parse_sas_load(sub("@1 YEAR N4PF.", "@1 YEAR UNKNOWN.", lines, fixed = TRUE), layout), "undefined")
  expect_error(parse_sas_load(sub("@1 YEAR N4PF.", "@1 YEAR $CHAR4.", lines, fixed = TRUE), layout), "type mismatch")
  expect_error(parse_sas_load(sub("OTHER = (|4.|)", "OTHER = (|5.|)", lines, fixed = TRUE), layout), "width")
  expect_error(parse_sas_load(sub("OTHER = (|11.7|)", "OTHER = (|11.6|)", lines, fixed = TRUE), layout), "precision")
  expect_error(parse_sas_load(sub("'-999' = .", "'-999' = .\n'-999' = .A", lines, fixed = TRUE), layout), "duplicate raw")
  expect_error(parse_sas_load(sub("'-999' = .", "'-999' = .Q EXTRA", lines, fixed = TRUE), layout), "syntax")
  expect_error(parse_sas_load(c(lines, "INVALUE N4PF\n'-999' = .\nOTHER = (|4.|);"), layout), "duplicate INVALUE")
  expect_error(parse_sas_load(c(lines, "INVALUE n4pf\n'-999' = .Q\nOTHER = (|4.|);"), layout), "syntax")
  expect_error(parse_sas_load(c(lines, "invalue N4PF\n'-999' = .Q\nOTHER = (|4.|);"), layout), "syntax")
  expect_error(parse_sas_load(c(lines, "input @1 YEAR N4PF.;"), layout), "repeated INPUT")
  expect_error(parse_sas_load(c(lines, "data NIS_2022_CORE;"), layout), "repeated DATA")
  expect_error(parse_sas_load(c(lines, "infile 'NIS_2022_CORE.ASC' LRECL = 48;"), layout), "repeated INFILE")
  expect_error(parse_sas_load(sub("@1 YEAR N4PF.", "@1 YEAR N4PF. EXTRA", lines, fixed = TRUE), layout), "syntax")
  expect_error(parse_sas_load(c(lines, "/* unfinished"), layout), "unclosed")
  expect_error(parse_sas_load(sub("'-999'", "'-9/*literal*/99'", lines, fixed = TRUE), layout), "syntax")
  expect_error(parse_sas_load(sub("'-999'", "'-9;99'", lines, fixed = TRUE), layout), "syntax")
  expect_error(parse_sas_load(c(lines, "ATTRIB TEST LABEL='unfinished;"), layout), "unclosed quoted")
  expect_error(parse_sas_load(c(lines, "* unfinished"), layout), "unclosed statement comment")
  # Comments may contain quotes/semicolons, while quoted label text stays literal.
  decorated <- c("/* an author's ; comment */", lines,
    "* another author's comment;", "ATTRIB TEST LABEL='a; /* literal */ it''s text';")
  expect_identical(parse_sas_load(decorated, layout), parse_sas_load(lines, layout))
})

test_that("a complete invented audit publishes together and preserves existing output", {
  root <- tempfile("sas audit ")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cache <- file.path(root, "cache")
  dir.create(cache)
  for (year in 2017:2022) for (component in c("Core", "Hospital", "Severity", "DX_PR_GRPS")) {
    if (year == 2017L && component == "DX_PR_GRPS") next
    suffix <- if (year %in% 2019:2020) "_V2" else ""
    stem <- paste0("NIS_", year, "_", component, suffix)
    lines <- invented_layout(year, component = component)
    layout <- parse_nis_layout(lines, year, component)
    writeLines(lines, file.path(cache, paste0("FileSpecifications_", stem, ".TXT")))
    writeLines(invented_sas(layout), file.path(cache, paste0("SASLoad_", stem, ".SAS")))
  }
  output <- file.path(root, "audit")
  tables <- audit_sas_loads(cache, output)
  expect_equal(nrow(tables$references), 23L)
  expect_true(all(tables$references$review_status == "provisional"))
  expect_setequal(list.files(output), c("fields.csv", "mappings.csv", "references.csv"))
  saved <- tools::md5sum(list.files(output, full.names = TRUE))
  expect_error(audit_sas_loads(cache, output), "new audit output")
  expect_identical(tools::md5sum(list.files(output, full.names = TRUE)), saved)
  previous <- setwd(normalizePath(file.path("..", "..")))
  on.exit(setwd(previous), add = TRUE)
  cli_output <- file.path(root, "cli audit")
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c("tools/audit-sas-loads.R", shQuote(cache), shQuote(cli_output)),
    stdout = TRUE, stderr = TRUE)
  expect_null(attr(status, "status"))
  expect_true(any(grepl("Audited 23 cached pairs", status, fixed = TRUE)))
  for (file in list.files(output)) {
    expect_identical(readLines(file.path(cli_output, file)), readLines(file.path(output, file)))
  }
  # Damage the last pair: no partial output may be published.
  path <- file.path(cache, "SASLoad_NIS_2022_DX_PR_GRPS.SAS")
  writeLines(sub("@1 HOSP_NIS", "@2 HOSP_NIS", readLines(path)), path)
  expect_error(audit_sas_loads(cache, file.path(root, "bad")), "positions")
  expect_false(dir.exists(file.path(root, "bad")))
  unlink(path)
  expect_error(audit_sas_loads(cache, file.path(root, "missing")), "Missing cached")
  expect_false(dir.exists(file.path(root, "missing")))
})
