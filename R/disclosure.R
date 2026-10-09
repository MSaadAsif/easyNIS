#' Review an experimental descriptive table for disclosure
#'
#' Applies caller-declared primary and complementary suppression to one
#' [nis_descriptive_table()] using unweighted included discharge counts and
#' contributing hospitals. Only `presentation` is an export candidate. The
#' review assists a human publication check and does not certify a manuscript.
#'
#' @param table An experimental [nis_descriptive_table()] result.
#' @param suppress Whole-number vector `c(lower, upper)` with
#'   `1 <= lower <= upper`. Checked counts in this inclusive range are
#'   disclosive. `c(1, 10)` reproduces the DUA range recorded in the package
#'   documentation; easyNIS supplies no default.
#' @param zero Explicitly choose `"display"` or `"suppress"` for zero nonzero or
#'   binary zero-valued counts and zero margin sums. Zero missing counts are
#'   never disclosive.
#' @param min_hospitals Positive whole number. Checked discharge groups from
#'   fewer distinct first-level clusters are disclosive.
#' @param margins A list, possibly empty, of additive relations. Each is a list
#'   with exactly a `total` row ID and distinct `parts` row IDs, declaring
#'   total = sum(parts) in raw counts. The relation must hold exactly.
#' @return A `nis_disclosure_review` list with `presentation`, `audit`, the
#'   unchanged `table` and `provenance`. `presentation` contains `id`, `label`,
#'   `statistic`, `unit`, `estimand`, `estimate`, `se`, `lower`, `upper`, `df`,
#'   `confidence`, `unweighted_n` and `disclosure_status` (`shown`,
#'   `suppressed_primary` or `suppressed_complementary`). Suppressed rows have
#'   `NA` values. `audit` and `table` contain raw counts and must stay local.
#' @details Every row checks included, missing and nonzero discharge counts.
#'   Binary fields also check zero-valued discharges, and other two-valued
#'   fields check their smaller level. Nonempty groups also check their
#'   contributing hospitals. Margins compare nonzero counts for binary rows and
#'   included counts otherwise. Complementary suppression repeats until rows on
#'   a suppressed field are all suppressed, no single margin recovers one
#'   suppressed row or a disclosive or single-hospital suppressed sum, no
#'   combination of margins determines a suppressed field, and no two published
#'   `unweighted_n` values differ by a disclosive amount. The procedure is
#'   greedy, conservative and limited to declared relations. Annual support and
#'   scientific approval remain pending.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$domain <- core$HOSP_NIS %in% c("0001", "0003")
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022),
#'     c("LOS", "domain"), TRUE, "hospital_wr", "fail")
#'   specification <- data.frame(id = c("los", "domain"),
#'     field = c("LOS", "domain"), statistic = c("mean", "proportion"),
#'     label = c("Length of stay", "Domain share"),
#'     unit = c("days", "proportion"))
#'   table <- nis_descriptive_table(design, specification, "fail", 2,
#'     0.95, "wr_unadjusted")
#'   review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
#'   review$presentation
#'   nis_close(session)
#'   unlink(path)
#' }
nis_disclosure_review <- function(table, suppress, zero, min_hospitals, margins) {
  if (!inherits(table, "nis_descriptive_table") || !is.data.frame(table$data) ||
      !is.list(table$results) || !identical(names(table$results), table$data$id)) {
    stop("`table` must be a nis_descriptive_table result.", call. = FALSE)
  }
  if (base::missing(suppress) || base::missing(zero) || base::missing(min_hospitals) ||
      base::missing(margins)) {
    stop("Choose explicit `suppress`, `zero`, `min_hospitals` and `margins` policies.",
         call. = FALSE)
  }
  if (!is_whole(suppress, 2L) || suppress[[1L]] < 1 || suppress[[1L]] > suppress[[2L]]) {
    stop("`suppress` must be whole numbers c(lower, upper) with 1 <= lower <= upper.",
         call. = FALSE)
  }
  suppress <- as.double(suppress)
  check_string(zero, "zero")
  if (!zero %in% c("display", "suppress")) {
    stop("`zero` must be \"display\" or \"suppress\".", call. = FALSE)
  }
  if (!is_whole(min_hospitals, 1L) || min_hospitals < 1) {
    stop("`min_hospitals` must be one positive whole number.", call. = FALSE)
  }
  min_hospitals <- as.double(min_hospitals)
  ids <- table$data$id
  margins <- check_margins(margins, ids)
  in_range <- function(count) count >= suppress[[1L]] & count <= suppress[[2L]]
  disclosive <- function(count) in_range(count) | (zero == "suppress" & count == 0)

  fields <- vapply(table$results, function(x) x$provenance$field, character(1), USE.NAMES = FALSE)
  rows <- lapply(seq_along(ids), function(i) {
    result <- table$results[[i]]
    value <- result$design$variables[[fields[[i]]]]
    if (inherits(value, "integer64")) value <- as.double(as.character(value))
    hospital <- as.character(result$design$cluster[[1L]])
    if (length(value) != length(hospital) || anyNA(value)) {
      stop("Row `", ids[[i]], "` does not retain its included outcome values.", call. = FALSE)
    }
    list(value = value, hospital = hospital,
         binary = is.logical(value) || all(value %in% c(0, 1)))
  })
  audit <- do.call(rbind, lapply(seq_along(ids), function(i) {
    value <- rows[[i]]$value
    hospital <- rows[[i]]$hospital
    nonzero <- value != 0
    levels <- if (!rows[[i]]$binary && length(unique(value)) == 2L) split(hospital, value) else list()
    data.frame(id = ids[[i]], field = fields[[i]], binary = rows[[i]]$binary,
      included = as.double(length(value)),
      missing = as.double(table$results[[i]]$sample$excluded_missing),
      nonzero = as.double(sum(nonzero)),
      zero_valued = as.double(sum(!nonzero)),
      two_level_minimum = if (length(levels)) as.double(min(lengths(levels))) else NA_real_,
      hospitals_included = as.double(length(unique(hospital))),
      hospitals_nonzero = as.double(length(unique(hospital[nonzero]))),
      hospitals_zero_valued = as.double(length(unique(hospital[!nonzero]))),
      hospitals_two_level = if (length(levels)) {
        as.double(min(vapply(levels, function(h) length(unique(h)), integer(1))))
      } else NA_real_,
      stringsAsFactors = FALSE)
  }))
  audit$margin_count <- ifelse(audit$binary, audit$nonzero, audit$included)
  margin_hospitals <- lapply(rows, function(row) {
    if (row$binary) row$hospital[row$value != 0] else row$hospital
  })
  reasons <- vector("list", nrow(audit))
  for (i in seq_len(nrow(audit))) {
    row <- audit[i, ]
    two_level <- !is.na(row$two_level_minimum)
    failed <- c(
      included = disclosive(row$included),
      missing = in_range(row$missing),
      nonzero = disclosive(row$nonzero),
      zero_valued = row$binary && disclosive(row$zero_valued),
      two_level = two_level && in_range(row$two_level_minimum),
      hospitals_included = row$hospitals_included < min_hospitals,
      hospitals_nonzero = row$nonzero > 0 && row$hospitals_nonzero < min_hospitals,
      hospitals_zero_valued = row$binary && row$zero_valued > 0 &&
        row$hospitals_zero_valued < min_hospitals,
      hospitals_two_level = two_level && row$hospitals_two_level < min_hospitals)
    reasons[[i]] <- names(failed)[failed]
  }
  status <- ifelse(lengths(reasons) > 0L, "suppressed_primary", "shown")

  for (relation in margins) {
    if (audit$margin_count[match(relation$total, ids)] !=
        sum(audit$margin_count[match(relation$parts, ids)])) {
      stop("Margin total `", relation$total,
           "` does not equal the sum of its parts in raw counts.", call. = FALSE)
    }
  }
  unique_fields <- unique(fields)
  # Each relation is total - sum(parts) = 0 over field-level raw counts.
  equations <- matrix(0, length(margins), length(unique_fields))
  for (k in seq_along(margins)) {
    columns <- match(fields[match(c(margins[[k]]$total, margins[[k]]$parts), ids)], unique_fields)
    signs <- c(1, rep(-1, length(margins[[k]]$parts)))
    for (j in seq_along(columns)) {
      equations[k, columns[[j]]] <- equations[k, columns[[j]]] + signs[[j]]
    }
  }
  hide_row <- function(pick, reason) {
    status[[pick]] <<- "suppressed_complementary"
    reasons[[pick]] <<- reason
  }
  smallest <- function(candidates) candidates[order(audit$margin_count[candidates], candidates)][[1L]]
  repeat {
    repaired <- FALSE
    for (i in which(status != "shown")) {
      for (j in which(status == "shown" & fields == fields[[i]])) {
        hide_row(j, paste0("field:", ids[[i]]))
        repaired <- TRUE
      }
    }
    if (repaired) next
    for (k in seq_along(margins)) {
      members <- match(c(margins[[k]]$total, margins[[k]]$parts), ids)
      hidden <- members[status[members] != "shown"]
      published <- members[status[members] == "shown"]
      if (!length(hidden) || !length(published)) next
      total_hidden <- status[members[[1L]]] != "shown"
      exposed <- length(hidden) == 1L || (!total_hidden &&
        (disclosive(sum(audit$margin_count[hidden])) ||
         length(unique(unlist(margin_hospitals[hidden]))) < min_hospitals))
      if (!exposed) next
      hide_row(smallest(published), paste0("margin:", k))
      repaired <- TRUE
      break
    }
    if (repaired) next
    hidden_fields <- unique_fields %in% fields[status != "shown"]
    if (length(margins) && any(hidden_fields)) {
      reduced <- equations[, hidden_fields, drop = FALSE]
      rank <- qr(reduced)$rank
      for (j in which(hidden_fields & colSums(equations != 0) > 0)) {
        unit <- as.double(unique_fields[hidden_fields] == unique_fields[[j]])
        if (qr(rbind(reduced, unit))$rank > rank) next
        related <- which(equations[, j] != 0)
        candidates <- unique(unlist(lapply(margins[related], function(relation) {
          match(c(relation$total, relation$parts), ids)
        })))
        candidates <- candidates[status[candidates] == "shown"]
        if (!length(candidates)) next
        hide_row(smallest(candidates), paste0("margins:", unique_fields[[j]]))
        repaired <- TRUE
        break
      }
    }
    if (repaired) next
    shown_rows <- which(status == "shown")
    for (a in shown_rows) {
      gap <- abs(audit$included[shown_rows] - audit$included[[a]])
      partner <- shown_rows[gap > 0 & in_range(gap)]
      if (!length(partner)) next
      pair <- c(a, partner[[1L]])
      pick <- pair[order(-audit$missing[pair], -pair)][[1L]]
      hide_row(pick, paste0("n_difference:", ids[[setdiff(pair, pick)]]))
      repaired <- TRUE
      break
    }
    if (!repaired) break
  }
  audit$reasons <- vapply(reasons, paste, character(1), collapse = ";")
  audit$disclosure_status <- status
  rownames(audit) <- NULL

  shown <- status == "shown"
  hide <- function(x) ifelse(shown, x, NA_real_)
  data <- table$data
  presentation <- data.frame(id = data$id, label = data$label,
    statistic = data$statistic, unit = data$unit, estimand = data$estimand,
    estimate = hide(data$weighted_estimate), se = hide(data$se),
    lower = hide(data$lower), upper = hide(data$upper),
    df = data$df, confidence = data$confidence,
    unweighted_n = hide(audit$included), disclosure_status = status,
    stringsAsFactors = FALSE)
  provenance <- list(policy = list(suppress = suppress, zero = zero,
      min_hospitals = min_hospitals, margins = margins),
    rule_source = "caller policy; docs/DISCLOSURE.md records the HCUP Nationwide DUA 1-10 guidance",
    count_basis = "unweighted included discharges",
    complementary = "greedy: same-field rows, declared relation recovery and sums, linear determination, unweighted n differences",
    table = table$provenance, scope = "experimental_disclosure_review",
    analysis_ready = FALSE)
  structure(list(presentation = presentation, audit = audit, table = table,
    provenance = provenance), class = "nis_disclosure_review")
}

is_whole <- function(x, n) {
  is.numeric(x) && !is.object(x) && is.null(dim(x)) && length(x) == n &&
    !anyNA(x) && all(is.finite(x)) && all(x == round(x))
}

check_margins <- function(margins, ids) {
  if (!is.list(margins) || is.object(margins)) {
    stop("`margins` must be a plain list of additive relations.", call. = FALSE)
  }
  lapply(margins, function(relation) {
    if (!is.list(relation) || is.object(relation) || length(relation) != 2L ||
        !setequal(names(relation), c("total", "parts")) ||
        !is.character(relation$total) || length(relation$total) != 1L ||
        !is.character(relation$parts) || length(relation$parts) < 1L ||
        anyNA(c(relation$total, relation$parts)) ||
        anyDuplicated(c(relation$total, relation$parts)) ||
        any(!c(relation$total, relation$parts) %in% ids)) {
      stop("Each margin must be list(total = id, parts = ids) with distinct existing row IDs.",
           call. = FALSE)
    }
    list(total = relation$total, parts = unname(relation$parts))
  })
}
