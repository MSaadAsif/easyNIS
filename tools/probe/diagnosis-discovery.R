probe_diagnosis_fields <- function(query) {
  grep("^(?:I10_DX|DXPOA)[0-9]+$", easyNIS:::nis_names(query), value = TRUE, perl = TRUE)
}
