reduce_or <- function(terms) {
  Reduce(function(left, right) rlang::expr((!!left) | (!!right)), terms)
}

nis_and_expr <- function(left, right) {
  rlang::expr(dplyr::if_else(!!left, !!right, FALSE))
}

nis_is_nonnegative_integer <- function(threshold) {
  if (!identical(length(threshold), 1L) || !is.numeric(threshold)) return(FALSE)
  !is.na(threshold) && is.finite(threshold) && threshold >= 0 &&
    threshold <= .Machine$integer.max && threshold == as.integer(threshold)
}
