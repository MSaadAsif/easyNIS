#' Generate entirely invented discharge components
#'
#' Create a small deterministic fixture without reading files, using random
#' numbers, or changing the random seed. Values, slot counts, and optional
#' component patterns are test choices, not audited annual HCUP layouts.
#' Codes beginning with `SYN_` and the string `"001"` are test tokens, not a
#' reviewed clinical code set. Do not use these records for clinical inference.
#'
#' @param year A single whole numeric year from 2017 through 2022. It labels
#'   the fixture; it does not assert that the year's real files are supported.
#' @return A list with `core`, `hospital`, `severity`, `diagnosis_procedure_groups`,
#'   `expected`, and `provenance`. Components are data frames; the groups
#'   component is `NULL` for the 2017 fixture. `expected` contains hand-calculated
#'   raw counts and weighted point summaries for future validation. These are
#'   not survey estimates or validated standard errors. Identifiers are strings
#'   so leading zeros and integers larger than double precision remain exact.
#' @export
#' @examples
#' fixture <- nis_synthetic_data(2022)
#' names(fixture)
#' head(fixture$core)
#' sum(fixture$core$DISCWT)
#' fixture$expected$weighted_discharges
nis_synthetic_data <- function(year = 2022L) {
  if (length(year) != 1L) {
    stop("`year` must be one fixture year from 2017 through 2022.",
         call. = FALSE)
  }
  validate_years(year)
  if (!year %in% 2017:2022) {
    stop("`year` must be one fixture year from 2017 through 2022.",
         call. = FALSE)
  }
  year <- as.integer(year)
  hospital_ids <- sprintf("%04d", 1:4)
  core <- data.frame(
    YEAR = rep(year, 12L),
    KEY_NIS = paste0("900719925474", sprintf("%04d", 1001:1012)),
    HOSP_NIS = rep(hospital_ids, each = 3L),
    NIS_STRATUM = rep(c(1L, 2L), each = 6L),
    DISCWT = rep(c(2, 3, 4), 4L),
    AGE = c(rep(c(20L, 40L, 60L), 3L), 20L, 40L, NA_integer_),
    FEMALE = rep(c(0L, 1L, NA_integer_), 4L),
    DIED = rep(c(0L, 1L, NA_integer_), 4L),
    LOS = rep(c(0L, 2L, 4L), 4L),
    TOTCHG = rep(c(1000, 2000, NA_real_), 4L),
    stringsAsFactors = FALSE
  )
  diagnosis_slots <- 2L + (year - 2017L) %% 3L
  procedure_slots <- 1L + (year - 2017L) %% 2L
  for (slot in seq_len(diagnosis_slots)) {
    core[[paste0("I10_DX", slot)]] <- if (slot == 1L) {
      rep(c("SYN_DX_A", "SYN_DX_B", NA_character_), 4L)
    } else {
      rep(c(NA_character_, "001", "SYN_DX_A"), 4L)
    }
  }
  for (slot in seq_len(procedure_slots)) {
    core[[paste0("I10_PR", slot)]] <- rep(c("SYN_PR_A", NA_character_, "001"), 4L)
  }
  hospital <- data.frame(
    YEAR = rep(year, 4L), HOSP_NIS = hospital_ids,
    NIS_STRATUM = c(1L, 1L, 2L, 2L),
    HOSP_BEDSIZE = c(1L, 2L, 1L, 3L), stringsAsFactors = FALSE
  )
  severity <- data.frame(
    YEAR = core$YEAR, KEY_NIS = core$KEY_NIS,
    SYN_SEVERITY = rep(c(1L, 2L, NA_integer_), 4L),
    stringsAsFactors = FALSE
  )
  groups <- if (year == 2017L) NULL else data.frame(
    YEAR = core$YEAR, KEY_NIS = core$KEY_NIS,
    SYN_DX_GROUP = rep(c("A", "B", NA_character_), 4L),
    stringsAsFactors = FALSE
  )
  list(
    core = core, hospital = hospital, severity = severity,
    diagnosis_procedure_groups = groups,
    expected = list(
      discharges = 12L, hospitals = 4L, strata = 2L,
      weighted_discharges = 36, observed_died_discharges = 8L,
      observed_died_weight = 20, weighted_deaths = 12,
      died_proportion_observed = 0.6, observed_age_weight = 32,
      age_mean_observed = 42.5, diagnosis_slots = diagnosis_slots,
      procedure_slots = procedure_slots
    ),
    provenance = list(
      origin = "entirely_invented", generator_version = "1",
      year = year, layout = "unaudited_test_layout",
      clinical_codes = FALSE,
      note = "No HCUP records or record-derived values were used."
    )
  )
}
