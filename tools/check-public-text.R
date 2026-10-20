scan_public_text <- function(text) {
  text <- paste(text, collapse = "\n")
  text <- gsub("local/loop/<run>/private/", "local loop private output", text, fixed = TRUE)
  number <- "(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\\.[0-9]*)?(?:[eE][-+]?[0-9]+)?[iL]?"
  count_words <- paste(c("n", "count", "patients?", "discharges?", "cases?", "deaths?",
    "hospitalizations?", "admissions?", "stays?", "records?", "rows?", "observations?",
    "encounters?", "events?", "people"), collapse = "|")
  rules <- c(
    count = paste0("(?i)(?:\\b(?:", count_words, ")\\s*(?:=|:|<|<=|>|>=|≤|≥)?\\s*", number,
      "\\b|\\b", number, "\\s*(?:", count_words, ")\\b)"),
    n_range = paste0("(?i)\\bn\\s*(?:<|<=|>|>=|≤|≥)\\s*", number, "\\b|\\bn\\s+of\\s+", number, "\\b"),
    percentage_with_sample_size = paste0("(?i)(?:\\b", number, "\\s*%[^\\n]{0,80}\\b(?:", count_words,
      "|sample\\s*size)\\s*(?:=|:)?\\s*", number, "|\\b(?:", count_words,
      "|sample\\s*size)\\s*(?:=|:)?\\s*", number, "[^\\n]{0,80}\\b", number, "\\s*%)"),
    statistical_estimate = paste0("(?i)(?:\\b", number, "\\s*%[^\\n]{0,80}\\b(?:CI|confidence\\s+interval)\\b|",
      "\\b(?:OR|AOR|HR|RR|IRR)\\s*(?:=|:)?\\s*", number, "|\\b(?:CI|confidence\\s+interval)\\s*[:=]?[^\\n]{0,80}", number, ")"),
    local_path = "(?i)(?:(?<![A-Za-z0-9_])[A-Z]:[/\\\\]|\\\\\\\\[^\\\\/]+[/\\\\][^\\\\/]+|(?<!:)//[^[:space:]<>\"']+|(?<![A-Za-z0-9_/:])/(?!/)[A-Za-z0-9._-]+(?:/|\\b))",
    ai_attribution = "(?i)(?:\\b(?:Claude|Opus|Luna|Codex|T3\\s*Code|ChatGPT|OpenAI|Anthropic|Copilot|Gemini)\\b|GPT|Co-Authored-By|Generated\\s+with)"
  )
  hits <- names(rules)[vapply(rules, function(pattern) grepl(pattern, text, perl = TRUE), logical(1))]
  list(pass = !length(hits), findings = hits)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (identical(args, "--self-test")) {
    unsafe_counts <- c("n=5 patients", "count=1e8 records", "n=5L cases",
      "reported 7 deaths", "35,123 hospitalizations", "4 admissions",
      "dropped 3 records", "2 rows have", "8 people included", "n < 11", "n of 5")
    unsafe_estimates <- c("12% of cases (n=120)",
      "mortality was 4.27% (95% CI 3.9-4.6)",
      "Mean age 67.3 years; OR 1.45 (1.20-1.75)")
    unsafe_attributions <- c("Written by Codex", "Drafted with ChatGPT.",
      "Co-Authored-By: Example <noreply@example.org>", "Co-authored-by: GitHub Copilot")
    unsafe_paths <- c("C:\\sandbox\\invented person\\private folder",
      "Open C:/work/nis/input.parquet", "Open D:/NIS/input.parquet",
      "Open \\\\server\\share\\folder with spaces", "Open /srv/invented/nis.parquet")
    safe_text <- c("Fixes the survey design using a synthetic fixture.",
      "See https://example.org/documentation.",
      "See local/loop/<run>/private/ for local-only output.")
    stopifnot(all(vapply(unsafe_counts, function(x) !scan_public_text(x)$pass, logical(1))),
      all(vapply(unsafe_estimates, function(x) !scan_public_text(x)$pass, logical(1))),
      all(vapply(unsafe_attributions, function(x) !scan_public_text(x)$pass, logical(1))),
      all(vapply(unsafe_paths, function(x) !scan_public_text(x)$pass, logical(1))),
      all(vapply(safe_text, function(x) scan_public_text(x)$pass, logical(1))))
    cat("Public-text guard self-tests passed.\n")
  } else {
    file_args <- setdiff(args, "--stdin")
    if ("--stdin" %in% args) {
      text <- readLines(file("stdin"), warn = FALSE)
    } else {
      if (!length(file_args)) stop("Pass one or more text files or --stdin.")
      text <- unlist(lapply(file_args, readLines, warn = FALSE), use.names = FALSE)
    }
    result <- scan_public_text(text)
    if (result$pass) cat("Public text passed the disclosure scan.\n") else {
      cat("Potential disclosure risks:", paste(result$findings, collapse = ", "), "\n")
      quit(status = 1L)
    }
  }
}
