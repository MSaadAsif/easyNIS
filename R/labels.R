# HCUP NIS Description of Data Elements, Appendix III (2020), cross-checked
# against the analyst's local recoding helper. Code sets are intentionally small
# and do not infer labels for unknown values.
.hcup_labels <- dplyr::tribble(
  ~variable               , ~code    , ~value_label                                              , ~variable_label                                           ,
  "AWEEKEND"              ,        0 , "Monday-Friday"                                           , "Admission day"                                           ,
  "AWEEKEND"              ,        1 , "Saturday-Sunday"                                         , "Admission day"                                           ,
  "AMONTH"                ,        1 , "January"                                                 , "Admission month"                                         ,
  "AMONTH"                ,        2 , "February"                                                , "Admission month"                                         ,
  "AMONTH"                ,        3 , "March"                                                   , "Admission month"                                         ,
  "AMONTH"                ,        4 , "April"                                                   , "Admission month"                                         ,
  "AMONTH"                ,        5 , "May"                                                     , "Admission month"                                         ,
  "AMONTH"                ,        6 , "June"                                                    , "Admission month"                                         ,
  "AMONTH"                ,        7 , "July"                                                    , "Admission month"                                         ,
  "AMONTH"                ,        8 , "August"                                                  , "Admission month"                                         ,
  "AMONTH"                ,        9 , "September"                                               , "Admission month"                                         ,
  "AMONTH"                ,       10 , "October"                                                 , "Admission month"                                         ,
  "AMONTH"                ,       11 , "November"                                                , "Admission month"                                         ,
  "AMONTH"                ,       12 , "December"                                                , "Admission month"                                         ,
  "TRAN_IN"               ,        0 , "No transfer"                                             , "Transfer into hospital"                                  ,
  "TRAN_IN"               ,        1 , "Transferred from acute-care hospital"                    , "Transfer into hospital"                                  ,
  "TRAN_IN"               ,        2 , "Transferred from another type of facility"               , "Transfer into hospital"                                  ,
  "TRAN_OUT"              ,        0 , "No transfer"                                             , "Transfer out of hospital"                                ,
  "TRAN_OUT"              ,        1 , "Transferred to acute-care hospital"                      , "Transfer out of hospital"                                ,
  "TRAN_OUT"              ,        2 , "Transferred to another type of facility"                 , "Transfer out of hospital"                                ,
  "DISPUNIFORM"           ,        1 , "Routine discharge to home/self-care"                     , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,        2 , "Transfer to another short-term hospital"                 , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,        5 , "Transfer to SNF, intermediate care, or another facility" , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,        6 , "Home health care"                                        , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,        7 , "Left against medical advice"                             , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,       20 , "Died in hospital"                                        , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,       21 , "Discharged/transferred to court/law enforcement"         , "Disposition of patient"                                  ,
  "DISPUNIFORM"           ,       99 , "Alive, destination unknown"                              , "Disposition of patient"                                  ,
  "HCUP_ED"               ,        0 , "No qualifying ED evidence"                               , "Emergency department indicator"                          ,
  "HCUP_ED"               ,        1 , "ED revenue code"                                         , "Emergency department indicator"                          ,
  "HCUP_ED"               ,        2 , "ED charge"                                               , "Emergency department indicator"                          ,
  "HCUP_ED"               ,        3 , "ED procedure code"                                       , "Emergency department indicator"                          ,
  "HCUP_ED"               ,        4 , "Admission source indicates ED"                           , "Emergency department indicator"                          ,
  "HCUP_ED"               ,        5 , "State-defined ED record"                                 , "Emergency department indicator"                          ,
  "ELECTIVE"              ,        0 , "Non-elective"                                            , "Elective admission indicator"                            ,
  "ELECTIVE"              ,        1 , "Elective"                                                , "Elective admission indicator"                            ,
  "AGE_NEONATE"           ,        0 , "Non-neonatal age"                                        , "Neonatal age indicator"                                  ,
  "AGE_NEONATE"           ,        1 , "Neonatal age"                                            , "Neonatal age indicator"                                  ,
  "FEMALE"                ,        0 , "Male"                                                    , "Sex of patient"                                          ,
  "FEMALE"                ,        1 , "Female"                                                  , "Sex of patient"                                          ,
  "RACE"                  ,        1 , "White"                                                   , "Race, uniform coding"                                    ,
  "RACE"                  ,        2 , "Black"                                                   , "Race, uniform coding"                                    ,
  "RACE"                  ,        3 , "Hispanic"                                                , "Race, uniform coding"                                    ,
  "RACE"                  ,        4 , "Asian or Pacific Islander"                               , "Race, uniform coding"                                    ,
  "RACE"                  ,        5 , "Native American"                                         , "Race, uniform coding"                                    ,
  "RACE"                  ,        6 , "Other"                                                   , "Race, uniform coding"                                    ,
  "PL_NCHS"               ,        1 , "Central metro, population 1 million or more"             , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS"               ,        2 , "Fringe metro, population 1 million or more"              , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS"               ,        3 , "Metro, population 250,000-999,999"                       , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS"               ,        4 , "Metro, population 50,000-249,999"                        , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS"               ,        5 , "Micropolitan"                                            , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS"               ,        6 , "Nonmetropolitan, nonmicropolitan"                        , "Patient location, NCHS urban-rural code"                 ,
  "PL_NCHS2006"           ,        1 , "Central metro, population 1 million or more"             , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2006"           ,        2 , "Fringe metro, population 1 million or more"              , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2006"           ,        3 , "Metro, population 250,000-999,999"                       , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2006"           ,        4 , "Metro, population 50,000-249,999"                        , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2006"           ,        5 , "Micropolitan"                                            , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2006"           ,        6 , "Nonmetropolitan, nonmicropolitan"                        , "Patient location, 2006 NCHS urban-rural code"            ,
  "PL_NCHS2"              ,       21 , "Metropolitan"                                            , "Patient location, collapsed NCHS urban-rural code"       ,
  "PL_NCHS2"              ,       22 , "Nonmetropolitan"                                         , "Patient location, collapsed NCHS urban-rural code"       ,
  "ZIPINC_QRTL"           ,        1 , "Q1"                                                      , "Median household income national quartile (patient ZIP)" ,
  "ZIPINC_QRTL"           ,        2 , "Q2"                                                      , "Median household income national quartile (patient ZIP)" ,
  "ZIPINC_QRTL"           ,        3 , "Q3"                                                      , "Median household income national quartile (patient ZIP)" ,
  "ZIPINC_QRTL"           ,        4 , "Q4"                                                      , "Median household income national quartile (patient ZIP)" ,
  "PAY1"                  ,        1 , "Medicare"                                                , "Expected primary payer"                                  ,
  "PAY1"                  ,        2 , "Medicaid"                                                , "Expected primary payer"                                  ,
  "PAY1"                  ,        3 , "Private including HMO"                                   , "Expected primary payer"                                  ,
  "PAY1"                  ,        4 , "Self-pay"                                                , "Expected primary payer"                                  ,
  "PAY1"                  ,        5 , "No charge"                                               , "Expected primary payer"                                  ,
  "PAY1"                  ,        6 , "Other"                                                   , "Expected primary payer"                                  ,
  "DQTR"                  ,        1 , "Q1"                                                      , "Discharge quarter"                                       ,
  "DQTR"                  ,        2 , "Q2"                                                      , "Discharge quarter"                                       ,
  "DQTR"                  ,        3 , "Q3"                                                      , "Discharge quarter"                                       ,
  "DQTR"                  ,        4 , "Q4"                                                      , "Discharge quarter"                                       ,
  "DIED"                  ,        0 , "No"                                                      , "Died during hospitalization"                             ,
  "DIED"                  ,        1 , "Yes"                                                     , "Died during hospitalization"                             ,
  "HOSP_DIVISION"         ,        1 , "New England"                                             , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        2 , "Middle Atlantic"                                         , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        3 , "East North Central"                                      , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        4 , "West North Central"                                      , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        5 , "South Atlantic"                                          , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        6 , "East South Central"                                      , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        7 , "West South Central"                                      , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        8 , "Mountain"                                                , "Hospital Census division"                                ,
  "HOSP_DIVISION"         ,        9 , "Pacific"                                                 , "Hospital Census division"                                ,
  "HOSP_REGION"           ,        1 , "Northeast"                                               , "Hospital Census region"                                  ,
  "HOSP_REGION"           ,        2 , "Midwest"                                                 , "Hospital Census region"                                  ,
  "HOSP_REGION"           ,        3 , "South"                                                   , "Hospital Census region"                                  ,
  "HOSP_REGION"           ,        4 , "West"                                                    , "Hospital Census region"                                  ,
  "HOSP_BEDSIZE"          ,        1 , "Small"                                                   , "Hospital bed size"                                       ,
  "HOSP_BEDSIZE"          ,        2 , "Medium"                                                  , "Hospital bed size"                                       ,
  "HOSP_BEDSIZE"          ,        3 , "Large"                                                   , "Hospital bed size"                                       ,
  "H_CONTRL"              ,        1 , "Government, non-federal"                                 , "Hospital control/ownership"                              ,
  "H_CONTRL"              ,        2 , "Private, non-profit"                                     , "Hospital control/ownership"                              ,
  "H_CONTRL"              ,        3 , "Private, investor-owned"                                 , "Hospital control/ownership"                              ,
  "HOSP_LOCTEACH"         ,        1 , "Rural"                                                   , "Hospital location and teaching status"                   ,
  "HOSP_LOCTEACH"         ,        2 , "Urban, non-teaching"                                     , "Hospital location and teaching status"                   ,
  "HOSP_LOCTEACH"         ,        3 , "Urban, teaching"                                         , "Hospital location and teaching status"                   ,
  "APRDRG_RISK_MORTALITY" ,        0 , "No class specified"                                      , "APR-DRG risk of mortality"                               ,
  "APRDRG_RISK_MORTALITY" ,        1 , "Minor"                                                   , "APR-DRG risk of mortality"                               ,
  "APRDRG_RISK_MORTALITY" ,        2 , "Moderate"                                                , "APR-DRG risk of mortality"                               ,
  "APRDRG_RISK_MORTALITY" ,        3 , "Major"                                                   , "APR-DRG risk of mortality"                               ,
  "APRDRG_RISK_MORTALITY" ,        4 , "Extreme"                                                 , "APR-DRG risk of mortality"                               ,
  "APRDRG_SEVERITY"       ,        0 , "No class specified"                                      , "APR-DRG severity of illness"                             ,
  "APRDRG_SEVERITY"       ,        1 , "Minor"                                                   , "APR-DRG severity of illness"                             ,
  "APRDRG_SEVERITY"       ,        2 , "Moderate"                                                , "APR-DRG severity of illness"                             ,
  "APRDRG_SEVERITY"       ,        3 , "Major"                                                   , "APR-DRG severity of illness"                             ,
  "APRDRG_SEVERITY"       ,        4 , "Extreme"                                                 , "APR-DRG severity of illness"                             ,
  "I10_BIRTH"             ,        0 , "No birth diagnosis"                                      , "ICD-10-CM birth indicator"                               ,
  "I10_BIRTH"             ,        1 , "Born in hospital"                                        , "ICD-10-CM birth indicator"                               ,
  "I10_BIRTH"             ,        2 , "Born outside hospital"                                   , "ICD-10-CM birth indicator"                               ,
  "I10_BIRTH"             ,        3 , "Place of birth unspecified"                              , "ICD-10-CM birth indicator"                               ,
  "I10_DELIVERY"          ,        0 , "No"                                                      , "ICD-10-CM delivery indicator"                            ,
  "I10_DELIVERY"          ,        1 , "Yes"                                                     , "ICD-10-CM delivery indicator"                            ,
  "I10_INJURY"            ,        0 , "No injury"                                               , "Injury ICD-10-CM diagnosis indicator"                    ,
  "I10_INJURY"            ,        1 , "Injury, first-listed"                                    , "Injury ICD-10-CM diagnosis indicator"                    ,
  "I10_INJURY"            ,        2 , "Injury, other than first-listed"                         , "Injury ICD-10-CM diagnosis indicator"                    ,
  "I10_MULTINJURY"        ,        0 , "No"                                                      , "Multiple injury indicator"                               ,
  "I10_MULTINJURY"        ,        1 , "Yes"                                                     , "Multiple injury indicator"                               ,
  "I10_SERVICELINE"       ,        1 , "Maternal and neonatal"                                   , "ICD-10-CM/PCS service line indicator"                    ,
  "I10_SERVICELINE"       ,        2 , "Mental health or substance use"                          , "ICD-10-CM/PCS service line indicator"                    ,
  "I10_SERVICELINE"       ,        3 , "Injury"                                                  , "ICD-10-CM/PCS service line indicator"                    ,
  "I10_SERVICELINE"       ,        4 , "Surgical"                                                , "ICD-10-CM/PCS service line indicator"                    ,
  "I10_SERVICELINE"       ,        5 , "Medical"                                                 , "ICD-10-CM/PCS service line indicator"                    ,
  "PCLASS_ORPROC"         ,        0 , "No"                                                      , "ICD-10-PCS major operating room procedure indicator"     ,
  "PCLASS_ORPROC"         ,        1 , "Yes"                                                     , "ICD-10-PCS major operating room procedure indicator"     ,
  "AGE"                   , NA_real_ , NA_character_                                             , "Age, years"                                              ,
  "LOS"                   , NA_real_ , NA_character_                                             , "Length of stay, days"                                    ,
  "TOTCHG"                , NA_real_ , NA_character_                                             , "Total charges, USD"                                      ,
  "CCR_NIS"               , NA_real_ , NA_character_                                             , "Cost-to-charge ratio"                                    ,
  "YEAR"                  , NA_real_ , NA_character_                                             , "Discharge year"                                          ,
  "DISCWT"                , NA_real_ , NA_character_                                             , "Discharge weight"                                        ,
  "HOSP_NIS"              , NA_real_ , NA_character_                                             , "NIS hospital identifier"                                 ,
  "NIS_STRATUM"           , NA_real_ , NA_character_                                             , "NIS stratum"                                             ,
  "elixsum"               , NA_real_ , NA_character_                                             , "Elixhauser comorbidity score"                            ,
  "charlindex"            , NA_real_ , NA_character_                                             , "Charlson comorbidity index"                              ,
  "ELIXSUM"               , NA_real_ , NA_character_                                             , "Elixhauser comorbidity score"                            ,
  "CHARLINDEX"            , NA_real_ , NA_character_                                             , "Charlson comorbidity index"                              ,
  "GRPCI"                 ,        0 , "No comorbidities"                                        , "Number of comorbidities"                                 ,
  "GRPCI"                 ,        1 , "One comorbidity"                                         , "Number of comorbidities"                                 ,
  "GRPCI"                 ,        2 , "Two or more comorbidities"                               , "Number of comorbidities"
)
attr(.hcup_labels, "source") <- paste(
  "HCUP NIS Introductions (2012, 2020, and 2023),",
  "and HCUP NIS data element notes for I10_BIRTH and I10_SERVICELINE."
)

#' Apply HCUP labels
#'
#' @param .data A collected data frame.
#'
#' @return `.data` with binary indicators as logical, multi-level coded
#'   elements as factors, and variable labels in `attr(x, "label")`.
#'   Unknown codes trigger one warning per variable. They become `NA` in
#'   binary fields and `Code <value>` levels in multi-level fields. Existing
#'   variable labels are preserved. Numeric fields without a table entry
#'   are returned unchanged. The operation is idempotent.
#'
#' Residence fields `PL_NCHS2006`, `PL_NCHS`, and `PL_NCHS2` retain their own
#' categories. The collapsed `PL_NCHS2` uses codes 21 and 22. Code-specific
#' labels for `I10_BIRTH` and `I10_SERVICELINE` follow HCUP's definitions.
#'
#' Binary codes 0 and 1 become `FALSE` and `TRUE`, respectively. For example,
#' `FEMALE` is true for female patients and `AWEEKEND` for weekend admissions.
#'
#' Negative numeric sentinels are handled as unknown codes. The supplied
#' HCUP documentation represents missing numeric values as system missing and
#' does not document negative sentinels for any element handled here.
#' `NaN` values in ordinary numeric vectors and Haven-labelled numeric storage
#' are treated as missing, while ordinary and tagged `NA` values remain
#' missing. Finite SPSS user-missing values and `integer64` values are
#' interpreted through their displayed values.
#' Factors containing raw codes are normalized as a whole. Existing labels,
#' including `Code 7`, are preserved when unused raw-code levels remain after
#' subsetting. A bare `Code ` value with raw-code levels and no recognized value
#' label is treated as raw text; without such levels it is preserved as an
#' existing label because its origin cannot be recovered after dropping levels.
#' @family data-access
#' @seealso [Opening NIS data](articles/opening-data.html),
#'   [HCUP NIS Description of Data Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).
#' @export
#' @examples
#' demographics <- nis_open(nis_example(years = 2019)) |>
#'   dplyr::select(AGE, FEMALE, RACE) |>
#'   dplyr::collect()
#' head(nis_label(demographics))
nis_label <- function(.data) {
  if (!is.data.frame(.data)) {
    cli::cli_abort(c(
      "`.data` must be a collected data frame.",
      i = "For a lazy query, select the columns you need and use `dplyr::collect()`, or let `nis_design()` label the analysis data."
    ))
  }
  for (variable in nis_names(.data)) {
    if (startsWith(variable, ".")) {
      next
    }
    .data[[variable]] <- label_one(.data[[variable]], variable)
  }
  .data
}

label_one <- function(x, variable) {
  old_label <- attr(x, "label", exact = TRUE)
  field <- if (variable == "discharge_disposition") "DISPUNIFORM" else variable
  definition <- .hcup_labels[.hcup_labels$variable == field, , drop = FALSE]
  value_rows <- !is.na(definition$code)
  binary_comorbidity <- grepl("^(ynel|ynch)[0-9]+$", variable)
  codes <- definition$code[value_rows]
  values <- definition$value_label[value_rows]
  if (binary_comorbidity || setequal(codes, 0:1)) {
    if (!is.logical(x)) {
      binary_labels <- if (binary_comorbidity) c("No", "Yes") else values[match(0:1, codes)]
      x <- label_binary(x, binary_labels, variable, rlang::caller_call())
    }
  } else if (length(codes)) {
    raw <- label_displayed_codes(x)
    codes <- as.character(codes)
    if (!labelled_factor(x, raw, codes, values)) {
      x <- label_raw_codes(raw, codes, values, variable, rlang::caller_call())
    }
  }
  variable_label <- if (nrow(definition) > 0L) {
    definition$variable_label[[1L]]
  } else {
    NULL
  }
  if (!is.null(old_label)) {
    attr(x, "label") <- old_label
  } else if (!is.null(variable_label)) {
    attr(x, "label") <- variable_label
  }
  x
}

label_binary <- function(x, values, variable, call) {
  if (is.numeric(x) && !is.object(x)) {
    raw <- x
    index <- match(raw, 0:1)
  } else {
    raw <- label_displayed_codes(x)
    codes <- if (is.factor(x)) c("0", "1", values) else c("0", "1")
    index <- match(raw, codes)
  }
  unknown <- !is.na(raw) & is.na(index)
  if (any(unknown)) {
    cli::cli_warn(
      "Unknown code(s) in {.var {variable}}: {paste(unique(raw[unknown]), collapse = ', ')}. Converted to missing.",
      call = call
    )
  }
  c(FALSE, TRUE, FALSE, TRUE)[index]
}

label_displayed_codes <- function(x) {
  raw <- as.character(x)
  plain_numeric <- is.double(x) && !is.object(x)
  haven_numeric <- inherits(x, "haven_labelled") &&
    typeof(unclass(x)) == "double" &&
    !inherits(x, "integer64")
  if (plain_numeric || haven_numeric) {
    raw[is.nan(unclass(x))] <- NA_character_
  }
  raw
}

labelled_factor <- function(x, raw, codes, values) {
  if (!is.factor(x)) {
    return(FALSE)
  }
  already_labelled <- !is.na(raw) &
    (raw %in% values | startsWith(raw, "Code "))
  raw_code_levels <- any(levels(x) %in% codes)
  observed_value_labels <- any(!is.na(raw) & raw %in% values)
  ambiguous_bare_code <- any(!is.na(raw) & raw == "Code ")
  all(is.na(raw) | already_labelled) &&
    (!raw_code_levels || observed_value_labels || !ambiguous_bare_code)
}

label_raw_codes <- function(raw, codes, values, variable, call) {
  unknown <- !is.na(raw) & !raw %in% codes
  unknown_labels <- if (any(unknown)) {
    unique(paste0("Code ", raw[unknown]))
  } else {
    character()
  }
  if (any(unknown)) {
    cli::cli_warn(
      paste0(
        "Unknown code(s) in {.var {variable}}: ",
        "{paste(unique(raw[unknown]), collapse = ', ')}. Retained as their own factor levels."
      ),
      call = call
    )
  }
  labels <- ifelse(is.na(raw), NA_character_, ifelse(raw %in% codes, values[match(raw, codes)], paste0("Code ", raw)))
  factor(labels, levels = c(values, unique(unknown_labels)))
}
