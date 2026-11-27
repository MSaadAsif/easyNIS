quality_evidence_valid <- function(item, current_commit, current_tree_clean) {
  is.list(item) &&
    isTRUE(current_tree_clean) &&
    valid_nonempty_string(current_commit) &&
    identical(item$commit, current_commit) &&
    identical(item$working_tree_clean, TRUE)
}

parse_quality_line <- function(line) {
  item <- tryCatch(jsonlite::parse_json(line, simplifyVector = FALSE), error = function(e) NULL)
  if (is.list(item) && !is.null(names(item)) && !anyDuplicated(names(item))) {
    required <- c("step", "status", "pass", "commit", "working_tree_clean")
    if (valid_named_fields(item, required)) {
      if (quality_receipt_shape_valid(item)) {
        return(item)
      }
      step <- if (valid_nonempty_string(item$step)) item$step else NULL
      return(invalid_quality_identity(step, item$commit))
    }
  }
  invalid_quality_line(line)
}

invalid_quality_line <- function(line) {
  recovered <- quality_line_fields(line)
  invalid_quality_identity(recovered$steps, recovered$commit)
}

invalid_quality_identity <- function(steps, commit = NULL) {
  steps <- unique(Filter(valid_nonempty_string, as.list(steps)))
  if (!length(steps)) {
    steps <- list(NULL)
  }
  if (!valid_nonempty_string(commit)) {
    commit <- NULL
  }
  structure(
    lapply(steps, function(step) {
      list(step = step, commit = commit, status = "invalid_evidence", pass = FALSE, invalid_evidence = TRUE)
    }),
    class = "invalid_quality_records"
  )
}

quality_receipt_step_status_valid <- function(item) {
  valid_nonempty_string(item$step) &&
    valid_nonempty_string(item$status) &&
    item$status %in%
      c("completed", "failed", "partial", "not_verified", "skipped_by_selection", "skipped_not_installed")
}

quality_boolean_pass_valid <- function(pass) {
  is.logical(pass) && length(pass) == 1L && !is.na(pass)
}

quality_receipt_pass_valid <- function(item) {
  valid_named_fields(item, "pass") &&
    (is.null(item[["pass", exact = TRUE]]) ||
      quality_boolean_pass_valid(item[["pass", exact = TRUE]]))
}

quality_receipt_tree_valid <- function(item) {
  valid_nonempty_string(item$commit) && quality_boolean_pass_valid(item$working_tree_clean)
}

quality_receipt_shape_valid <- function(item) {
  all(c(
    quality_receipt_step_status_valid(item),
    quality_receipt_pass_valid(item),
    quality_receipt_tree_valid(item)
  ))
}

quality_json_space <- function(chars, pos) {
  while (pos <= length(chars) && chars[[pos]] %in% c(" ", "\t", "\r", "\n")) {
    pos <- pos + 1L
  }
  pos
}

quality_json_string_end <- function(chars, pos) {
  if (pos >= length(chars) || chars[[pos]] != '"') {
    return(NA_integer_)
  }
  escaped <- FALSE
  for (i in seq.int(pos + 1L, length(chars))) {
    if (escaped) {
      escaped <- FALSE
    } else if (chars[[i]] == "\\") {
      escaped <- TRUE
    } else if (chars[[i]] == '"') {
      return(i)
    }
  }
  NA_integer_
}

quality_json_token <- function(chars, pos) {
  end <- quality_json_string_end(chars, pos)
  if (is.na(end)) {
    return(list(ok = FALSE))
  }
  token <- paste(chars[pos:end], collapse = "")
  value <- tryCatch(jsonlite::parse_json(token, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    return(list(ok = FALSE))
  }
  list(ok = TRUE, value = value, end = end + 1L)
}

quality_json_value <- function(chars, pos) {
  if (pos > length(chars)) {
    return(list(ok = FALSE))
  }
  if (chars[[pos]] == '"') {
    token <- quality_json_token(chars, pos)
    if (!token$ok) {
      return(token)
    }
    return(list(ok = TRUE, kind = "string", value = token$value, end = token$end))
  }
  if (chars[[pos]] %in% c("{", "[")) {
    return(quality_json_compound(chars, pos))
  }
  quality_json_primitive(chars, pos)
}

quality_json_primitive <- function(chars, pos) {
  end <- pos
  while (end <= length(chars) && !chars[[end]] %in% c(",", "]", "}", " ", "\t", "\r", "\n")) {
    end <- end + 1L
  }
  if (end == pos) {
    return(list(ok = FALSE))
  }
  token <- paste(chars[pos:(end - 1L)], collapse = "")
  value <- tryCatch(jsonlite::parse_json(token, simplifyVector = FALSE), error = function(e) {
    structure(list(), class = "invalid_json_value")
  })
  if (inherits(value, "invalid_json_value")) {
    return(list(ok = FALSE))
  }
  list(ok = TRUE, kind = "other", value = value, end = end)
}

quality_json_compound <- function(chars, pos) {
  end <- quality_json_compound_end(chars, pos)
  if (is.na(end)) {
    return(list(ok = FALSE))
  }
  token <- paste(chars[pos:end], collapse = "")
  value <- tryCatch(jsonlite::parse_json(token, simplifyVector = FALSE), error = function(e) {
    structure(list(), class = "invalid_json_value")
  })
  if (inherits(value, "invalid_json_value")) {
    return(list(ok = FALSE))
  }
  list(ok = TRUE, kind = if (chars[[pos]] == "{") "object" else "array", value = value, end = end + 1L)
}

quality_json_compound_end <- function(chars, pos) {
  if (pos >= length(chars)) {
    return(NA_integer_)
  }
  state <- list(stack = chars[[pos]], in_string = FALSE, escaped = FALSE, ok = TRUE)
  for (i in seq.int(pos + 1L, length(chars))) {
    state <- quality_json_compound_step(state, chars[[i]])
    if (!state$ok) {
      return(NA_integer_)
    }
    if (!length(state$stack)) return(i)
  }
  NA_integer_
}

quality_json_compound_step <- function(state, char) {
  if (state$in_string) {
    return(quality_json_string_step(state, char))
  }
  if (char == '"') {
    state$in_string <- TRUE
  }
  if (char %in% c("{", "[")) {
    state$stack <- c(state$stack, char)
  }
  if (char %in% c("}", "]")) {
    expected <- if (char == "}") "{" else "["
    if (tail(state$stack, 1L) != expected) {
      state$ok <- FALSE
    } else {
      state$stack <- head(state$stack, -1L)
    }
  }
  state
}

quality_json_string_step <- function(state, char) {
  if (state$escaped) {
    state$escaped <- FALSE
  } else if (char == "\\") {
    state$escaped <- TRUE
  } else if (char == '"') {
    state$in_string <- FALSE
  }
  state
}

quality_line_fields <- function(line) {
  chars <- strsplit(line, "", fixed = TRUE)[[1L]]
  pos <- quality_json_space(chars, 1L)
  if (pos > length(chars) || chars[[pos]] != "{") {
    return(list(steps = character(), commit = NULL))
  }
  fields <- quality_scan_top_fields(chars, pos + 1L)
  quality_recovered_identities(fields)
}

quality_scan_top_fields <- function(chars, pos) {
  fields <- list()
  repeat {
    field <- quality_scan_top_field(chars, pos)
    if (!field$found) {
      break
    }
    fields[[length(fields) + 1L]] <- field
    if (!field$complete || field$done) {
      break
    }
    pos <- field$next_pos
  }
  fields
}

quality_scan_top_field <- function(chars, pos) {
  pos <- quality_json_space(chars, pos)
  key <- quality_json_token(chars, pos)
  if (!isTRUE(key$ok)) {
    return(list(found = FALSE))
  }
  field <- list(
    found = TRUE,
    name = key$value,
    complete = FALSE,
    value = NULL,
    kind = NULL,
    next_pos = pos,
    done = FALSE
  )
  pos <- quality_json_space(chars, key$end)
  if (pos > length(chars) || chars[[pos]] != ":") {
    return(field)
  }
  value <- quality_json_value(chars, quality_json_space(chars, pos + 1L))
  if (!isTRUE(value$ok)) {
    return(field)
  }
  pos <- quality_json_space(chars, value$end)
  if (pos > length(chars)) {
    field$value <- value$value
    field$kind <- value$kind
    field$terminal_string <- identical(value$kind, "string")
    return(field)
  }
  if (!chars[[pos]] %in% c(",", "}")) {
    return(field)
  }
  field$complete <- TRUE
  field$value <- value$value
  field$kind <- value$kind
  field$done <- chars[[pos]] == "}"
  field$next_pos <- pos + 1L
  field
}

quality_recovered_step <- function(field) {
  if (
    (isTRUE(field$complete) || isTRUE(field$terminal_string)) &&
      identical(field$name, "step") &&
      identical(field$kind, "string")
  ) {
    field$value
  } else {
    NA_character_
  }
}

quality_recovered_commit_value <- function(field) {
  if (isTRUE(field$complete) && identical(field$name, "commit") && identical(field$kind, "string")) {
    field$value
  } else {
    NA_character_
  }
}

quality_recovered_identities <- function(fields) {
  names <- vapply(fields, `[[`, character(1), "name")
  steps <- vapply(fields, quality_recovered_step, character(1))
  commits <- vapply(fields, quality_recovered_commit_value, character(1))
  list(steps = unique(steps[!is.na(steps)]), commit = quality_recovered_commit(names, commits))
}

quality_recovered_commit <- function(names, commits) {
  if (sum(names == "commit") != 1L || sum(!is.na(commits)) != 1L) {
    return(NULL)
  }
  commits[!is.na(commits)][[1L]]
}

read_raw_bytes <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection))
  readBin(connection, what = "raw", n = file.info(path)$size)
}

quality_read_raw_lines <- function(path) {
  bytes <- read_raw_bytes(path)
  if (!length(bytes)) {
    return(list())
  }
  lines <- list()
  start <- 1L
  position <- 1L
  while (position <= length(bytes)) {
    byte <- bytes[[position]]
    if (byte %in% as.raw(c(0x0A, 0x0D))) {
      end <- position - 1L
      lines[[length(lines) + 1L]] <- if (start <= end) bytes[start:end] else raw()
      if (byte == as.raw(0x0D) && position < length(bytes) && bytes[[position + 1L]] == as.raw(0x0A)) {
        position <- position + 1L
      }
      start <- position + 1L
    }
    position <- position + 1L
  }
  if (start <= length(bytes)) {
    lines[[length(lines) + 1L]] <- bytes[start:length(bytes)]
  }
  lines
}

quality_parse_raw_line <- function(bytes) {
  nul <- which(bytes == as.raw(0))
  if (!length(nul)) {
    return(parse_quality_line(rawToChar(bytes)))
  }
  prefix <- if (nul[[1L]] > 1L) rawToChar(bytes[seq_len(nul[[1L]] - 1L)]) else ""
  invalid_quality_line(prefix)
}

load_quality_evidence <- function(files) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  unlist(
    lapply(files, function(file) {
      lines <- tryCatch(quality_read_raw_lines(file), error = function(e) list())
      unlist(
        lapply(lines, function(line) {
          item <- quality_parse_raw_line(line)
          if (inherits(item, "invalid_quality_records")) {
            return(item)
          }
          list(item)
        }),
        recursive = FALSE
      )
    }),
    recursive = FALSE
  )
}

quality_evidence_invalid <- function(item) {
  isTRUE(item$invalid_evidence) || identical(item$status, "invalid_evidence")
}

quality_evidence_stale <- function(item, current_commit) {
  valid_nonempty_string(item$commit) && !identical(item$commit, current_commit)
}

quality_evidence_should_apply <- function(item, current_commit) {
  if (!quality_step_identifiable(item)) {
    return(FALSE)
  }
  if (quality_evidence_stale(item, current_commit)) {
    return(FALSE)
  }
  if (quality_evidence_invalid(item)) {
    return(TRUE)
  }
  if (quality_receipt_shape_valid(item) && identical(item$working_tree_clean, FALSE)) {
    return(FALSE)
  }
  if (quality_item_skipped(item)) {
    return(FALSE)
  }
  TRUE
}

merge_quality_evidence <- function(quality, current_commit) {
  quality_by_step <- list()
  for (item in quality) {
    if (quality_evidence_should_apply(item, current_commit)) {
      quality_by_step[[item$step]] <- item
    }
  }
  quality_by_step
}

quality_step_identifiable <- function(item) {
  is.list(item) && valid_nonempty_string(item$step)
}

quality_item_skipped <- function(item) {
  valid_named_fields(item, c("step", "status", "pass", "commit", "working_tree_clean")) &&
    quality_skip_identity_valid(item) &&
    quality_skip_status_valid(item) &&
    quality_skip_tree_valid(item) &&
    is.null(item$pass)
}

quality_skip_identity_valid <- function(item) {
  valid_nonempty_string(item$step) && valid_nonempty_string(item$commit)
}

quality_skip_status_valid <- function(item) {
  identical(item$status, "skipped_by_selection")
}

quality_skip_tree_valid <- function(item) {
  is.logical(item$working_tree_clean) && length(item$working_tree_clean) == 1L && !is.na(item$working_tree_clean)
}

coverage_percent_value <- function(item) {
  value <- if (is.list(item)) item[["value", exact = TRUE]] else NULL
  if (!valid_coverage_percent(value)) {
    return(NA_real_)
  }
  as.numeric(value)
}

coverage_percent_record <- function(coverage_check, evidence, percent_coverage) {
  coverage <- coverage_check$value
  if (identical(coverage, "skipped_by_selection")) {
    return(NULL)
  }
  if (inherits(coverage, "coverage")) {
    value <- percent_coverage(coverage)
    valid <- valid_coverage_percent(value)
    return(list(
      step = "coverage_percent",
      status = if (valid) "completed" else "not_verified",
      pass = if (valid) value >= 90 else NA,
      value = value,
      commit = evidence$commit,
      working_tree_clean = evidence$working_tree_clean
    ))
  }
  list(
    step = "coverage_percent",
    status = "failed",
    pass = FALSE,
    value = NA_real_,
    error_class = coverage_check$error_class,
    commit = evidence$commit,
    working_tree_clean = evidence$working_tree_clean
  )
}

valid_coverage_percent <- function(value) {
  is.numeric(value) && length(value) == 1L && is.finite(value) && value >= 0 && value <= 100
}
