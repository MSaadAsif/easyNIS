args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !file.exists(args)) {
  stop("Usage: Rscript tools/check-tarball.R <source.tar.gz>")
}
entries <- utils::untar(args, list = TRUE)
if (!length(entries) || any(!startsWith(entries, "easyNIS/"))) {
  stop("Tarball must contain only the easyNIS package root.")
}
paths <- sub("^easyNIS/", "", entries)
vignette_index <- paths == "build/vignette.rds"
forbidden <- grepl(
  "(^|/)(private|local-data|local-validation|local|docs|tools|\\.git|\\.github|\\.agents)(/|$)|(^|/)(AGENTS[.]md|[.]easynis-local[.]ps1)$|\\.\\.(/|$)|\\.(pdf|parquet|dta|sas7bdat|sav|rds|rda|rdata|duckdb|log)$",
  paths, ignore.case = TRUE
)
forbidden <- forbidden & !vignette_index
if (any(forbidden)) {
  stop("Forbidden tarball entries: ", paste(paths[forbidden], collapse = ", "))
}
required <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R/years.R", "R/synthetic.R",
              "man/nis_supported_years.Rd", "man/nis_synthetic_data.Rd",
              "inst/metadata/year-support.csv", "inst/CITATION")
missing <- setdiff(required, paths)
if (length(missing)) stop("Missing tarball entries: ", paste(missing, collapse = ", "))
if (any(vignette_index)) {
  temporary <- tempfile("easynis-vignette-index-")
  dir.create(temporary)
  tryCatch({
    utils::untar(args, files = "easyNIS/build/vignette.rds", exdir = temporary)
    index <- readRDS(file.path(temporary, "easyNIS/build/vignette.rds"))
    expected <- data.frame(File = "synthetic-workflow.Rhtml",
      Title = "Offline synthetic import-to-export workflow",
      PDF = "synthetic-workflow.html", R = "synthetic-workflow.R",
      stringsAsFactors = FALSE)
    expected$Depends <- list(Depends = character())
    expected$Keywords <- list(Keywords = character())
    if (!identical(index, expected)) stop("Unexpected vignette index metadata.")
  }, finally = unlink(temporary, recursive = TRUE))
}
vignette_files <- c("vignettes/synthetic-workflow.Rhtml",
  "inst/doc/synthetic-workflow.Rhtml", "inst/doc/synthetic-workflow.R",
  "inst/doc/synthetic-workflow.html", "build/vignette.rds")
missing_vignette <- setdiff(vignette_files, paths)
if (length(missing_vignette)) {
  stop("Missing vignette entries: ", paste(missing_vignette, collapse = ", "))
}
cat("Tarball inspection passed for", length(entries), "entries.\n")
