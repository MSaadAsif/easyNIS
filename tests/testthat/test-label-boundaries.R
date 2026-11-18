is.na.synthetic_labelled_spss <- function(x) {
  values <- unclass(x)
  is.na(values) | values %in% attr(x, "na_values", exact = TRUE)
}

test_that("empty unknown codes retain their identity on repeated labelling", {
  data <- data.frame(DIED = c("0", "", "1", "", NA_character_))

  expect_warning(labelled <- nis_label(data), "Unknown code.*DIED")
  expect_identical(as.character(labelled$DIED), c("No", "Code ", "Yes", "Code ", NA_character_))
  expect_identical(levels(labelled$DIED), c("No", "Yes", "Code "))
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric missing values remain missing without unknown-code warnings", {
  data <- data.frame(DIED = c(0, NaN, NA_real_, 1))

  expect_no_warning(labelled <- nis_label(data))
  expect_identical(as.character(labelled$DIED), c("No", NA_character_, NA_character_, "Yes"))
  expect_identical(is.na(labelled$DIED), c(FALSE, TRUE, TRUE, FALSE))
  expect_identical(levels(labelled$DIED), c("No", "Yes"))
  expect_identical(nis_label(labelled), labelled)

  expect_no_warning(missing <- nis_label(data.frame(DIED = c(NaN, NA_real_))))
  expect_identical(as.character(missing$DIED), c(NA_character_, NA_character_))
  expect_identical(levels(missing$DIED), c("No", "Yes"))
})

test_that("observed unknown codes remain distinct from missing values", {
  data <- data.frame(DIED = c("0", "NaN", "NA", "", " ", "01", "1.0", "-9", "\n", NA_character_))

  expect_warning(labelled <- nis_label(data), "Unknown code.*DIED")
  expect_identical(as.character(labelled$DIED), c(
    "No", "Code NaN", "Code NA", "Code ", "Code  ", "Code 01", "Code 1.0", "Code -9", "Code \n", NA_character_
  ))
  expect_identical(levels(labelled$DIED), c(
    "No", "Yes", "Code NaN", "Code NA", "Code ", "Code  ", "Code 01", "Code 1.0", "Code -9", "Code \n"
  ))
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric unknown codes still warn while NaN remains missing", {
  data <- data.frame(DIED = c(0, NaN, -9, Inf, NA_real_, -9))
  warnings <- character()
  labelled <- withCallingHandlers(nis_label(data), warning = function(warning) {
    warnings <<- c(warnings, conditionMessage(warning))
    invokeRestart("muffleWarning")
  })

  expect_length(warnings, 1L)
  expect_match(warnings, "Unknown code.*DIED")
  expect_match(warnings, "-9, Inf", fixed = TRUE)
  expect_false(grepl("NaN", warnings, fixed = TRUE))
  expect_identical(as.character(labelled$DIED), c(
    "No", NA_character_, "Code -9", "Code Inf", NA_character_, "Code -9"
  ))
  expect_identical(levels(labelled$DIED), c("No", "Yes", "Code -9", "Code Inf"))
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric NaN handling preserves SPSS sentinel values", {
  data <- data.frame(DIED = structure(c(0, -9, 1),
    na_values = -9,
    class = c("synthetic_labelled_spss", "numeric")))

  expect_identical(is.na(data$DIED), c(FALSE, TRUE, FALSE))
  expect_warning(labelled <- nis_label(data), "Unknown code.*DIED")
  expect_identical(as.character(labelled$DIED), c("No", "Code -9", "Yes"))
  expect_identical(levels(labelled$DIED), c("No", "Yes", "Code -9"))
})

test_that("raw factor levels resembling generated codes are still labelled", {
  data <- data.frame(DIED = factor("Code ", levels = c("0", "1", "Code ")))

  expect_warning(labelled <- nis_label(data), "Unknown code.*DIED")
  expect_identical(as.character(labelled$DIED), "Code Code ")
  expect_identical(levels(labelled$DIED), c("No", "Yes", "Code Code "))
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("raw factors decode displayed codes including empty unknown codes", {
  for (ordered in c(FALSE, TRUE)) {
    data <- data.frame(DIED = factor(c("0", "", "1", NA_character_),
      levels = c("unused", "1", "", "0"), ordered = ordered))

    expect_warning(labelled <- nis_label(data), "Unknown code.*DIED")
    expect_identical(as.character(labelled$DIED), c("No", "Code ", "Yes", NA_character_))
    expect_identical(levels(labelled$DIED), c("No", "Yes", "Code "))
    expect_false(is.ordered(labelled$DIED))
    expect_no_warning(repeated <- nis_label(labelled))
    expect_identical(repeated, labelled)
  }
})

test_that("existing labelled factors retain levels order and attributes", {
  for (ordered in c(FALSE, TRUE)) {
    died <- factor(c("No", "Code ", "Code 7", NA_character_),
      levels = c("Code 7", "Yes", "Code ", "No", "unused"), ordered = ordered)
    attr(died, "label") <- "Existing outcome label"
    attr(died, "source") <- "Invented fixture"
    names(died) <- c("a", "b", "c", "d")
    data <- data.frame(DIED = died)

    expect_no_warning(labelled <- nis_label(data))
    expect_identical(labelled, data)
    expect_identical(nis_label(labelled), labelled)
  }
})

test_that("labelling preserves input row column and unrelated metadata", {
  data <- data.frame(id = c("third", "first", "second"), DIED = c(0, NaN, 1),
    AGE = c(30, 40, 50), row.names = c("row-c", "row-a", "row-b"))
  attr(data, "source") <- "Invented fixture"
  attr(data$id, "label") <- "Row identity"
  attr(data$AGE, "units") <- "years"
  attr(data$DIED, "label") <- "Existing outcome label"

  expect_no_warning(labelled <- nis_label(data))
  expect_identical(attributes(labelled), attributes(data))
  expect_identical(labelled$id, data$id)
  expect_identical(attr(labelled$AGE, "units"), "years")
  expect_identical(as.numeric(labelled$AGE), c(30, 40, 50))
  expect_identical(attr(labelled$DIED, "label"), "Existing outcome label")
  expect_identical(as.character(labelled$DIED), c("No", NA_character_, "Yes"))
  expect_identical(nis_label(labelled), labelled)
})
