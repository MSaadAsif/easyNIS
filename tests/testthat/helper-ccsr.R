# Invented CCSR-shaped fixtures: made-up codes and categories only.
ccsr_fixture_rows <- function() {
  data.frame(
    code = c("X100", "X101", "X101", "X102", "X200", "X200", "Y300", "Y30A"),
    category = c("ZZZ001", "ZZZ001", "ZZZ002", "ZZZ002", "ZZZ002", "ZZZ003",
      "ZZZ003", "ZZZ003"),
    default = c("Y", "N", "Y", "Y", "N", "Y", "X", "Y"),
    stringsAsFactors = FALSE
  )
}

# Minimal workbook with a title row above the header, like HCUP workbooks.
write_ccsr_xlsx <- function(path, rows = ccsr_fixture_rows(),
                            sheet = "DX_to_CCSR_Mapping",
                            header = c("ICD-10-CM Code", "ICD-10-CM Code Description",
                              "CCSR Category", "CCSR Category Description",
                              "Inpatient Default CCSR (Y/N/X)")) {
  skip_if_not_installed("zip") # nolint
  cell <- function(ref, text) {
    sprintf('<c r="%s" t="inlineStr"><is><t>%s</t></is></c>', ref, text)
  }
  table <- rbind(header, cbind(rows$code, "Invented description", rows$category,
    "Invented category", rows$default))
  table <- rbind(c("Invented mapping list", rep("", 4L)), table)
  sheet_rows <- vapply(seq_len(nrow(table)), function(i) {
    cells <- vapply(seq_len(ncol(table)), function(j) {
      cell(paste0(LETTERS[j], i), table[i, j])
    }, "")
    sprintf('<row r="%d">%s</row>', i, paste(cells, collapse = ""))
  }, "")
  dir <- tempfile("xlsx-")
  dir.create(file.path(dir, "_rels"), recursive = TRUE)
  dir.create(file.path(dir, "xl", "_rels"), recursive = TRUE)
  dir.create(file.path(dir, "xl", "worksheets"), recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  ns <- "http://schemas.openxmlformats.org"
  writeLines(sprintf(paste0('<?xml version="1.0"?><Types xmlns="%s/package/2006/content-types">',
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    '<Default Extension="xml" ContentType="application/xml"/>',
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    "</Types>"), ns), file.path(dir, "[Content_Types].xml"))
  writeLines(sprintf(paste0('<?xml version="1.0"?><Relationships xmlns="%s/package/2006/relationships">',
    '<Relationship Id="rId1" Type="%s/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>',
    "</Relationships>"), ns, ns), file.path(dir, "_rels", ".rels"))
  writeLines(sprintf(paste0('<?xml version="1.0"?><workbook xmlns="%s/spreadsheetml/2006/main" ',
    'xmlns:r="%s/officeDocument/2006/relationships"><sheets>',
    '<sheet name="%s" sheetId="1" r:id="rId1"/></sheets></workbook>'), ns, ns, sheet),
    file.path(dir, "xl", "workbook.xml"))
  writeLines(sprintf(paste0('<?xml version="1.0"?><Relationships xmlns="%s/package/2006/relationships">',
    '<Relationship Id="rId1" Type="%s/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>',
    "</Relationships>"), ns, ns), file.path(dir, "xl", "_rels", "workbook.xml.rels"))
  writeLines(sprintf('<?xml version="1.0"?><worksheet xmlns="%s/spreadsheetml/2006/main"><sheetData>%s</sheetData></worksheet>',
    ns, paste(sheet_rows, collapse = "")), file.path(dir, "xl", "worksheets", "sheet1.xml"))
  zip::zip(normalizePath(path, mustWork = FALSE),
    c("[Content_Types].xml", "_rels", "xl"), root = dir, mode = "mirror")
  invisible(path)
}

# Wide layout with quoted values, as in the HCUP comma-separated download.
write_ccsr_wide_csv <- function(path) {
  writeLines(c(
    "'ICD-10-CM CODE','ICD-10-CM CODE DESCRIPTION','Default CCSR CATEGORY IP','Default CCSR CATEGORY DESCRIPTION IP','CCSR CATEGORY 1','CCSR CATEGORY 1 DESCRIPTION','CCSR CATEGORY 2','CCSR CATEGORY 2 DESCRIPTION'",
    "'X100','d','ZZZ001','c','ZZZ001','c',' ',' '",
    "'X101','d','ZZZ002','c','ZZZ001','c','ZZZ002','c'",
    "'X102','d','ZZZ002','c','ZZZ002','c',' ',' '",
    "'X200','d','ZZZ003','c','ZZZ002','c','ZZZ003','c'"
  ), path)
  invisible(path)
}
