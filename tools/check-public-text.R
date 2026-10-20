scan_public_text <- function(text) {
  text <- paste(text, collapse = "\n")
  rules <- c(
    small_count = "(?i)(?:\\b(?:n|count|patients?|discharges?|cases?)\\s*(?:=|:)?\\s*[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?\\b|\\b[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?\\s*(?:n|count|patients?|discharges?|cases?)\\b)",
    percentage_with_sample_size = "(?i)(?:\\b[0-9]+(?:\\.[0-9]*)?\\s*%[^\\n]{0,60}\\b(?:n|count|patients?|discharges?|cases?|sample\\s*size)\\s*(?:=|:)?\\s*[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?|\\b(?:n|count|patients?|discharges?|cases?|sample\\s*size)\\s*(?:=|:)?\\s*[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?[^\\n]{0,60}\\b[0-9]+(?:\\.[0-9]*)?\\s*%)",
    local_path = "(?i)(?:(?<![A-Za-z0-9_])[A-Z]:[/\\\\]|\\\\\\\\[^\\\\/]+[/\\\\][^\\\\/]+|(?<!:)//[^[:space:]<>\"']+|(?<![A-Za-z0-9_/:])/(?!/)[A-Za-z0-9._-]+(?:/|\\b))",
    ai_attribution = "(?i)\\b(?:Claude|Opus|Luna|Codex|GPT|T3\\s*Code)\\b"
  )
  hits <- names(rules)[vapply(rules, function(pattern) grepl(pattern, text, perl = TRUE), logical(1))]
  list(pass = !length(hits), findings = hits)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (identical(args, "--self-test")) {
    examples <- list(
      safe = "Fixes the survey design validation using a synthetic fixture.",
      url = "See https://example.org/documentation.",
      count = "n=5 patients were affected",
      scientific_count = "count=1e8 records",
      r_integer = "n=5L cases",
      percentage = "12% of cases (n=120)",
      path = "See C:\\sandbox\\invented person\\private folder",
      windows_path = "Open C:/work/nis/input.parquet",
      drive_path = "Open D:/NIS/input.parquet",
      unc_path = "Open \\\\server\\share\\folder with spaces",
      posix_path = "Open /srv/invented/nis.parquet",
      attribution = "Written by Codex"
    )
    results <- lapply(examples, scan_public_text)
    stopifnot(results$safe$pass, results$url$pass, !results$count$pass,
      !results$scientific_count$pass, !results$r_integer$pass,
      !results$percentage$pass, !results$path$pass, !results$windows_path$pass,
      !results$drive_path$pass, !results$unc_path$pass, !results$posix_path$pass,
      !results$attribution$pass)
    cat("Public-text guard self-tests passed.\n")
  } else {
    text <- if ("--stdin" %in% args) readLines(file("stdin"), warn = FALSE) else {
      paths <- setdiff(args, "--stdin")
      if (!length(paths)) stop("Pass a text file or --stdin.")
      readLines(paths[[1L]], warn = FALSE)
    }
    result <- scan_public_text(text)
    if (result$pass) cat("Public text passed the disclosure scan.\n") else {
      cat("Potential disclosure risks:", paste(result$findings, collapse = ", "), "\n")
      quit(status = 1L)
    }
  }
}
