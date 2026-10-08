source("tools/layout-metadata.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) && args != "--cached-only")) {
  stop("Usage: Rscript tools/update-layout-metadata.R [--cached-only]")
}
update_layout_metadata(cached_only = length(args) == 1L)
cat("Updated provisional Core layout facts for six years. No support status changed.\n")
