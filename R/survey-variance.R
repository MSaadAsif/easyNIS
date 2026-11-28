.nis_hospital_fields <- c("YEAR", "HOSP_NIS")
.nis_stratum_fields <- c("YEAR", "NIS_STRATUM")
.nis_survey_keys <- union(.nis_stratum_fields, .nis_hospital_fields)
.nis_survey_nested_separator <- "."

nis_survey_ids <- function(records) {
  list(
    psu = paste(records$YEAR, records$HOSP_NIS, sep = "::"),
    stratum = paste(records$YEAR, records$NIS_STRATUM, sep = "::")
  )
}

nis_survey_nested_ids <- function(ids) {
  paste(ids$stratum, ids$psu, sep = .nis_survey_nested_separator)
}

nis_survey_roster_sizes <- function(roster) {
  roster$stratum <- vctrs::vec_group_id(roster[.nis_stratum_fields])
  roster$n_psu <- tabulate(roster$stratum)[roster$stratum]
  roster
}

nis_survey_variance <- function(scores, psu, roster, lonely.psu = getOption("survey.lonely.psu", "fail")) {
  strata <- roster$stratum[psu]
  survey::svyrecvar(
    scores,
    matrix(psu),
    matrix(strata),
    list(sampsize = matrix(roster$n_psu[psu]), popsize = NULL),
    lonely.psu = lonely.psu
  )
}
