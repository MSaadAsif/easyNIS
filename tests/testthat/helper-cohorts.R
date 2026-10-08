invented_code_set <- function(codes = "A001", system = "ICD10CM", ...) {
  nis_code_set(codes, system = system, valid_years = 2017:2022,
               version = "invented-1", source = "invented tests", author = "example", ...)
}

collect_by_key <- function(data, columns) {
  result <- nis_collect(data, unique(c(columns, "KEY_NIS")))
  result <- result[order(as.character(result$KEY_NIS)), , drop = FALSE]
  rownames(result) <- NULL
  result
}
