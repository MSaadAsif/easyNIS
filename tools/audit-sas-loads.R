source("tools/layout-metadata.R")
source("tools/sas-load-metadata.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2L) {
  stop("Usage: Rscript tools/audit-sas-loads.R [cache-directory [new-output-directory]]")
}
cache <- if (length(args)) args[1L] else "docs/references/local/annual-documents"
output <- if (length(args) == 2L) args[2L] else ".audit/sas-load-audit"
audit <- audit_sas_loads(cache, output)
cat("Audited", nrow(audit$references), "cached pairs and", nrow(audit$fields),
    "field assignments. Literal mappings remain provisional; no support status changed.\n")
