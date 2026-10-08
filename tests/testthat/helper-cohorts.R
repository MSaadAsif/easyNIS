invented_code_set <- function(codes = "A001", system = "ICD10CM", ...) {
  nis_code_set(codes, system = system, valid_years = 2017:2022,
               version = "invented-1", source = "invented tests", author = "example", ...)
}
