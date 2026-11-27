# jarl-ignore unused_function: S3 dispatch for the synthetic labelled column.
is.na.synthetic_labelled_spss <- function(x) {
  values <- unclass(x)
  is.na(values) | values %in% attr(x, "na_values", exact = TRUE)
}

test_that("empty unknown codes retain their identity on repeated labelling", {
  data <- data.frame(TRAN_IN = c("0", "", "1", "", NA_character_))

  expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
  expect_identical(
    as.character(labelled$TRAN_IN),
    c("No transfer", "Code ", "Transferred from acute-care hospital", "Code ", NA_character_)
  )
  expect_identical(
    levels(labelled$TRAN_IN),
    c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility", "Code ")
  )
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric missing values remain missing without unknown-code warnings", {
  data <- data.frame(TRAN_IN = c(0, NaN, NA_real_, 1))

  expect_no_warning(labelled <- nis_label(data))
  expect_identical(
    as.character(labelled$TRAN_IN),
    c("No transfer", NA_character_, NA_character_, "Transferred from acute-care hospital")
  )
  expect_identical(is.na(labelled$TRAN_IN), c(FALSE, TRUE, TRUE, FALSE))
  expect_identical(
    levels(labelled$TRAN_IN),
    c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility")
  )
  expect_identical(nis_label(labelled), labelled)

  expect_no_warning(missing <- nis_label(data.frame(TRAN_IN = c(NaN, NA_real_))))
  expect_identical(as.character(missing$TRAN_IN), c(NA_character_, NA_character_))
  expect_identical(
    levels(missing$TRAN_IN),
    c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility")
  )
})

test_that("classed numeric storage is not mistaken for a plain numeric NaN", {
  skip_if_not_installed("bit64")
  data <- data.frame(TRAN_IN = bit64::as.integer64(c(0, -9, NA, 1)))
  warnings <- character()
  labelled <- withCallingHandlers(nis_label(data), warning = function(warning) {
    warnings <<- c(warnings, conditionMessage(warning))
    invokeRestart("muffleWarning")
  })

  expect_length(warnings, 1L)
  expect_match(warnings, "Unknown code.*TRAN_IN")
  expect_false(grepl("-9", warnings, fixed = TRUE))
  expect_identical(
    as.character(labelled$TRAN_IN),
    c("No transfer", "Code -9", NA_character_, "Transferred from acute-care hospital")
  )
  expect_identical(is.na(labelled$TRAN_IN), c(FALSE, FALSE, TRUE, FALSE))
})

test_that("Haven labelled NaN and tagged missing values stay missing", {
  skip_if_not_installed("haven")
  values <- c(0, NaN, haven::tagged_na("a"), NA_real_, 1)
  labelled_values <- haven::labelled(values, labels = c(No = 0, Yes = 1))
  expect_s3_class(labelled_values, "haven_labelled")
  expect_identical(typeof(unclass(labelled_values)), "double")

  data <- data.frame(TRAN_IN = labelled_values)
  expect_no_warning(labelled <- nis_label(data))
  expect_identical(
    as.character(labelled$TRAN_IN),
    c(
      "No transfer",
      NA_character_,
      NA_character_,
      NA_character_,
      "Transferred from acute-care hospital"
    )
  )
  expect_identical(is.na(labelled$TRAN_IN), c(FALSE, TRUE, TRUE, TRUE, FALSE))
})

test_that("labelled_spss numeric NaN is missing and finite sentinel stays visible", {
  skip_if_not_installed("haven")
  values <- haven::labelled_spss(c(0, NaN, -9, 1), labels = c(No = 0, Yes = 1), na_values = -9)
  expect_s3_class(values, "haven_labelled_spss")
  expect_s3_class(values, "haven_labelled")
  expect_identical(typeof(unclass(values)), "double")
  data <- data.frame(TRAN_IN = values)
  warnings <- character()
  labelled <- withCallingHandlers(nis_label(data), warning = function(warning) {
    warnings <<- c(warnings, conditionMessage(warning))
    invokeRestart("muffleWarning")
  })

  expect_length(warnings, 1L)
  expect_match(warnings, "Unknown code.*TRAN_IN")
  expect_false(grepl("-9", warnings, fixed = TRUE))
  expect_identical(
    as.character(labelled$TRAN_IN),
    c("No transfer", NA_character_, "Code -9", "Transferred from acute-care hospital")
  )
  expect_identical(is.na(labelled$TRAN_IN), c(FALSE, TRUE, FALSE, FALSE))
})

test_that("mixed raw and labelled factor values use whole-vector normalization", {
  data <- data.frame(TRAN_IN = factor(c("0", "No transfer", "Code 7")))
  expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
  expect_identical(as.character(labelled$TRAN_IN), c("No transfer", "Code No transfer", "Code Code 7"))
  expect_identical(
    levels(labelled$TRAN_IN),
    c(
      "No transfer",
      "Transferred from acute-care hospital",
      "Transferred from another type of facility",
      "Code No transfer",
      "Code Code 7"
    )
  )
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("observed unknown codes remain distinct from missing values", {
  data <- data.frame(TRAN_IN = c("0", "NaN", "NA", "", " ", "01", "1.0", "-9", "\n", NA_character_))

  expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
  expect_identical(
    as.character(labelled$TRAN_IN),
    c(
      "No transfer",
      "Code NaN",
      "Code NA",
      "Code ",
      "Code  ",
      "Code 01",
      "Code 1.0",
      "Code -9",
      "Code \n",
      NA_character_
    )
  )
  expect_identical(
    levels(labelled$TRAN_IN),
    c(
      "No transfer",
      "Transferred from acute-care hospital",
      "Transferred from another type of facility",
      "Code NaN",
      "Code NA",
      "Code ",
      "Code  ",
      "Code 01",
      "Code 1.0",
      "Code -9",
      "Code \n"
    )
  )
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric unknown codes still warn while NaN remains missing", {
  data <- data.frame(TRAN_IN = c(0, NaN, -9, Inf, NA_real_, -9))
  warnings <- character()
  labelled <- withCallingHandlers(nis_label(data), warning = function(warning) {
    warnings <<- c(warnings, conditionMessage(warning))
    invokeRestart("muffleWarning")
  })

  expect_length(warnings, 1L)
  expect_match(warnings, "Unknown code.*TRAN_IN")
  expect_false(grepl("-9|Inf|NaN", warnings))
  expect_identical(
    as.character(labelled$TRAN_IN),
    c(
      "No transfer",
      NA_character_,
      "Code -9",
      "Code Inf",
      NA_character_,
      "Code -9"
    )
  )
  expect_identical(
    levels(labelled$TRAN_IN),
    c(
      "No transfer",
      "Transferred from acute-care hospital",
      "Transferred from another type of facility",
      "Code -9",
      "Code Inf"
    )
  )
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("numeric NaN handling preserves SPSS sentinel values", {
  data <- data.frame(TRAN_IN = structure(c(0, -9, 1), na_values = -9, class = c("synthetic_labelled_spss", "numeric")))

  expect_identical(is.na(data$TRAN_IN), c(FALSE, TRUE, FALSE))
  expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
  expect_identical(as.character(labelled$TRAN_IN), c("No transfer", "Code -9", "Transferred from acute-care hospital"))
  expect_identical(
    levels(labelled$TRAN_IN),
    c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility", "Code -9")
  )
})

test_that("raw factor levels resembling generated codes are still labelled", {
  data <- data.frame(TRAN_IN = factor("Code ", levels = c("0", "1", "Code ")))

  expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
  expect_identical(as.character(labelled$TRAN_IN), "Code Code ")
  expect_identical(
    levels(labelled$TRAN_IN),
    c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility", "Code Code ")
  )
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("raw factors decode displayed codes including empty unknown codes", {
  for (ordered in c(FALSE, TRUE)) {
    data <- data.frame(
      TRAN_IN = factor(c("0", "", "1", NA_character_), levels = c("unused", "1", "", "0"), ordered = ordered)
    )

    expect_warning(labelled <- nis_label(data), "Unknown code.*TRAN_IN")
    expect_identical(
      as.character(labelled$TRAN_IN),
      c("No transfer", "Code ", "Transferred from acute-care hospital", NA_character_)
    )
    expect_identical(
      levels(labelled$TRAN_IN),
      c("No transfer", "Transferred from acute-care hospital", "Transferred from another type of facility", "Code ")
    )
    expect_false(is.ordered(labelled$TRAN_IN))
    expect_no_warning(repeated <- nis_label(labelled))
    expect_identical(repeated, labelled)
  }
})

test_that("recognized factor labels survive raw code levels", {
  died <- factor(
    c("No transfer", "Transferred from acute-care hospital"),
    levels = c("0", "1", "No transfer", "Transferred from acute-care hospital")
  )
  data <- data.frame(TRAN_IN = died)

  expect_no_warning(labelled <- nis_label(data))
  expect_identical(as.character(labelled$TRAN_IN), as.character(died))
  expect_identical(levels(labelled$TRAN_IN), levels(died))
  expect_identical(nis_label(labelled), labelled)
})

test_that("subsets preserve Code labels with unused raw-code levels", {
  # Sol's compatibility reproduction: the subset retains its factor levels.
  died <- factor(c("No transfer", "Code 7"), levels = c("0", "No transfer", "Code 7"))[2]
  expect_no_warning(labelled <- nis_label(data.frame(TRAN_IN = died)))
  expect_identical(as.character(labelled$TRAN_IN), "Code 7")
  expect_identical(levels(labelled$TRAN_IN), levels(died))
  expect_no_warning(repeated <- nis_label(labelled))
  expect_identical(repeated, labelled)
})

test_that("bare Code factor labels remain stable despite ambiguous provenance", {
  # This is also the value generated from an empty raw code after levels drop.
  # A factor alone cannot tell those inputs apart, so treat it as already labelled.
  died <- factor("Code ")
  expect_no_warning(labelled <- nis_label(data.frame(TRAN_IN = died)))
  expect_identical(as.character(labelled$TRAN_IN), as.character(died))
  expect_identical(levels(labelled$TRAN_IN), levels(died))
  expect_identical(nis_label(labelled), labelled)

  expect_warning(generated <- nis_label(data.frame(TRAN_IN = c("0", ""))), "Unknown code.*TRAN_IN")
  dropped <- droplevels(generated[2L, , drop = FALSE])
  expect_identical(dropped$TRAN_IN, died)
  expect_no_warning(labelled_dropped <- nis_label(dropped))
  expect_identical(as.character(labelled_dropped$TRAN_IN), "Code ")

  # Unused raw-code levels give enough evidence to use raw-factor normalization.
  raw_factor <- factor("Code ", levels = c("0", "1", "Code "))
  expect_warning(normalized <- nis_label(data.frame(TRAN_IN = raw_factor)), "Unknown code.*TRAN_IN")
  expect_identical(as.character(normalized$TRAN_IN), "Code Code ")
  expect_identical(nis_label(normalized), normalized)

  # A nonempty suffix, including the synthetic newline value, is a label.
  newline <- factor("Code \n", levels = c("0", "Code \n"))
  expect_no_warning(labelled_newline <- nis_label(data.frame(TRAN_IN = newline)))
  expect_identical(as.character(labelled_newline$TRAN_IN), "Code \n")
  expect_identical(levels(labelled_newline$TRAN_IN), levels(newline))
  expect_identical(nis_label(labelled_newline), labelled_newline)

  subset <- generated[2L, , drop = FALSE]
  expect_no_warning(labelled_subset <- nis_label(subset))
  expect_no_warning(repeated_subset <- nis_label(labelled_subset))
  expect_identical(repeated_subset, labelled_subset)
})

test_that("existing labelled factors retain levels order and attributes", {
  for (ordered in c(FALSE, TRUE)) {
    died <- factor(
      c("No transfer", "Code ", "Code 7", NA_character_),
      levels = c("Code 7", "Transferred from acute-care hospital", "Code ", "No transfer", "unused"),
      ordered = ordered
    )
    attr(died, "label") <- "Existing outcome label"
    attr(died, "source") <- "Invented fixture"
    names(died) <- c("a", "b", "c", "d")
    data <- data.frame(TRAN_IN = died)

    expect_no_warning(labelled <- nis_label(data))
    expect_identical(labelled, data)
    expect_identical(nis_label(labelled), labelled)
  }
})

test_that("labelling preserves input row column and unrelated metadata", {
  data <- data.frame(
    id = c("third", "first", "second"),
    DIED = c(0, NaN, 1),
    AGE = c(30, 40, 50),
    row.names = c("row-c", "row-a", "row-b")
  )
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
  expect_identical(as.vector(labelled$DIED), c(FALSE, NA, TRUE))
  expect_identical(nis_label(labelled), labelled)
})
