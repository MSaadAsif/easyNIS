invented_layout <- function(year = 2022L, revision = "unspecified", legacy = FALSE,
                            component = "Core") {
  dataset <- paste0("NIS_", year, "_", toupper(component), if (revision == "V2") "_V2" else "")
  ranges <- if (legacy) list(c(1,3), c(5,8), c(10,35), c(37,39), c(41,69),
                            c(71,73), c(75,77), c(79,79), c(81,84)) else
    list(c(1,3), c(5,8), c(10,35), c(37,40), c(42,70),
         c(72,75), c(77,80), c(82,82), c(84,87))
  descriptions <- c("Database name", "Discharge year of data", "File name",
    "Data element number", "Data element name",
    "Starting column of data element in ASCII file", "Ending column of data element in ASCII file",
    "Non-zero number of digits after decimal point for numeric data element",
    "Data element type (Num=numeric; Char=character)")
  guide <- vapply(seq_along(ranges), function(i) {
    paste0(sprintf("%2d-%3d    ", ranges[[i]][1L], ranges[[i]][2L]), descriptions[i])
  }, character(1))
  names <- switch(component,
    Core = c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "I10_DX1", "I10_PR1"),
    Hospital = c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT"),
    Severity = c("HOSP_NIS", "KEY_NIS", "TEST_SCORE"),
    DX_PR_GRPS = c("HOSP_NIS", "KEY_NIS", "TEST_VERSION", "TEST_GROUP"))
  widths <- unname(c(YEAR = 4L, KEY_NIS = 10L, HOSP_NIS = 5L, NIS_STRATUM = 4L,
    DISCWT = 11L, I10_DX1 = 7L, I10_PR1 = 7L, TEST_SCORE = 2L,
    TEST_VERSION = 6L, TEST_GROUP = 1L)[names])
  ends <- cumsum(widths)
  starts <- ends - widths + 1L
  rows <- vapply(seq_along(names), function(i) {
    values <- c("NIS", as.character(year), dataset, as.character(i), names[i],
                as.character(starts[i]), as.character(ends[i]), if (names[i] == "DISCWT") "7" else "",
                if (names[i] %in% c("I10_DX1", "I10_PR1", "TEST_VERSION")) "Char" else "Num")
    line <- strrep(" ", 100L)
    for (j in seq_along(values)) {
      substring(line, ranges[[j]][1L], ranges[[j]][2L]) <-
        sprintf(paste0("%-", diff(ranges[[j]]) + 1L, "s"), values[j])
    }
    line
  }, character(1))
  c(paste("Data Set Name:", dataset), "Number of Observations: 12",
    paste("Total Record Length:", sum(widths)), paste("Total Number of Data Elements:", length(names)), guide, rows)
}
