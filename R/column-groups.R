#' Select NIS column groups
#'
#' Use these helpers inside [dplyr::select()] and easyNIS tidy-select
#' arguments, such as `keep` in [nis_design()] or `columns` in
#' [nis_join_companion()]. Groups use HCUP field names from 2012 onward.
#' Each helper selects the columns present in the input. Combine groups
#' with `c()` or exclude them with `-`.
#'
#' - `nis_vars_design()` selects `YEAR`, `HOSP_NIS`, `NIS_STRATUM`,
#'   `DISCWT`, and `DQTR` when available. Include it when projecting a table
#'   before building a design. [nis_design()] checks the four required fields
#'   and errors if any are missing. `DQTR` supports 2015 coverage checks.
#' - `nis_vars_demographics()` selects age, neonatal age indicator, sex,
#'   race, expected primary payer, ZIP income quartile, and the applicable
#'   urban-rural field.
#' - `nis_vars_dx()` selects numbered ICD-9 and ICD-10 diagnosis, external
#'   cause, and present-on-admission fields, plus diagnosis counts and
#'   `DXVER` when present.
#' - `nis_vars_pr()` selects numbered ICD-9 and ICD-10 procedure and
#'   procedure-day fields, plus procedure counts and `PRVER` when present.
#' - `nis_vars_hospital()` selects the hospital identifier and bed size,
#'   ownership, location/teaching, region, and division fields. Availability
#'   depends on the release and whether the Hospital file was joined.
#'
#' These helpers match names and do not check how the fields were coded.
#' Diagnosis and procedure groups do not include derived classification
#' fields such as CCS or CCSR.
#'
#' @return Tidyselect column positions for the current selection.
#' @family data-access
#' @seealso [Prepare annual NIS files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html),
#'   [HCUP NIS File Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp),
#'   [HCUP NIS Description of Data Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019))
#' dplyr::select(nis, nis_vars_design(), nis_vars_demographics(), LOS)
#' dplyr::select(nis, c(nis_vars_dx(), nis_vars_pr()))
#' dplyr::select(nis, -nis_vars_pr())
nis_vars_design <- function() {
  tidyselect::any_of(c(.nis_design_fields, "DQTR"))
}

#' @rdname nis_vars_design
#' @export
nis_vars_demographics <- function() {
  tidyselect::any_of(c(
    "AGE",
    "AGE_NEONATE",
    "FEMALE",
    "RACE",
    "PAY1",
    "ZIPINC_QRTL",
    "PL_NCHS2006",
    "PL_NCHS",
    "PL_NCHS2"
  ))
}

#' @rdname nis_vars_design
#' @export
nis_vars_dx <- function() {
  tidyselect::matches(
    "^((I10_DX|DX|DXPOA|ECODE|I10_ECAUSE)[1-9][0-9]*|NDX|I10_NDX|NECODE|I10_NECAUSE|DXVER)$",
    ignore.case = FALSE
  )
}

#' @rdname nis_vars_design
#' @export
nis_vars_pr <- function() {
  tidyselect::matches(
    "^((I10_PR|PR|PRDAY)[1-9][0-9]*|NPR|I10_NPR|PRVER)$",
    ignore.case = FALSE
  )
}

#' @rdname nis_vars_design
#' @export
nis_vars_hospital <- function() {
  tidyselect::any_of(c(
    "HOSP_NIS",
    "HOSP_BEDSIZE",
    "H_CONTRL",
    "HOSP_LOCTEACH",
    "HOSP_REGION",
    "HOSP_DIVISION"
  ))
}
