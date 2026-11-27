for (module in c(
  "workspace",
  "diagnostics",
  "git-evidence",
  "study-receipts",
  "quality-receipts",
  "quality-diagnostics",
  "hcup-url-proxy",
  "export-documentation"
)) {
  sys.source(file.path("tools", "probe", paste0(module, ".R")), envir = environment())
}
rm(module)
