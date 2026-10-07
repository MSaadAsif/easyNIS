args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !file.exists(args)) {
  stop("Usage: Rscript tools/check-tarball.R <source.tar.gz>")
}
entries <- utils::untar(args, list = TRUE)
if (!length(entries) || any(!startsWith(entries, "easyNIS/"))) {
  stop("Tarball must contain only the easyNIS package root.")
}
paths <- sub("^easyNIS/", "", entries)
forbidden <- grepl(
  "(^|/)(private|local-data|local-validation|local|docs|tools|\\.git|\\.github)(/|$)|\\.\\.(/|$)|\\.(pdf|parquet|dta|sas7bdat|sav|rds|rda|rdata|duckdb|log)$",
  paths, ignore.case = TRUE
)
if (any(forbidden)) {
  stop("Forbidden tarball entries: ", paste(paths[forbidden], collapse = ", "))
}
required <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R/years.R", "R/synthetic.R",
              "man/nis_supported_years.Rd", "man/nis_synthetic_data.Rd",
              "inst/metadata/year-support.csv", "inst/CITATION")
missing <- setdiff(required, paths)
if (length(missing)) stop("Missing tarball entries: ", paste(missing, collapse = ", "))
cat("Tarball inspection passed for", length(entries), "entries.\n")
