probe_diagnosis_fields <- function(query) {
  grep("^(?:I10_DX|DXPOA)[0-9]+$", colnames(query), value = TRUE, perl = TRUE)
}
