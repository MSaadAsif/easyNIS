source("tools/layout-metadata.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2L) {
  stop("Usage: Rscript tools/update-component-metadata.R [cache-directory [output-csv]]")
}
cache <- if (length(args)) args[1L] else "docs/references/local/annual-documents"
output <- if (length(args) == 2L) args[2L] else "inst/metadata/component-layouts.csv"
update_component_metadata(cache, output)
cat("Updated provisional component facts from cached sources only. No support status changed.\n")
