# HCUP NIS Description of Data Elements, Appendix III (2020), cross-checked
# against the analyst's local recoding helper. Code sets are intentionally small
# and do not infer labels for unknown values.
.hcup_labels <- dplyr::tribble(
  ~variable, ~code, ~value_label, ~variable_label,
  "AWEEKEND", 0, "Monday-Friday", "Admission day",
  "AWEEKEND", 1, "Saturday-Sunday", "Admission day",
  "AMONTH", 1, "January", "Admission month",
  "AMONTH", 2, "February", "Admission month",
  "AMONTH", 3, "March", "Admission month",
  "AMONTH", 4, "April", "Admission month",
  "AMONTH", 5, "May", "Admission month",
  "AMONTH", 6, "June", "Admission month",
  "AMONTH", 7, "July", "Admission month",
  "AMONTH", 8, "August", "Admission month",
  "AMONTH", 9, "September", "Admission month",
  "AMONTH", 10, "October", "Admission month",
  "AMONTH", 11, "November", "Admission month",
  "AMONTH", 12, "December", "Admission month",
  "TRAN_IN", 0, "No transfer", "Transfer into hospital",
  "TRAN_IN", 1, "Transferred from acute-care hospital", "Transfer into hospital",
  "TRAN_IN", 2, "Transferred from another type of facility", "Transfer into hospital",
  "TRAN_OUT", 0, "No transfer", "Transfer out of hospital",
  "TRAN_OUT", 1, "Transferred to acute-care hospital", "Transfer out of hospital",
  "TRAN_OUT", 2, "Transferred to another type of facility", "Transfer out of hospital",
  "DISPUNIFORM", 1, "Routine discharge to home/self-care", "Disposition of patient",
  "DISPUNIFORM", 2, "Transfer to another short-term hospital", "Disposition of patient",
  "DISPUNIFORM", 5, "Transfer to SNF, intermediate care, or another facility", "Disposition of patient",
  "DISPUNIFORM", 6, "Home health care", "Disposition of patient",
  "DISPUNIFORM", 7, "Left against medical advice", "Disposition of patient",
  "DISPUNIFORM", 20, "Died in hospital", "Disposition of patient",
  "DISPUNIFORM", 21, "Discharged to court/law enforcement", "Disposition of patient",
  "DISPUNIFORM", 99, "Alive, destination unknown", "Disposition of patient",
  "HCUP_ED", 0, "No qualifying ED evidence", "Emergency department indicator",
  "HCUP_ED", 1, "ED revenue code", "Emergency department indicator",
  "HCUP_ED", 2, "ED charge", "Emergency department indicator",
  "HCUP_ED", 3, "ED procedure code", "Emergency department indicator",
  "HCUP_ED", 4, "Admission source indicates ED", "Emergency department indicator",
  "HCUP_ED", 5, "State-defined ED record", "Emergency department indicator",
  "ELECTIVE", 0, "Non-elective", "Elective admission indicator",
  "ELECTIVE", 1, "Elective", "Elective admission indicator",
  "AGE_NEONATE", 0, "Non-neonatal age", "Neonatal age indicator",
  "AGE_NEONATE", 1, "Neonatal age", "Neonatal age indicator",
  "FEMALE", 0, "Male", "Sex of patient",
  "FEMALE", 1, "Female", "Sex of patient",
  "RACE", 1, "White", "Race, uniform coding",
  "RACE", 2, "Black", "Race, uniform coding",
  "RACE", 3, "Hispanic", "Race, uniform coding",
  "RACE", 4, "Asian or Pacific Islander", "Race, uniform coding",
  "RACE", 5, "Native American", "Race, uniform coding",
  "RACE", 6, "Other", "Race, uniform coding",
  "PL_NCHS", 1, "Central metro, population 1 million or more", "Patient location, NCHS urban-rural code",
  "PL_NCHS", 2, "Fringe metro, population 1 million or more", "Patient location, NCHS urban-rural code",
  "PL_NCHS", 3, "Metro, population 250,000-999,999", "Patient location, NCHS urban-rural code",
  "PL_NCHS", 4, "Metro, population 50,000-249,999", "Patient location, NCHS urban-rural code",
  "PL_NCHS", 5, "Micropolitan", "Patient location, NCHS urban-rural code",
  "PL_NCHS", 6, "Nonmetropolitan, nonmicropolitan", "Patient location, NCHS urban-rural code",
  "ZIPINC_QRTL", 1, "Q1", "Median household income quartile (patient ZIP)",
  "ZIPINC_QRTL", 2, "Q2", "Median household income quartile (patient ZIP)",
  "ZIPINC_QRTL", 3, "Q3", "Median household income quartile (patient ZIP)",
  "ZIPINC_QRTL", 4, "Q4", "Median household income quartile (patient ZIP)",
  "PAY1", 1, "Medicare", "Primary payer",
  "PAY1", 2, "Medicaid", "Primary payer",
  "PAY1", 3, "Private including HMO", "Primary payer",
  "PAY1", 4, "Self-pay", "Primary payer",
  "PAY1", 5, "No charge", "Primary payer",
  "PAY1", 6, "Other", "Primary payer",
  "DQTR", 1, "Q1", "Discharge quarter",
  "DQTR", 2, "Q2", "Discharge quarter",
  "DQTR", 3, "Q3", "Discharge quarter",
  "DQTR", 4, "Q4", "Discharge quarter",
  "DIED", 0, "No", "Died during hospitalization",
  "DIED", 1, "Yes", "Died during hospitalization",
  "HOSP_DIVISION", 1, "New England", "Hospital Census division",
  "HOSP_DIVISION", 2, "Middle Atlantic", "Hospital Census division",
  "HOSP_DIVISION", 3, "East North Central", "Hospital Census division",
  "HOSP_DIVISION", 4, "West North Central", "Hospital Census division",
  "HOSP_DIVISION", 5, "South Atlantic", "Hospital Census division",
  "HOSP_DIVISION", 6, "East South Central", "Hospital Census division",
  "HOSP_DIVISION", 7, "West South Central", "Hospital Census division",
  "HOSP_DIVISION", 8, "Mountain", "Hospital Census division",
  "HOSP_DIVISION", 9, "Pacific", "Hospital Census division",
  "HOSP_REGION", 1, "Northeast", "Hospital Census region",
  "HOSP_REGION", 2, "Midwest", "Hospital Census region",
  "HOSP_REGION", 3, "South", "Hospital Census region",
  "HOSP_REGION", 4, "West", "Hospital Census region",
  "HOSP_BEDSIZE", 1, "Small", "Hospital bed size",
  "HOSP_BEDSIZE", 2, "Medium", "Hospital bed size",
  "HOSP_BEDSIZE", 3, "Large", "Hospital bed size",
  "H_CONTRL", 1, "Government, non-federal", "Hospital control",
  "H_CONTRL", 2, "Private, non-profit", "Hospital control",
  "H_CONTRL", 3, "Private, investor-owned", "Hospital control",
  "HOSP_LOCTEACH", 1, "Rural", "Hospital location and teaching status",
  "HOSP_LOCTEACH", 2, "Urban, non-teaching", "Hospital location and teaching status",
  "HOSP_LOCTEACH", 3, "Urban, teaching", "Hospital location and teaching status",
  "APRDRG_RISK_MORTALITY", 0, "None specified", "APR-DRG risk of mortality",
  "APRDRG_RISK_MORTALITY", 1, "Minor", "APR-DRG risk of mortality",
  "APRDRG_RISK_MORTALITY", 2, "Moderate", "APR-DRG risk of mortality",
  "APRDRG_RISK_MORTALITY", 3, "Major", "APR-DRG risk of mortality",
  "APRDRG_RISK_MORTALITY", 4, "Extreme", "APR-DRG risk of mortality",
  "APRDRG_SEVERITY", 0, "None specified", "APR-DRG severity of illness",
  "APRDRG_SEVERITY", 1, "Minor", "APR-DRG severity of illness",
  "APRDRG_SEVERITY", 2, "Moderate", "APR-DRG severity of illness",
  "APRDRG_SEVERITY", 3, "Major", "APR-DRG severity of illness",
  "APRDRG_SEVERITY", 4, "Extreme", "APR-DRG severity of illness",
  "I10_BIRTH", 0, "No", "ICD-10-CM birth indicator",
  "I10_BIRTH", 1, "Yes", "ICD-10-CM birth indicator",
  "I10_DELIVERY", 0, "No", "ICD-10-CM delivery indicator",
  "I10_DELIVERY", 1, "Yes", "ICD-10-CM delivery indicator",
  "I10_INJURY", 0, "No", "Injury ICD-10-CM diagnosis indicator",
  "I10_INJURY", 1, "Yes", "Injury ICD-10-CM diagnosis indicator",
  "I10_MULTINJURY", 0, "No", "Multiple injury indicator",
  "I10_MULTINJURY", 1, "Yes", "Multiple injury indicator",
  "I10_SERVICELINE", 0, "No", "ICD-10-CM/PCS service line indicator",
  "I10_SERVICELINE", 1, "Yes", "ICD-10-CM/PCS service line indicator",
  "PCLASS_ORPROC", 0, "No", "ICD-10-PCS major operating room procedure indicator",
  "PCLASS_ORPROC", 1, "Yes", "ICD-10-PCS major operating room procedure indicator",
  "AGE", NA_real_, NA_character_, "Age, years",
  "LOS", NA_real_, NA_character_, "Length of stay, days",
  "TOTCHG", NA_real_, NA_character_, "Total charges, USD",
  "CCR_NIS", NA_real_, NA_character_, "Cost-to-charge ratio",
  "YEAR", NA_real_, NA_character_, "Discharge year",
  "DISCWT", NA_real_, NA_character_, "Discharge weight",
  "HOSP_NIS", NA_real_, NA_character_, "NIS hospital identifier",
  "NIS_STRATUM", NA_real_, NA_character_, "NIS stratum",
  "elixsum", NA_real_, NA_character_, "Elixhauser comorbidity score",
  "charlindex", NA_real_, NA_character_, "Charlson comorbidity index",
  "ELIXSUM", NA_real_, NA_character_, "Elixhauser comorbidity score",
  "CHARLINDEX", NA_real_, NA_character_, "Charlson comorbidity index"
)
attr(.hcup_labels, "source") <- paste(
  "HCUP 2020 NIS Introduction, Appendix III, Data Elements;",
  "local analyst recoding helper cross-check"
)

#' Apply HCUP labels and common missing-value handling
#'
#' @param data A collected data frame.
#'
#' @return `data` with known coded elements as factors and variable labels in
#'   `attr(x, "label")`. Existing labels and labelled comorbidity fields are
#'   preserved. The operation is idempotent.
#' @export
nis_label <- function(data) {
  if (!is.data.frame(data)) {
    cli::cli_abort("`data` must be a collected data frame.")
  }
  missing_codes <- c(-9, -8, -6, -5)
  design_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "CCR_NIS")

  for (variable in names(data)) {
    if (startsWith(variable, ".")) next
    x <- data[[variable]]
    definition <- .hcup_labels[.hcup_labels$variable == variable, , drop = FALSE]
    value_rows <- !is.na(definition$code)

    if (is.numeric(x) && !variable %in% design_fields) {
      x[x %in% missing_codes] <- NA
    }

    if (any(value_rows)) {
      codes <- as.character(definition$code[value_rows])
      values <- definition$value_label[value_rows]
      if (is.factor(x) && all(is.na(x) | as.character(x) %in% values)) {
        x <- factor(as.character(x), levels = unique(values))
      } else {
        x <- factor(as.character(x), levels = codes, labels = values)
      }
    } else if (is.logical(x)) {
      x <- factor(ifelse(is.na(x), NA_character_, ifelse(x, "Yes", "No")),
        levels = c("No", "Yes"))
    }

    variable_label <- if (nrow(definition) > 0L) {
      definition$variable_label[[1L]]
    } else {
      NULL
    }
    old_label <- attr(data[[variable]], "label", exact = TRUE)
    data[[variable]] <- x
    if (!is.null(old_label)) {
      attr(data[[variable]], "label") <- old_label
    } else if (!is.null(variable_label)) {
      attr(data[[variable]], "label") <- variable_label
    }
  }
  data
}
