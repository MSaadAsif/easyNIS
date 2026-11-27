#' Map comorbidity output flags to distinct conditions
#'
#' Inspect the condition IDs used by [nis_comorbidity()] when
#' `count_distinct = TRUE`. A flag that represents multiple conditions has
#' one row per component. Severity variants share an ID. For example,
#' both diabetes flags map to `diabetes`, and refined Elixhauser's solid
#' tumor and metastatic cancer flags map to `solid_cancer`. Leukemia and
#' lymphoma retain separate IDs.
#'
#' The map describes the emitted flags, including medicalcoder combination
#' and compatibility flags. For example, `hfhtn_cxrenlfl_sev` maps to heart
#' failure (`hf`), `hypertension`, and `renal_failure`. The count takes the
#' union of the conditions represented by true flags. It applies no further
#' hierarchy or present-on-admission adjudication.
#'
#' @inheritParams nis_comorbidity
#' @return A data frame with character columns `output` (the prefixed
#'   logical column name) and `condition` (the unprefixed ID to count or
#'   exclude). The map omits summary counts, indices, and the `any` flag.
#' @references
#'   AHRQ HCUP. [Elixhauser Comorbidity Software Refined for ICD-10-CM](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/comorbidity_icd10.jsp).
#'
#'   Dewitt PE. [medicalcoder](https://github.com/dewittpe/medicalcoder),
#'   version 0.10.0. The combination flag names and decomposition follow
#'   the package's refined Elixhauser mappings.
#'
#'   Quan H et al. [Coding algorithms for defining comorbidities in ICD-9-CM
#'   and ICD-10 administrative data](https://pubmed.ncbi.nlm.nih.gov/16224307/).
#'   Med Care. 2005;43(11):1130–1139.
#' @family comorbidity
#' @export
#' @examples
#' nis_comorbidity_condition_map("elixhauser_ahrq2027", prefix = "risk_")
nis_comorbidity_condition_map <- function(method = "elixhauser_ahrq_icd10", prefix = "cmrb_") {
  nis_comorbidity_check_prefix(prefix)
  map <- nis_cmrb_condition_map(nis_comorbidity_spec(method))
  map$output <- paste0(prefix, tolower(map$output))
  map
}

nis_cmrb_condition_map <- function(spec) {
  components <- c(spec$evidence$always, spec$evidence$positive)
  components <- components[names(components) %in% spec$conditions]
  single <- setdiff(spec$conditions, names(components))
  output <- c(single, names(components))
  condition <- c(single, unname(components))
  groups <- c(
    DIAB_CX = "diabetes",
    DIAB_UNCX = "diabetes",
    DM = "diabetes",
    DMCX = "diabetes",
    dm = "diabetes",
    dmc = "diabetes",
    HTN_C = "hypertension",
    HTN_CX = "hypertension",
    HTN_UNCX = "hypertension",
    CANCER_METS = "solid_cancer",
    CANCER_NSITU = "solid_cancer",
    CANCER_SOLID = "solid_cancer",
    METS = "solid_cancer",
    TUMOR = "solid_cancer",
    mal = "solid_cancer",
    mst = "solid_cancer",
    LIVER_MLD = "liver_disease",
    LIVER_SEV = "liver_disease",
    LIVER = "liver_disease",
    mld = "liver_disease",
    msld = "liver_disease",
    RENLFL_MOD = "renal_failure",
    RENLFL_SEV = "renal_failure",
    RENLFAIL = "renal_failure",
    CBVD_POA = "cbvd",
    CBVD_SQLA = "cbvd"
  )
  group <- unname(groups[condition])
  group[is.na(group)] <- tolower(condition[is.na(group)])
  unique(data.frame(output = output, condition = group))
}

nis_cmrb_count_groups <- function(spec, count_distinct, exclude_conditions) {
  if (!rlang::is_bool(count_distinct)) {
    cli::cli_abort("`count_distinct` must be TRUE or FALSE.")
  }
  if (!is.vector(exclude_conditions, mode = "character") || anyNA(exclude_conditions)) {
    cli::cli_abort("`exclude_conditions` must be a character vector without missing values.")
  }
  if (!count_distinct) {
    if (length(exclude_conditions)) {
      cli::cli_abort("`exclude_conditions` requires `count_distinct = TRUE`.")
    }
    return(NULL)
  }
  map <- nis_cmrb_condition_map(spec)
  unknown <- setdiff(exclude_conditions, map$condition)
  if (length(unknown)) {
    cli::cli_abort(c(
      "Unknown condition ID{?s} in `exclude_conditions`: {.val {unknown}}.",
      i = "See `nis_comorbidity_condition_map()` for the selected method's condition IDs."
    ))
  }
  map <- map[!map$condition %in% exclude_conditions, ]
  split(map$output, map$condition)
}
