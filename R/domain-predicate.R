# Evaluate a bounded predicate using retained columns and fixed base operators.
# No expression is evaluated in the formula's environment or parsed from text.
domain_predicate <- function(formula, rows) {
  literal <- function(node) {
    if (is.call(node) && identical(node[[1L]], as.name("-")) && length(node) == 2L) {
      return(is.numeric(node[[2L]]) && !is.object(node[[2L]]) && length(node[[2L]]) == 1L &&
        !is.na(node[[2L]]) && is.finite(node[[2L]]))
    }
    is.atomic(node) && !is.object(node) && is.null(dim(node)) && length(node) == 1L &&
      typeof(node) %in% c("logical", "integer", "double", "character") &&
      (!is.numeric(node) || is.na(node) || is.finite(node))
  }
  constants <- function(node) {
    literal(node) || (is.call(node) && identical(node[[1L]], as.name("c")) &&
      length(node) > 1L && is.null(names(as.list(node)[-1L])) &&
      all(vapply(as.list(node)[-1L], literal, logical(1))))
  }
  supported <- function(node) {
    if (is.symbol(node) || literal(node)) return(TRUE)
    if (!is.call(node) || !is.symbol(node[[1L]])) return(FALSE)
    args <- as.list(node)[-1L]
    if (!is.null(names(args))) return(FALSE)
    operator <- as.character(node[[1L]])
    if (operator == "%in%") {
      return(length(args) == 2L && supported(args[[1L]]) && constants(args[[2L]]))
    }
    arity <- if (operator %in% c("!", "(", "is.na")) 1L else
      if (operator %in% c("&", "|", "==", "!=", "<", "<=", ">", ">=")) 2L else 0L
    arity > 0L && length(args) == arity && all(vapply(args, supported, logical(1)))
  }
  if (length(formula) != 2L || !supported(formula[[2L]])) {
    stop("Domain predicates require a one-sided formula with supported comparisons and logical operators.",
         call. = FALSE)
  }
  fields <- all.vars(formula[[2L]])
  if (!length(fields) || any(!fields %in% names(rows))) {
    stop("Every domain predicate field must be retained; global variables are unsupported.", call. = FALSE)
  }
  for (field in fields) {
    x <- rows[[field]]
    factor <- identical(class(x), "factor") || identical(class(x), c("ordered", "factor"))
    if (!is.null(dim(x)) || (!factor && (is.object(x) || is.complex(x) ||
        (!is.numeric(x) && !is.logical(x) && !is.character(x)))) ||
        (is.numeric(x) && any(!is.na(x) & !is.finite(x)))) {
      stop("Domain predicate fields must be plain finite numeric, logical, character or standard factor vectors.",
           call. = FALSE)
    }
  }
  evaluate <- function(node) {
    if (is.symbol(node)) return(rows[[as.character(node)]])
    if (!is.call(node)) return(node)
    operator <- as.character(node[[1L]])
    values <- lapply(as.list(node)[-1L], evaluate)
    if (operator %in% c("&", "|", "!") &&
        any(!vapply(values, is.logical, logical(1)))) {
      stop("Logical domain operators require logical flags or comparisons; numeric coding is not inferred.",
           call. = FALSE)
    }
    do.call(get(operator, envir = baseenv(), inherits = FALSE), values)
  }
  indicator <- withCallingHandlers(evaluate(formula[[2L]]), warning = function(warning) {
    stop("Domain predicate evaluation warned: ", conditionMessage(warning), call. = FALSE)
  })
  if (!is.logical(indicator) || is.object(indicator) || !is.null(dim(indicator)) ||
      length(indicator) != nrow(rows)) {
    stop("Domain predicates must return one plain logical value per supplied discharge.", call. = FALSE)
  }
  list(indicator = indicator, fields = fields,
       expression = paste(deparse(formula[[2L]], width.cutoff = 500L), collapse = " "))
}
