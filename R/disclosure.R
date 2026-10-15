#' Review an experimental descriptive or regression table for disclosure
#'
#' Applies caller-declared primary and complementary suppression to one
#' [nis_descriptive_table()], or coefficient suppression to one
#' [nis_regression_table()], using unweighted included discharge counts and
#' contributing hospitals. Only `presentation` is an export candidate. The
#' review assists a human publication check and does not certify a manuscript.
#'
#' @param table One experimental [nis_descriptive_table()] constructor result,
#'   optionally grouped by a retained factor, or one unchanged
#'   [nis_regression_table()] result.
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
#'   Regression reviews require `list()`.
#' @return A `nis_disclosure_review` list with `presentation`, `audit`, the
#'   unchanged `table` and `provenance`. `presentation` contains `id`, `label`,
#'   `statistic`, `unit`, `estimand`, `estimate`, `se`, `lower`, `upper`, `df`,
#'   `confidence`, `unweighted_n` and `disclosure_status` (`shown`,
#'   `suppressed_primary` or `suppressed_complementary`). Suppressed rows have
#'   `NA` values. `audit` and `table` contain raw counts and must stay local.
#'   A regression review instead has `presentation` columns `id`, `term`,
#'   `label`, `unit`, `estimate`, `se`, `statistic`, `p_value`, `lower`,
#'   `upper`, `aliased`, `coefficient_scale`, `family`, `link`, `df`,
#'   `confidence`, `unweighted_n` and `disclosure_status` (`shown` or
#'   `suppressed`), an `audit` list of `sample`, `groups` and `rows`, and
#'   `provenance$table_kind = "regression"`.
#' @details In a descriptive table, every row checks included, missing and
#'   nonzero discharge counts. Binary fields also check zero-valued discharges,
#'   and other two-valued fields check their smaller level. Nonempty groups
#'   also check their contributing hospitals. Margins compare nonzero counts
#'   for binary rows and
#'   included counts otherwise. Complementary suppression repeats until rows on
#'   a suppressed field are all suppressed, no single margin recovers one
#'   suppressed row or a disclosive or single-hospital suppressed sum, no
#'   combination of margins determines a suppressed field or a protected sum,
#'   and no two published `unweighted_n` values differ by a disclosive amount.
#'   Protected sums are frozen before repairs: primary-hidden parts within each
#'   relation and pairs of primary-hidden fields participating in margins, when
#'   their summed raw counts or contributing hospitals fail the policy. These
#'   are additive raw counts, with repeated fields counted repeatedly; their
#'   hospital count uses the union of contributing hospitals. Count equality
#'   alone does not establish that the underlying groups are disjoint. The call
#'   uses separate count identities for exact fields in distinct complete group
#'   domain histories, keeping repeated statistics together within a group.
#'   Grouping provenance and retained factor membership must agree. Internal
#'   identities and domain histories are never presentation columns. Combining
#'   separate tables, overall rows and between-group tests are outside this scope.
#'   The call
#'   fails if declarations alone determine a protected hidden target. The
#'   procedure is greedy and conservative within these bounded checks, not a
#'   search over all subsets or nonnegative/whole-number constraints. Undeclared
#'   relations and external tables require human review. Annual support and
#'   scientific approval remain pending.
#'
#'   A regression table must match its retained model's coefficient table and
#'   declarations exactly; altered objects are refused. Counts come from the
#'   model's included analysis rows. The model checks its included count and,
#'   for a binary (logical or zero/one) response, its event and nonevent
#'   counts; a failure suppresses every row and `unweighted_n`. Each fitted
#'   model-matrix column with two distinct values checks both levels, and with a
#'   binary response their four level-by-outcome cells; a column with more
#'   values checks its nonzero and any zero-valued count. Every fitted level of
#'   each factor or logical predictor, including the reference and zero-count
#'   levels, is checked, with outcome cells for a binary response. A failed
#'   column suppresses its rows and constant columns such as the intercept. A
#'   failed factor suppresses every term containing it and the lower-order terms
#'   within those terms. Rows repeating a term share its status. Suppressed rows
#'   have `NA` inference and `aliased` values. Differencing across models,
#'   disclosive weights, offsets and continuous extremes are not checked.
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
  regression <- inherits(table, "nis_regression_table")
  if (!regression && (!inherits(table, "nis_descriptive_table") || !is.data.frame(table$data) ||
      !is.list(table$results) || !identical(names(table$results), table$data$id))) {
    stop("`table` must be a nis_descriptive_table or nis_regression_table result.", call. = FALSE)
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
  if (regression) return(regression_disclosure_review(table, suppress, zero, min_hospitals, margins))
  ids <- table$data$id
  margins <- check_margins(margins, ids)
  in_range <- function(count) count >= suppress[[1L]] & count <= suppress[[2L]]
  disclosive <- function(count) in_range(count) | (zero == "suppress" & count == 0)

  source_fields <- vapply(table$results, function(x) x$provenance$field, character(1), USE.NAMES = FALSE)
  grouped <- !is.null(table$provenance$grouping)
  fields <- if (grouped) grouped_count_identity(table, source_fields) else source_fields
  rows <- lapply(seq_along(ids), function(i) {
    result <- table$results[[i]]
    value <- result$design$variables[[source_fields[[i]]]]
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
    levels <- if (!rows[[i]]$binary && length(unique(value)) == 2L) {
      split(hospital, match(value, unique(value)))
    } else list()
    data.frame(id = ids[[i]], field = source_fields[[i]], binary = rows[[i]]$binary,
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
  if (grouped) audit$count_identity <- fields
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
  primary <- status == "suppressed_primary"

  for (relation in margins) {
    if (audit$margin_count[match(relation$total, ids)] !=
        sum(audit$margin_count[match(relation$parts, ids)])) {
      stop("Margin total `", relation$total,
           "` does not equal the sum of its parts in raw counts.", call. = FALSE)
    }
  }
  unique_fields <- unique(fields)
  # Each relation is total - sum(parts) = 0 over count identities.
  equations <- matrix(0, length(margins), length(unique_fields))
  for (k in seq_along(margins)) {
    columns <- match(fields[match(c(margins[[k]]$total, margins[[k]]$parts), ids)], unique_fields)
    signs <- c(1, rep(-1, length(margins[[k]]$parts)))
    for (j in seq_along(columns)) {
      equations[k, columns[[j]]] <- equations[k, columns[[j]]] + signs[[j]]
    }
  }
  declaration_rank <- if (length(margins)) qr(equations)$rank else 0L
  # Freeze these targets before complementary rows enlarge the hidden sets.
  protected_sums <- list()
  add_sum <- function(members, label) {
    if (length(members) < 2L ||
        !(disclosive(sum(audit$margin_count[members])) ||
          length(unique(unlist(margin_hospitals[members]))) < min_hospitals)) return()
    protected_sums[[length(protected_sums) + 1L]] <<- list(
      coefficients = as.double(tabulate(match(fields[members], unique_fields),
        nbins = length(unique_fields))), label = label)
  }
  for (k in seq_along(margins)) {
    parts <- match(margins[[k]]$parts, ids)
    add_sum(parts[primary[parts]], paste0("relation:", k))
  }
  primary_rows <- match(unique(fields[primary]), fields)
  primary_rows <- primary_rows[colSums(equations != 0)[match(fields[primary_rows], unique_fields)] > 0]
  if (length(primary_rows) > 1L) {
    for (a in seq_len(length(primary_rows) - 1L)) {
      for (b in seq.int(a + 1L, length(primary_rows))) {
        pair <- primary_rows[c(a, b)]
        add_sum(pair, paste0("pair:", paste(fields[pair], collapse = "+")))
      }
    }
  }
  # A repair may need a published field several relations away from the target.
  connected_rows <- function(coefficients) {
    connected <- coefficients != 0
    repeat {
      related <- rowSums(equations[, connected, drop = FALSE] != 0) > 0
      expanded <- connected | colSums(equations[related, , drop = FALSE] != 0) > 0
      if (identical(connected, expanded)) break
      connected <- expanded
    }
    which(fields %in% unique_fields[connected])
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
      targets <- lapply(which(hidden_fields & colSums(equations != 0) > 0), function(j) {
        list(coefficients = as.double(seq_along(unique_fields) == j),
          label = unique_fields[[j]], reason = paste0("margins:", unique_fields[[j]]))
      })
      targets <- c(targets, lapply(protected_sums, function(target) {
        target$reason <- paste0("margins_sum:", target$label)
        target
      }))
      for (target in targets) {
        if (qr(rbind(reduced, target$coefficients[hidden_fields]))$rank > rank) next
        if (qr(rbind(equations, target$coefficients))$rank == declaration_rank) {
          stop("Margin declarations alone determine protected hidden target `",
               target$label, "`; suppression cannot repair this review.", call. = FALSE)
        }
        candidates <- connected_rows(target$coefficients)
        candidates <- candidates[status[candidates] == "shown"]
        if (!length(candidates)) {
          stop("No published row can protect hidden margin target `", target$label,
               "`; suppression cannot repair this review.", call. = FALSE)
        }
        hide_row(smallest(candidates), target$reason)
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
    complementary = if (grouped) {
      "greedy: same-field/domain rows, declared relation recovery and sums, hidden count identities and bounded primary sums across margins, unweighted n differences"
    } else "greedy: same-field rows, declared relation recovery and sums, hidden fields and bounded primary sums across margins, unweighted n differences",
    table = table$provenance, scope = "experimental_disclosure_review",
    analysis_ready = FALSE)
  structure(list(presentation = presentation, audit = audit, table = table,
    provenance = provenance), class = "nis_disclosure_review")
}

grouped_count_identity <- function(table, fields) {
  refuse <- function() stop("Grouped table has inconsistent grouping provenance or retained results.",
                            call. = FALSE)
  plain_list <- function(x) is.list(x) && !is.object(x)
  labels <- function(x) is.character(x) && is.null(attributes(x)) &&
    !anyNA(x) && all(nzchar(trimws(x))) && !anyDuplicated(x)
  grouping <- table$provenance$grouping
  parent <- table$provenance$domains
  policies <- table$provenance$policies
  if (!plain_list(grouping) ||
      !identical(names(grouping), c("field", "observed_levels", "unused_levels", "unknown", "missing")) ||
      !labels(grouping$field) || length(grouping$field) != 1L ||
      !labels(grouping$observed_levels) || !length(grouping$observed_levels) ||
      !labels(grouping$unused_levels) ||
      any(grouping$unused_levels %in% grouping$observed_levels) ||
      !is_whole(grouping$unknown, 1L) || grouping$unknown < 0 ||
      !identical(grouping$missing, "fail") && !identical(grouping$missing, "exclude") ||
      (grouping$missing == "fail" && grouping$unknown != 0) ||
      !plain_list(parent) || !plain_list(policies) ||
      !identical(fields, table$data$field)) refuse()
  histories <- list()
  domain <- integer(length(table$results))
  supplied <- NULL
  for (i in seq_along(table$results)) {
    result <- table$results[[i]]
    provenance <- result$provenance
    history <- provenance$domains
    if (!identical(provenance$design, table$provenance$constructor) ||
        !identical(provenance$population, table$provenance$population) ||
        !identical(provenance$statistic, table$data$statistic[[i]]) ||
        !identical(provenance$missing, policies$missing) ||
        !identical(provenance$variance, policies$variance) ||
        !identical(provenance$df, as.double(policies$df)) ||
        !identical(provenance$confidence, as.double(policies$confidence)) ||
        !plain_list(history) || length(history) != length(parent) + 1L ||
        !identical(history[seq_along(parent)], parent)) refuse()
    last <- history[[length(history)]]
    if (!plain_list(last) || !identical(last$fields, grouping$field) ||
        !identical(last$missing, grouping$missing) ||
        !is_whole(last$included, 1L) || last$included < 1 ||
        !identical(as.double(last$included), as.double(result$sample$supplied)) ||
        !identical(as.double(last$unknown), as.double(grouping$unknown)) ||
        !is_whole(last$supplied, 1L)) refuse()
    if (is.null(supplied)) supplied <- last$supplied
    if (!identical(last$supplied, supplied)) refuse()
    same <- which(vapply(histories, identical, logical(1), history))
    if (!length(same)) {
      histories[[length(histories) + 1L]] <- history
      same <- length(histories)
    }
    domain[[i]] <- same[[1L]]
    if (domain[[i]] > length(grouping$observed_levels)) refuse()
    group <- result$design$variables[[grouping$field]]
    if (!identical(class(group), "factor") || !is.null(dim(group)) ||
        !length(group) || anyNA(group) ||
        length(group) != result$sample$included ||
        anyNA(as.character(group)) ||
        any(as.character(group) != grouping$observed_levels[[domain[[i]]]])) refuse()
  }
  if (length(histories) != length(grouping$observed_levels)) refuse()
  paste0("d", domain, ".f", match(fields, unique(fields)))
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

regression_disclosure_review <- function(table, suppress, zero, min_hospitals, margins) {
  if (!identical(margins, list())) {
    stop("Regression reviews require `margins = list()`; coefficients are not additive counts.",
         call. = FALSE)
  }
  fit <- regression_review_fit(table)
  x <- fit$matrix
  hospital <- fit$hospital
  in_range <- function(count) count >= suppress[[1L]] & count <= suppress[[2L]]
  disclosive <- function(count) in_range(count) | (zero == "suppress" & count == 0)
  binary <- is.logical(fit$response) || all(fit$response %in% c(0, 1))
  event <- if (binary) as.double(fit$response) == 1 else NULL
  groups <- list()
  # Records one unweighted group; nonempty groups also need enough hospitals.
  check <- function(scope, target, name, members, level = NA_character_,
                    value = NA_real_, outcome = NA_character_) {
    count <- as.double(sum(members))
    hospitals <- as.double(length(unique(hospital[members])))
    groups[[length(groups) + 1L]] <<- data.frame(scope = scope, target = target,
      check = name, level = level, value = value, outcome = outcome, count = count,
      hospitals = hospitals, count_failed = disclosive(count),
      hospitals_failed = count > 0 && hospitals < min_hospitals, stringsAsFactors = FALSE)
  }
  # With a binary response, each group also checks its event and nonevent cells.
  check_cells <- function(scope, target, name, members, level = NA_character_, value = NA_real_) {
    check(scope, target, name, members, level, value)
    if (binary) {
      check(scope, target, paste0(name, "_events"), members & event, level, value, "event")
      check(scope, target, paste0(name, "_nonevents"), members & !event, level, value, "nonevent")
    }
  }
  check("model", NA_character_, "included", rep(TRUE, nrow(x)))
  if (binary) {
    check("model", NA_character_, "events", event, outcome = "event")
    check("model", NA_character_, "nonevents", !event, outcome = "nonevent")
  }
  terms <- colnames(x)
  constant <- logical(length(terms))
  for (j in seq_along(terms)) {
    column <- x[, j]
    values <- sort(unique(column))
    constant[[j]] <- length(values) == 1L
    if (length(values) == 2L) {
      check_cells("column", terms[[j]], "lower_level", column == values[[1L]], value = values[[1L]])
      check_cells("column", terms[[j]], "upper_level", column == values[[2L]], value = values[[2L]])
    } else if (length(values) > 2L) {
      check("column", terms[[j]], "nonzero", column != 0)
      if (any(column == 0)) check("column", terms[[j]], "zero_valued", column == 0, value = 0)
    }
  }
  for (variable in names(fit$levels)) {
    observed <- as.character(fit$frame[[variable]])
    for (level in fit$levels[[variable]]) {
      check_cells("factor", variable, "level", observed == level, level = level)
    }
  }
  groups <- do.call(rbind, groups)
  rownames(groups) <- NULL
  failures <- function(scope, target = NA_character_) {
    selected <- groups$scope == scope & groups$target %in% target
    c(groups$check[selected & groups$count_failed],
      paste0("hospitals_", groups$check[selected & groups$hospitals_failed], recycle0 = TRUE))
  }
  model_failed <- failures("model")
  failed_columns <- terms[vapply(terms, function(term) length(failures("column", term)) > 0L,
    logical(1), USE.NAMES = FALSE)]
  failed_factors <- names(fit$levels)[vapply(names(fit$levels), function(variable) {
    length(failures("factor", variable)) > 0L
  }, logical(1), USE.NAMES = FALSE)]
  # A failed factor also protects the lower-order terms of every term containing
  # it: the intercept, and main effects that an interaction makes level-specific.
  factor_columns <- lapply(failed_factors, function(variable) {
    containing <- Filter(function(v) variable %in% v, fit$term_variables)
    vapply(fit$column_variables, function(v) {
      any(vapply(containing, function(s) all(v %in% s), logical(1)))
    }, logical(1))
  })
  # Reasons belong to fitted columns, so rows repeating a term share one identity.
  # Constant columns describe the reference groups of every other column.
  column_reasons <- lapply(seq_along(terms), function(j) {
    c(paste0("model:", model_failed, recycle0 = TRUE),
      if (!constant[[j]]) paste0("column:", failures("column", terms[[j]]), recycle0 = TRUE),
      if (constant[[j]]) paste0("reference:", failed_columns, recycle0 = TRUE),
      paste0("factor:", failed_factors[vapply(factor_columns, function(x) x[[j]], logical(1))],
        recycle0 = TRUE))
  })
  data <- table$data
  at <- match(data$term, terms)
  reasons <- column_reasons[at]
  status <- ifelse(lengths(reasons) > 0L, "suppressed", "shown")
  shown <- status == "shown"
  hide <- function(value) {
    value[!shown] <- NA
    value
  }
  included <- as.double(nrow(x))
  presentation <- data.frame(id = data$id, term = data$term, label = data$label,
    unit = data$unit, estimate = hide(data$estimate), se = hide(data$se),
    statistic = hide(data$statistic), p_value = hide(data$p_value),
    lower = hide(data$lower), upper = hide(data$upper), aliased = hide(data$aliased),
    coefficient_scale = data$coefficient_scale, family = data$family, link = data$link,
    df = data$df, confidence = data$confidence,
    unweighted_n = rep(if (length(model_failed)) NA_real_ else included, nrow(data)),
    disclosure_status = status, stringsAsFactors = FALSE)
  audit <- list(
    sample = data.frame(supplied = as.double(table$sample$supplied), included = included,
      missing = as.double(table$sample$excluded_missing),
      hospitals = as.double(length(unique(hospital))), binary_response = binary),
    groups = groups,
    rows = data.frame(id = data$id, term = data$term,
      reasons = vapply(reasons, paste, character(1), collapse = ";"),
      disclosure_status = status, stringsAsFactors = FALSE))
  provenance <- list(policy = list(suppress = suppress, zero = zero,
      min_hospitals = min_hospitals, margins = list()),
    rule_source = "caller policy; docs/DISCLOSURE.md records the HCUP Nationwide DUA 1-10 guidance",
    count_basis = "unweighted included model analysis discharges",
    table_kind = "regression",
    procedure = "model sample, fitted model-matrix columns and factor levels; failed columns suppress constant columns and failed factors their marginal terms; no margins",
    table = table$provenance, scope = "experimental_disclosure_review",
    analysis_ready = FALSE)
  structure(list(presentation = presentation, audit = audit, table = table,
    provenance = provenance), class = "nis_disclosure_review")
}

# Verifies an unchanged regression table against its retained fit and returns
# the fitted analysis rows that underlie its coefficients.
regression_review_fit <- function(table) {
  refuse <- function() {
    stop("`table` must be an unchanged nis_regression_table result.", call. = FALSE)
  }
  if (!identical(class(table), "nis_regression_table") || !is.list(table) ||
      !identical(names(table), c("data", "model", "factors", "sample", "diagnostics", "provenance")) ||
      !is.list(table$provenance)) refuse()
  rebuilt <- tryCatch(nis_regression_table(table$model, table$provenance$declarations, "link"),
    error = function(e) NULL)
  if (is.null(rebuilt) || !identical(rebuilt, table)) refuse()
  model <- table$model
  native <- model$native
  estimates <- stats::coef(native, na.rm = FALSE)
  x <- tryCatch(stats::model.matrix(native), error = function(e) NULL)
  frame <- native$model
  hospital <- as.character(model$design$cluster[[1L]])
  if (is.null(x) || !is.data.frame(frame) || !identical(colnames(x), names(estimates)) ||
      !identical(model$coefficients$term, names(estimates)) ||
      !identical(model$coefficients$estimate, unname(estimates)) ||
      nrow(x) != length(hospital) || nrow(frame) != nrow(x) ||
      nrow(x) != model$sample$included || length(attr(x, "assign")) != ncol(x)) refuse()
  response <- stats::model.response(frame)
  if (!is.null(dim(response)) || length(response) != nrow(x) || anyNA(response)) refuse()
  predictors <- setdiff(names(frame)[-1L], c("(weights)", "(offset)"))
  categorical <- predictors[vapply(frame[predictors], function(v) {
    is.factor(v) || is.character(v) || is.logical(v)
  }, logical(1))]
  # Logical predictors are fitted with both levels, even when one has no rows.
  levels <- lapply(frame[categorical], function(v) {
    if (is.logical(v)) c("FALSE", "TRUE") else levels(factor(v))
  })
  if (!identical(as.character(names(model$factors)), categorical) ||
      !identical(unname(levels), unname(lapply(model$factors, function(f) f$levels)))) refuse()
  incidence <- attr(attr(frame, "terms"), "factors")
  term_variables <- if (length(incidence)) lapply(seq_len(ncol(incidence)), function(j) {
    rownames(incidence)[incidence[, j] > 0]
  }) else list()
  column_variables <- lapply(attr(x, "assign"), function(j) {
    if (j == 0L) character() else term_variables[[j]]
  })
  list(matrix = x, frame = frame, response = response, hospital = hospital,
    levels = levels, term_variables = term_variables, column_variables = column_variables)
}
